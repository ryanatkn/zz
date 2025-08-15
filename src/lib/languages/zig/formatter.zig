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
    try formatZigNode(node, source, builder, 0, options);
}

/// Zig node formatting with controlled recursion
fn formatZigNode(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) std.mem.Allocator.Error!void {
    const node_type = node.kind();
    const node_text = getNodeText(node, source);


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

/// Format function body with proper spacing
fn formatFunctionBody(body: []const u8, builder: *LineBuilder) !void {
    // Simple body formatting - add spaces around key operators
    var i: usize = 0;
    while (i < body.len) : (i += 1) {
        const char = body[i];
        if (char == ',' and i + 1 < body.len and body[i + 1] != ' ') {
            try builder.append(&[_]u8{char});
            try builder.append(" ");
        } else if (char == '(' or char == ')') {
            try builder.append(&[_]u8{char});
        } else {
            try builder.append(&[_]u8{char});
        }
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

    // Check if it's public
    if (node.childByFieldName("pub")) |_| {
        try builder.append("pub ");
    }

    try builder.append("const ");

    // Struct name
    if (node.childByFieldName("name")) |name_node| {
        const name_text = getNodeText(name_node, source);
        try builder.append(name_text);
    }

    try builder.append(" = struct {");
    try builder.newline();

    // Struct body
    builder.indent();
    const child_count = node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        if (node.child(i)) |child| {
            const child_type = child.kind();
            if (std.mem.eql(u8, child_type, "field_declaration") or
                std.mem.eql(u8, child_type, "function_declaration"))
            {
                try formatZigNode(child, source, builder, depth + 1, options);
            }
        }
    }
    builder.dedent();

    try builder.appendIndent();
    try builder.append("};");
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
    try builder.appendIndent();
    try builder.append("test ");

    // Test name
    if (node.childByFieldName("name")) |name_node| {
        const name_text = getNodeText(name_node, source);
        try builder.append(name_text);
    }

    try builder.append(" {");
    try builder.newline();

    // Test body
    if (node.childByFieldName("body")) |body_node| {
        builder.indent();
        try formatZigNode(body_node, source, builder, depth + 1, options);
        builder.dedent();
    }

    try builder.appendIndent();
    try builder.append("}");
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
