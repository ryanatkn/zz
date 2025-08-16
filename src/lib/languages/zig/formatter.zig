const std = @import("std");
const ts = @import("tree-sitter");
const FormatterOptions = @import("../../parsing/formatter.zig").FormatterOptions;
const LineBuilder = @import("../../parsing/formatter.zig").LineBuilder;

// Legacy format function for backwards compatibility - delegates to AST formatter
pub fn format(allocator: std.mem.Allocator, source: []const u8, options: FormatterOptions) ![]const u8 {
    // TODO: This will be removed once we fully transition to AST-only formatting
    // For now, return error to force use of AST formatter
    _ = allocator;
    _ = source;
    _ = options;
    return error.UnsupportedOperation;
}

// AST-based Zig formatting

/// Format Zig using AST-based approach
pub fn formatAst(allocator: std.mem.Allocator, node: ts.Node, source: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
    _ = allocator;
    std.debug.print("[DEBUG] Zig formatAst called\n", .{});
    try formatZigNode(node, source, builder, 0, options);
}

/// Zig node formatting with controlled recursion
fn formatZigNode(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) std.mem.Allocator.Error!void {
    const node_type = node.kind();
    const node_text = getNodeText(node, source);

    // Debug: Print node type to diagnose issues
    if (depth <= 1) {
        std.debug.print("[DEBUG] Zig Node at depth {d}: {s}\n", .{ depth, node_type });
    }

    // Use same logic as the visitor to identify node types
    if (std.mem.eql(u8, node_type, "VarDecl")) {
        // Check what kind of VarDecl this is
        if (isFunctionDecl(node_text)) {
            try formatZigFunction(node, source, builder, depth, options);
        } else if (isTypeDecl(node_text)) {
            try formatZigStruct(node, source, builder, depth, options);
        } else if (isImportDecl(node_text)) {
            try formatZigImport(node, source, builder, depth, options);
        } else {
            try formatZigVariable(node, source, builder, depth, options);
        }
    } else if (std.mem.eql(u8, node_type, "TestDecl")) {
        try formatZigTest(node, source, builder, depth, options);
    } else if (std.mem.eql(u8, node_type, "Decl")) {
        // Handle Decl nodes (similar to VarDecl but different tree-sitter node type)
        if (isFunctionDecl(node_text)) {
            try formatZigFunction(node, source, builder, depth, options);
        } else if (isTypeDecl(node_text)) {
            try formatZigStruct(node, source, builder, depth, options);
        } else if (isImportDecl(node_text)) {
            try formatZigImport(node, source, builder, depth, options);
        } else {
            try formatZigVariable(node, source, builder, depth, options);
        }
    } else if (std.mem.eql(u8, node_type, "source_file")) {
        // For container nodes, recurse into children with spacing
        const child_count = node.childCount();
        var i: u32 = 0;
        var prev_was_decl = false;
        
        while (i < child_count) : (i += 1) {
            if (node.child(i)) |child| {
                const child_type = child.kind();
                const child_text = getNodeText(child, source);
                
                // Handle pub + following declaration as a single unit
                if (std.mem.eql(u8, child_type, "pub") and i + 1 < child_count) {
                    if (node.child(i + 1)) |next_child| {
                        const next_type = next_child.kind();
                        const next_text = getNodeText(next_child, source);
                        
                        // Add spacing before pub declaration
                        if (prev_was_decl) {
                            try builder.newline();
                        }
                        
                        // Combine pub + declaration
                        try formatPubDecl(child_text, next_text, next_type, source, builder, depth, options);
                        
                        prev_was_decl = true;
                        i += 1; // Skip the next node since we processed it
                        continue;
                    }
                }
                
                // Add spacing between top-level declarations
                if (prev_was_decl and isTopLevelDecl(child_type, child_text)) {
                    try builder.newline();
                }
                
                try formatZigNode(child, source, builder, depth, options);
                
                prev_was_decl = isTopLevelDecl(child_type, child_text);
            }
        }
    } else {
        // For unknown nodes, just append text without recursion
        try appendNodeText(node, source, builder);
    }
}

/// Check if this VarDecl represents a function
fn isFunctionDecl(text: []const u8) bool {
    const contains_fn = std.mem.indexOf(u8, text, "fn ") != null;
    const not_import = std.mem.indexOf(u8, text, "@import") == null;
    const not_type_def = std.mem.indexOf(u8, text, "struct") == null and
                         std.mem.indexOf(u8, text, "enum") == null and
                         std.mem.indexOf(u8, text, "union") == null;
    return contains_fn and not_import and not_type_def;
}

/// Check if this VarDecl represents a type definition
fn isTypeDecl(text: []const u8) bool {
    const trimmed = std.mem.trim(u8, text, " \t\n\r");
    if (std.mem.startsWith(u8, trimmed, "const ") or std.mem.startsWith(u8, trimmed, "pub const ")) {
        return std.mem.indexOf(u8, text, "struct") != null or
               std.mem.indexOf(u8, text, "enum") != null or
               std.mem.indexOf(u8, text, "union") != null;
    }
    return false;
}

/// Check if this VarDecl represents an import
fn isImportDecl(text: []const u8) bool {
    return std.mem.indexOf(u8, text, "@import") != null;
}

/// Extract struct name from declaration text like "const Point = struct"
fn extractStructName(text: []const u8) ?[]const u8 {
    const trimmed = std.mem.trim(u8, text, " \t\n\r");
    
    // Handle both "const Name = struct" and "pub const Name = struct"
    var start_pos: usize = 0;
    if (std.mem.startsWith(u8, trimmed, "pub const ")) {
        start_pos = 10; // length of "pub const "
    } else if (std.mem.startsWith(u8, trimmed, "const ")) {
        start_pos = 6; // length of "const "
    } else {
        return null;
    }
    
    // Find the end of the name (before " = struct")
    if (std.mem.indexOfPos(u8, trimmed, start_pos, " =")) |equals_pos| {
        const name = std.mem.trim(u8, trimmed[start_pos..equals_pos], " \t");
        if (name.len > 0) {
            return name;
        }
    }
    
    return null;
}

/// Format struct declaration with proper spacing
fn formatStructDeclaration(struct_text: []const u8, builder: *LineBuilder) !void {
    const trimmed = std.mem.trim(u8, struct_text, " \t\n\r");
    
    // Find "=struct" to separate declaration from body
    if (std.mem.indexOf(u8, trimmed, "=struct")) |struct_pos| {
        const declaration = std.mem.trim(u8, trimmed[0..struct_pos], " \t");
        // Add proper spacing around keywords and identifiers
        try formatZigDeclaration(declaration, builder);
    } else {
        // Fallback: just append the text
        try builder.append(trimmed);
    }
}

/// Format Zig declaration with spacing around keywords
fn formatZigDeclaration(declaration: []const u8, builder: *LineBuilder) !void {
    var i: usize = 0;
    while (i < declaration.len) : (i += 1) {
        const char = declaration[i];
        
        // Handle "pub const" or "const"
        if (declaration.len > i + 2 and std.mem.eql(u8, declaration[i..i+3], "pub")) {
            try builder.append("pub ");
            i += 2; // Will be incremented by loop
            // Skip any following whitespace
            while (i + 1 < declaration.len and (declaration[i + 1] == ' ' or declaration[i + 1] == '\t')) {
                i += 1;
            }
        } else if (declaration.len > i + 4 and std.mem.eql(u8, declaration[i..i+5], "const")) {
            try builder.append("const ");
            i += 4; // Will be incremented by loop
            // Skip any following whitespace
            while (i + 1 < declaration.len and (declaration[i + 1] == ' ' or declaration[i + 1] == '\t')) {
                i += 1;
            }
        } else if (char != ' ' and char != '\t') {
            // Regular character, append as-is
            try builder.append(&[_]u8{char});
        } else if (char == ' ') {
            // Preserve single spaces, skip multiple
            if (i == 0 or declaration[i-1] != ' ') {
                try builder.append(" ");
            }
        }
    }
}

/// Check if node represents a top-level declaration that needs spacing
fn isTopLevelDecl(node_type: []const u8, text: []const u8) bool {
    if (std.mem.eql(u8, node_type, "VarDecl") or std.mem.eql(u8, node_type, "Decl")) {
        return isFunctionDecl(text) or isTypeDecl(text) or isImportDecl(text);
    }
    return std.mem.eql(u8, node_type, "TestDecl");
}

/// Format a pub declaration by combining pub keyword with following declaration
fn formatPubDecl(pub_text: []const u8, decl_text: []const u8, decl_type: []const u8, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
    _ = source;
    _ = depth;
    _ = options;
    
    // Combine pub + declaration text
    const combined_text = try std.fmt.allocPrint(builder.allocator, "{s} {s}", .{ pub_text, decl_text });
    defer builder.allocator.free(combined_text);
    
    // Format based on the declaration type
    if (std.mem.eql(u8, decl_type, "Decl") and isFunctionDecl(combined_text)) {
        try builder.appendIndent();
        try formatFunctionWithSpacing(combined_text, builder);
        try builder.newline();
    } else {
        // Fallback - format with basic spacing
        try builder.appendIndent();
        try formatWithBasicSpacing(combined_text, builder);
        try builder.newline();
    }
}

/// Format Zig function
fn formatZigFunction(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) std.mem.Allocator.Error!void {
    _ = depth;
    _ = options;
    
    const func_text = getNodeText(node, source);
    try builder.appendIndent();
    
    // Parse and format the function with proper spacing
    try formatFunctionWithSpacing(func_text, builder);
    try builder.newline();
}

/// Format function with proper spacing around parentheses, return types, and braces
fn formatFunctionWithSpacing(func_text: []const u8, builder: *LineBuilder) !void {
    // Find key positions
    var fn_pos: ?usize = null;
    var paren_pos: ?usize = null;
    var brace_pos: ?usize = null;
    
    // Find "fn " position - handle both "fn " and "pubfn" cases
    if (std.mem.indexOf(u8, func_text, "fn ")) |pos| {
        fn_pos = pos;
    } else if (std.mem.indexOf(u8, func_text, "fn")) |pos| {
        // Handle concatenated case like "pubfn"
        fn_pos = pos;
    }
    
    // Find opening parenthesis
    if (fn_pos) |fn_start| {
        if (std.mem.indexOfPos(u8, func_text, fn_start, "(")) |pos| {
            paren_pos = pos;
        }
    }
    
    // Find opening brace
    if (std.mem.indexOf(u8, func_text, "{")) |pos| {
        brace_pos = pos;
    }
    
    if (fn_pos != null and paren_pos != null and brace_pos != null) {
        // Format signature part (up to opening brace)
        const signature = func_text[0..brace_pos.?];
        try formatFunctionSignature(signature, builder);
        
        try builder.append(" {");
        
        // Format body (simplified - just indent it)
        const body = func_text[brace_pos.? + 1..];
        if (body.len > 1) { // More than just closing brace
            try builder.newline();
            builder.indent();
            try builder.appendIndent();
            
            // Extract body content (remove closing brace and format)
            const body_content = std.mem.trim(u8, body[0..body.len-1], " \t\n\r");
            if (body_content.len > 0) {
                try formatFunctionBody(body_content, builder);
            }
            
            builder.dedent();
            try builder.newline();
            try builder.appendIndent();
        }
        try builder.append("}");
    } else {
        // Fallback - just add basic spacing
        try formatWithBasicSpacing(func_text, builder);
    }
}

/// Format function signature with proper spacing
fn formatFunctionSignature(signature: []const u8, builder: *LineBuilder) !void {
    // First handle the pub fn keyword spacing
    if (std.mem.indexOf(u8, signature, "pubfn")) |pos| {
        // Replace "pubfn" with "pub fn"
        try builder.append(signature[0..pos]);
        try builder.append("pub fn");
        
        // Continue with the rest after "pubfn"
        const rest = signature[pos + 5..];
        try formatSignatureRest(rest, builder);
        return;
    }
    
    // Regular character-by-character formatting
    var i: usize = 0;
    while (i < signature.len) : (i += 1) {
        const char = signature[i];
        if (char == '(') {
            try builder.append(&[_]u8{char});
        } else if (char == ')') {
            try builder.append(&[_]u8{char});
            // Add space after ) if followed by non-space (return type)
            if (i + 1 < signature.len and signature[i + 1] != ' ' and signature[i + 1] != '{') {
                try builder.append(" ");
            }
        } else if (char == ':') {
            try builder.append(&[_]u8{char});
            // Add space after : if not present
            if (i + 1 < signature.len and signature[i + 1] != ' ') {
                try builder.append(" ");
            }
        } else if (char == ',') {
            try builder.append(&[_]u8{char});
            // Add space after , if not present
            if (i + 1 < signature.len and signature[i + 1] != ' ') {
                try builder.append(" ");
            }
        } else {
            try builder.append(&[_]u8{char});
        }
    }
}

/// Format the rest of the signature after keywords
fn formatSignatureRest(rest: []const u8, builder: *LineBuilder) !void {
    var i: usize = 0;
    while (i < rest.len) : (i += 1) {
        const char = rest[i];
        if (char == '(') {
            try builder.append(&[_]u8{char});
        } else if (char == ')') {
            try builder.append(&[_]u8{char});
            // Add space after ) if followed by non-space (return type)
            if (i + 1 < rest.len and rest[i + 1] != ' ' and rest[i + 1] != '{') {
                try builder.append(" ");
            }
        } else if (char == ':') {
            try builder.append(&[_]u8{char});
            // Add space after : if not present
            if (i + 1 < rest.len and rest[i + 1] != ' ') {
                try builder.append(" ");
            }
        } else if (char == ',') {
            try builder.append(&[_]u8{char});
            // Add space after , if not present
            if (i + 1 < rest.len and rest[i + 1] != ' ') {
                try builder.append(" ");
            }
        } else {
            try builder.append(&[_]u8{char});
        }
    }
}

/// Format function body with proper spacing and statement expansion
fn formatFunctionBody(body: []const u8, builder: *LineBuilder) !void {
    // Split into statements by semicolon
    var statements = std.ArrayList([]const u8).init(builder.allocator);
    defer statements.deinit();
    
    var start: usize = 0;
    var i: usize = 0;
    while (i < body.len) : (i += 1) {
        if (body[i] == ';') {
            const statement = std.mem.trim(u8, body[start..i], " \t\n\r");
            if (statement.len > 0) {
                try statements.append(statement);
            }
            start = i + 1;
        }
    }
    
    // Add final statement if no trailing semicolon
    if (start < body.len) {
        const statement = std.mem.trim(u8, body[start..], " \t\n\r");
        if (statement.len > 0) {
            try statements.append(statement);
        }
    }
    
    // Format each statement
    for (statements.items, 0..) |statement, idx| {
        try formatZigStatement(statement, builder);
        
        // Add semicolon - return statements always need semicolons
        try builder.append(";");
        
        // Add newline between statements
        if (idx < statements.items.len - 1) {
            try builder.newline();
            try builder.appendIndent();
        }
    }
}

/// Format a single Zig statement with proper spacing and expansion
fn formatZigStatement(statement: []const u8, builder: *LineBuilder) !void {
    // Check if this is a return statement with struct literal
    if (std.mem.startsWith(u8, statement, "return ") and std.mem.indexOf(u8, statement, "{") != null) {
        try formatReturnWithStruct(statement, builder);
    } else {
        // Regular statement with operator spacing
        try formatStatementWithSpacing(statement, builder);
    }
}

/// Format return statement with struct literal expansion
fn formatReturnWithStruct(statement: []const u8, builder: *LineBuilder) !void {
    // Find the struct literal part
    if (std.mem.indexOf(u8, statement, "{")) |brace_start| {
        // Format "return StructName"
        const return_part = std.mem.trim(u8, statement[0..brace_start], " \t");
        try formatStatementWithSpacing(return_part, builder);
        try builder.append("{");
        try builder.newline();
        
        builder.indent();
        
        // Extract and format struct fields
        const struct_end = std.mem.lastIndexOf(u8, statement, "}") orelse statement.len;
        const struct_content = std.mem.trim(u8, statement[brace_start + 1..struct_end], " \t\n\r");
        
        if (struct_content.len > 0) {
            // Split by comma and format each field
            var field_start: usize = 0;
            var j: usize = 0;
            while (j < struct_content.len) : (j += 1) {
                if (struct_content[j] == ',') {
                    const field = std.mem.trim(u8, struct_content[field_start..j], " \t\n\r");
                    if (field.len > 0) {
                        try builder.appendIndent();
                        try formatStatementWithSpacing(field, builder);
                        try builder.append(",");
                        try builder.newline();
                    }
                    field_start = j + 1;
                }
            }
            
            // Add final field if no trailing comma
            if (field_start < struct_content.len) {
                const field = std.mem.trim(u8, struct_content[field_start..], " \t\n\r");
                if (field.len > 0) {
                    try builder.appendIndent();
                    try formatStatementWithSpacing(field, builder);
                    try builder.append(",");
                    try builder.newline();
                }
            }
        }
        
        builder.dedent();
        try builder.appendIndent();
        try builder.append("}");
    } else {
        // No struct literal, just format normally
        try formatStatementWithSpacing(statement, builder);
    }
}

/// Format statement with proper spacing around operators
fn formatStatementWithSpacing(statement: []const u8, builder: *LineBuilder) !void {
    var i: usize = 0;
    while (i < statement.len) : (i += 1) {
        const char = statement[i];
        
        if (char == '=') {
            // Add spaces around = but not for == (equality)
            if (i + 1 < statement.len and statement[i + 1] == '=') {
                // This is == (equality), don't add spaces individually
                try builder.append("==");
                i += 1; // Skip the next =
            } else {
                // Single = (assignment), add spaces
                if (i > 0 and statement[i-1] != ' ') {
                    try builder.append(" ");
                }
                try builder.append(&[_]u8{char});
                if (i + 1 < statement.len and statement[i + 1] != ' ') {
                    try builder.append(" ");
                }
            }
        } else if (char == '+' or char == '-' or char == '*') {
            // Add spaces around arithmetic operators
            if (i > 0 and statement[i-1] != ' ') {
                try builder.append(" ");
            }
            try builder.append(&[_]u8{char});
            if (i + 1 < statement.len and statement[i + 1] != ' ') {
                try builder.append(" ");
            }
        } else if (char == '@') {
            // Add space before @ functions
            if (i > 0 and statement[i-1] != ' ') {
                try builder.append(" ");
            }
            try builder.append(&[_]u8{char});
        } else if (char == ',') {
            // Add space after comma if not present
            try builder.append(&[_]u8{char});
            if (i + 1 < statement.len and statement[i + 1] != ' ') {
                try builder.append(" ");
            }
        } else {
            try builder.append(&[_]u8{char});
        }
    }
}

/// Format test with proper spacing and body expansion
fn formatTestWithSpacing(test_text: []const u8, builder: *LineBuilder) !void {
    // Find test name between "test" and "{"
    if (std.mem.indexOf(u8, test_text, "test")) |test_pos| {
        if (std.mem.indexOf(u8, test_text, "{")) |brace_pos| {
            const test_part = std.mem.trim(u8, test_text[test_pos..brace_pos], " \t");
            
            // Format "test" keyword and name with proper spacing
            if (std.mem.indexOf(u8, test_part, "\"")) |quote_start| {
                const before_quote = std.mem.trim(u8, test_part[0..quote_start], " \t");
                const after_quote = std.mem.trim(u8, test_part[quote_start..], " \t");
                
                try builder.append(before_quote);
                try builder.append(" ");
                try builder.append(after_quote);
            } else {
                try formatStatementWithSpacing(test_part, builder);
            }
            
            try builder.append(" {");
            try builder.newline();
            
            // Format test body
            const body_end = std.mem.lastIndexOf(u8, test_text, "}") orelse test_text.len;
            const body_content = std.mem.trim(u8, test_text[brace_pos + 1..body_end], " \t\n\r");
            
            if (body_content.len > 0) {
                try formatFunctionBody(body_content, builder);
            }
            
            try builder.append("}");
        } else {
            // No body, just format as basic statement
            try formatStatementWithSpacing(test_text, builder);
        }
    } else {
        // Fallback
        try formatStatementWithSpacing(test_text, builder);
    }
}

/// Fallback formatting with basic spacing
fn formatWithBasicSpacing(text: []const u8, builder: *LineBuilder) !void {
    var i: usize = 0;
    while (i < text.len) : (i += 1) {
        const char = text[i];
        if (char == '=' and i + 1 < text.len and text[i + 1] != ' ') {
            // Add space before = if not present
            if (i > 0 and text[i-1] != ' ') {
                try builder.append(" ");
            }
            try builder.append(&[_]u8{char});
            try builder.append(" ");
        } else {
            try builder.append(&[_]u8{char});
        }
    }
}

/// Format Zig struct
fn formatZigStruct(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) std.mem.Allocator.Error!void {
    try builder.appendIndent();

    // Parse and format the complete struct declaration
    const struct_text = getNodeText(node, source);
    try formatStructDeclaration(struct_text, builder);

    try builder.append(" = struct {");
    try builder.newline();

    // Navigate to the actual struct body (ContainerDecl)
    const container_decl = findContainerDecl(node);
    if (container_decl) |container| {
        // Format struct body
        builder.indent();
        try formatStructBody(container, source, builder, depth + 1, options);
        builder.dedent();
    }

    try builder.appendIndent();
    try builder.append("};");
    try builder.newline();
}

/// Find the ContainerDecl node within the struct definition
fn findContainerDecl(node: ts.Node) ?ts.Node {
    // Navigate: Decl -> VarDecl -> ErrorUnionExpr -> SuffixExpr -> ContainerDecl
    const child_count = node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        if (node.child(i)) |child| {
            if (std.mem.eql(u8, child.kind(), "VarDecl")) {
                // Look for ErrorUnionExpr in VarDecl children
                const vardecl_child_count = child.childCount();
                var j: u32 = 0;
                while (j < vardecl_child_count) : (j += 1) {
                    if (child.child(j)) |grandchild| {
                        if (std.mem.eql(u8, grandchild.kind(), "ErrorUnionExpr")) {
                            // Look for SuffixExpr in ErrorUnionExpr children
                            const error_child_count = grandchild.childCount();
                            var k: u32 = 0;
                            while (k < error_child_count) : (k += 1) {
                                if (grandchild.child(k)) |struct_child| {
                                    if (std.mem.eql(u8, struct_child.kind(), "SuffixExpr")) {
                                        // Look for ContainerDecl in SuffixExpr children
                                        const suffix_child_count = struct_child.childCount();
                                        var l: u32 = 0;
                                        while (l < suffix_child_count) : (l += 1) {
                                            if (struct_child.child(l)) |suffix_child| {
                                                if (std.mem.eql(u8, suffix_child.kind(), "ContainerDecl")) {
                                                    return suffix_child;
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    return null;
}

/// Format the contents of a struct body (ContainerDecl children)
fn formatStructBody(container: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
    const child_count = container.childCount();
    var i: u32 = 0;
    var prev_was_field = false;
    
    while (i < child_count) : (i += 1) {
        if (container.child(i)) |child| {
            const child_type = child.kind();
            
            if (std.mem.eql(u8, child_type, "ContainerField")) {
                // Format struct field
                try formatStructField(child, source, builder);
                prev_was_field = true;
            } else if (std.mem.eql(u8, child_type, "pub")) {
                // Handle pub + following declaration
                if (i + 1 < child_count) {
                    if (container.child(i + 1)) |next_child| {
                        if (std.mem.eql(u8, next_child.kind(), "Decl")) {
                            // Add blank line before methods
                            try builder.newline();
                            
                            try formatPubMethod(child, next_child, source, builder, depth, options);
                            prev_was_field = false;
                            i += 1; // Skip the next node since we processed it
                        }
                    }
                }
            } else if (std.mem.eql(u8, child_type, "Decl")) {
                // Non-pub method
                if (prev_was_field) {
                    try builder.newline();
                }
                try formatZigNode(child, source, builder, depth, options);
                prev_was_field = false;
            }
            // Skip other tokens like '{', '}', ',', 'struct'
        }
    }
}

/// Format a struct field (ContainerField)
fn formatStructField(node: ts.Node, source: []const u8, builder: *LineBuilder) !void {
    try builder.appendIndent();
    const field_text = getNodeText(node, source);
    // Format field with proper spacing around colon
    try formatFieldWithSpacing(field_text, builder);
    try builder.append(",");
    try builder.newline();
}

/// Format field text with proper spacing around colon
fn formatFieldWithSpacing(field_text: []const u8, builder: *LineBuilder) !void {
    var i: usize = 0;
    while (i < field_text.len) : (i += 1) {
        const char = field_text[i];
        if (char == ':') {
            try builder.append(": ");
        } else {
            try builder.append(&[_]u8{char});
        }
    }
}

/// Format pub method by combining pub keyword with method declaration
fn formatPubMethod(pub_node: ts.Node, decl_node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
    _ = pub_node;
    _ = depth;
    _ = options;
    
    try builder.appendIndent();
    
    // Get the method text and format it as a public function
    const method_text = getNodeText(decl_node, source);
    const combined_text = try std.fmt.allocPrint(builder.allocator, "pub {s}", .{method_text});
    defer builder.allocator.free(combined_text);
    
    // Format the combined pub method
    try formatFunctionWithSpacing(combined_text, builder);
    try builder.newline();
}

/// Format Zig enum
fn formatZigEnum(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
    _ = depth;
    _ = options;

    try builder.appendIndent();

    // Check if it's public
    if (node.childByFieldName("pub")) |_| {
        try builder.append("pub ");
    }

    try builder.append("const ");

    // Enum name
    if (node.childByFieldName("name")) |name_node| {
        const name_text = getNodeText(name_node, source);
        try builder.append(name_text);
    }

    try builder.append(" = enum {");
    try builder.newline();

    // Enum values
    builder.indent();
    const child_count = node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        if (node.child(i)) |child| {
            const child_type = child.kind();
            if (std.mem.eql(u8, child_type, "enum_field")) {
                try builder.appendIndent();
                try appendNodeText(child, source, builder);
                try builder.append(",");
                try builder.newline();
            }
        }
    }
    builder.dedent();

    try builder.appendIndent();
    try builder.append("};");
    try builder.newline();
}

/// Format Zig union
fn formatZigUnion(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
    _ = depth;
    _ = options;

    try builder.appendIndent();

    // Check if it's public
    if (node.childByFieldName("pub")) |_| {
        try builder.append("pub ");
    }

    try builder.append("const ");

    // Union name
    if (node.childByFieldName("name")) |name_node| {
        const name_text = getNodeText(name_node, source);
        try builder.append(name_text);
    }

    try builder.append(" = union {");
    try builder.newline();

    // Union fields
    builder.indent();
    const child_count = node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        if (node.child(i)) |child| {
            const child_type = child.kind();
            if (std.mem.eql(u8, child_type, "field_declaration")) {
                try builder.appendIndent();
                try appendNodeText(child, source, builder);
                try builder.append(",");
                try builder.newline();
            }
        }
    }
    builder.dedent();

    try builder.appendIndent();
    try builder.append("};");
    try builder.newline();
}

/// Format Zig test
fn formatZigTest(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) std.mem.Allocator.Error!void {
    _ = depth;
    _ = options;
    
    const test_text = getNodeText(node, source);
    try builder.appendIndent();
    try formatTestWithSpacing(test_text, builder);
    try builder.newline();
}

/// Format Zig import statement
fn formatZigImport(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
    _ = depth;
    _ = options;

    const import_text = getNodeText(node, source);
    try builder.appendIndent();
    try formatImportWithSpacing(import_text, builder);
    try builder.newline();
}

/// Format Zig variable declaration
fn formatZigVariable(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
    _ = depth;
    _ = options;

    const var_text = getNodeText(node, source);
    try builder.appendIndent();
    try formatVariableWithSpacing(var_text, builder);
    try builder.newline();
}

/// Format import with proper spacing around = and semicolon
fn formatImportWithSpacing(import_text: []const u8, builder: *LineBuilder) !void {
    var i: usize = 0;
    while (i < import_text.len) : (i += 1) {
        const char = import_text[i];
        if (char == '=') {
            // Add space before = if not present
            if (i > 0 and import_text[i-1] != ' ') {
                try builder.append(" ");
            }
            try builder.append(&[_]u8{char});
            // Add space after = if not present
            if (i + 1 < import_text.len and import_text[i + 1] != ' ') {
                try builder.append(" ");
            }
        } else {
            try builder.append(&[_]u8{char});
        }
    }
}

/// Format variable with proper spacing
fn formatVariableWithSpacing(var_text: []const u8, builder: *LineBuilder) !void {
    var i: usize = 0;
    while (i < var_text.len) : (i += 1) {
        const char = var_text[i];
        if (char == '=') {
            // Add space before = if not present
            if (i > 0 and var_text[i-1] != ' ') {
                try builder.append(" ");
            }
            try builder.append(&[_]u8{char});
            // Add space after = if not present
            if (i + 1 < var_text.len and var_text[i + 1] != ' ') {
                try builder.append(" ");
            }
        } else if (char == ':') {
            try builder.append(&[_]u8{char});
            // Add space after : if not present
            if (i + 1 < var_text.len and var_text[i + 1] != ' ') {
                try builder.append(" ");
            }
        } else {
            try builder.append(&[_]u8{char});
        }
    }
}

/// Helper function to get node text from source
fn getNodeText(node: ts.Node, source: []const u8) []const u8 {
    const start = node.startByte();
    const end = node.endByte();
    if (end <= source.len and start <= end) {
        return source[start..end];
    }
    return "";
}

/// Helper function to append node text to builder
fn appendNodeText(node: ts.Node, source: []const u8, builder: *LineBuilder) !void {
    const text = getNodeText(node, source);
    try builder.append(text);
}

/// Check if a node represents a Zig declaration
pub fn isZigDeclaration(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "function_declaration") or
        std.mem.eql(u8, node_type, "struct_declaration") or
        std.mem.eql(u8, node_type, "enum_declaration") or
        std.mem.eql(u8, node_type, "union_declaration") or
        std.mem.eql(u8, node_type, "variable_declaration");
}

/// Check if a node represents a Zig test
pub fn isZigTest(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "test_declaration");
}
