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
    
    // Check if this starts with a function declaration pattern
    // Functions can contain struct/enum/union in their return statements
    const trimmed = std.mem.trim(u8, text, " \t\n\r");
    const starts_with_fn = std.mem.startsWith(u8, trimmed, "fn ") or
                           std.mem.startsWith(u8, trimmed, "pub fn ");
    
    // If it doesn't start with fn, then check for type definitions
    const not_type_def = if (!starts_with_fn) 
        std.mem.indexOf(u8, text, "struct") == null and
        std.mem.indexOf(u8, text, "enum") == null and
        std.mem.indexOf(u8, text, "union") == null
    else
        true; // If it starts with fn, it's a function regardless of content
    
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

fn formatEnumDeclaration(enum_text: []const u8, builder: *LineBuilder) !void {
    const trimmed = std.mem.trim(u8, enum_text, " \t\n\r");
    
    // Find "=enum" or "enum" to separate declaration from body
    if (std.mem.indexOf(u8, trimmed, "=enum")) |enum_pos| {
        const declaration = std.mem.trim(u8, trimmed[0..enum_pos], " \t");
        // Add proper spacing around keywords and identifiers
        try formatZigDeclaration(declaration, builder);
    } else if (std.mem.indexOf(u8, trimmed, "enum")) |enum_pos| {
        const declaration = std.mem.trim(u8, trimmed[0..enum_pos], " \t");
        if (declaration.len > 0) {
            try formatZigDeclaration(declaration, builder);
        }
    } else {
        // Fallback: just append the text
        try builder.append(trimmed);
    }
}

fn formatUnionDeclaration(union_text: []const u8, builder: *LineBuilder) !void {
    const trimmed = std.mem.trim(u8, union_text, " \t\n\r");
    
    // Find the union keyword - could be =union or just union
    // Need to handle union(enum) specially
    if (std.mem.indexOf(u8, trimmed, "=union(")) |union_pos| {
        // Tagged union case: const Value=union(enum){...
        const declaration = std.mem.trim(u8, trimmed[0..union_pos], " \t");
        try formatZigDeclaration(declaration, builder);
        // Add the union part with proper spacing
        try builder.append(" = union(enum)");
    } else if (std.mem.indexOf(u8, trimmed, "=union")) |union_pos| {
        // Regular union: const Value=union{...
        const declaration = std.mem.trim(u8, trimmed[0..union_pos], " \t");
        try formatZigDeclaration(declaration, builder);
        // Add the union part with proper spacing
        try builder.append(" = union");
    } else if (std.mem.indexOf(u8, trimmed, " union(")) |union_pos| {
        // Space before union(
        const declaration = std.mem.trim(u8, trimmed[0..union_pos], " \t");
        if (declaration.len > 0) {
            try formatZigDeclaration(declaration, builder);
        }
        try builder.append(" union(enum)");
    } else if (std.mem.indexOf(u8, trimmed, " union")) |union_pos| {
        // Space before union
        const declaration = std.mem.trim(u8, trimmed[0..union_pos], " \t");
        if (declaration.len > 0) {
            try formatZigDeclaration(declaration, builder);
        }
        try builder.append(" union");
    } else {
        // Fallback: just output const Name if we can extract it
        if (std.mem.indexOf(u8, trimmed, "const ")) |_| {
            // Extract the name between const and = or {
            if (std.mem.indexOf(u8, trimmed, "=")) |eq_pos| {
                const decl = std.mem.trim(u8, trimmed[0..eq_pos], " \t");
                try formatZigDeclaration(decl, builder);
            } else {
                try builder.append(trimmed);
            }
        } else {
            try builder.append(trimmed);
        }
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
    
    // Combine pub + declaration text
    const combined_text = try std.fmt.allocPrint(builder.allocator, "{s} {s}", .{ pub_text, decl_text });
    defer builder.allocator.free(combined_text);
    
    // Format based on the declaration type
    if (std.mem.eql(u8, decl_type, "Decl") and isFunctionDecl(combined_text)) {
        try builder.appendIndent();
        try formatFunctionWithSpacing(combined_text, builder, options);
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
    
    const func_text = getNodeText(node, source);
    try builder.appendIndent();
    
    // Parse and format the function with proper spacing
    try formatFunctionWithSpacing(func_text, builder, options);
    try builder.newline();
}

/// Format function with proper spacing around parentheses, return types, and braces
fn formatFunctionWithSpacing(func_text: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
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
        try formatFunctionSignature(signature, builder, options);
        
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

/// Format function signature with proper spacing and multiline support
fn formatFunctionSignature(signature: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
    // First handle the pub fn keyword spacing
    if (std.mem.indexOf(u8, signature, "pubfn")) |pos| {
        // Replace "pubfn" with "pub fn"
        try builder.append(signature[0..pos]);
        try builder.append("pub fn");
        
        // Continue with the rest after "pubfn"
        const rest = signature[pos + 5..];
        try formatSignatureWithOptions(rest, builder, options);
        return;
    }
    
    try formatSignatureWithOptions(signature, builder, options);
}

/// Format signature with line width awareness and multiline parameter support
fn formatSignatureWithOptions(signature: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
    // Find function name and parameter section
    if (std.mem.indexOf(u8, signature, "(")) |paren_start| {
        if (std.mem.lastIndexOf(u8, signature, ")")) |paren_end| {
            // Extract parts
            const func_name_part = signature[0..paren_start];
            const params_part = signature[paren_start + 1..paren_end];
            const return_part = if (paren_end + 1 < signature.len) signature[paren_end + 1..] else "";
            
            // Format function name part with proper spacing
            try formatFunctionNamePart(func_name_part, builder);
            
            // Check if we need multiline formatting
            const total_width = func_name_part.len + params_part.len + return_part.len + 2; // +2 for parentheses
            if (total_width > options.line_width and params_part.len > 0) {
                // Use multiline format
                try builder.append("(");
                try builder.newline();
                builder.indent();
                
                try formatParametersMultiline(params_part, builder, options);
                
                builder.dedent();
                try builder.appendIndent();
                try builder.append(")");
            } else {
                // Use single line format
                try builder.append("(");
                try formatParametersSingleLine(params_part, builder);
                try builder.append(")");
            }
            
            // Format return type
            if (return_part.len > 0) {
                try builder.append(" ");
                try formatReturnType(return_part, builder);
            }
            
            return;
        }
    }
    
    // Fallback - basic formatting without parameter parsing
    try formatBasicSignature(signature, builder);
}

/// Format function name part with proper spacing
fn formatFunctionNamePart(name_part: []const u8, builder: *LineBuilder) !void {
    var i: usize = 0;
    while (i < name_part.len) : (i += 1) {
        const char = name_part[i];
        if (char == ':') {
            try builder.append(&[_]u8{char});
            // Add space after : if not present
            if (i + 1 < name_part.len and name_part[i + 1] != ' ') {
                try builder.append(" ");
            }
        } else {
            try builder.append(&[_]u8{char});
        }
    }
}

/// Format parameters in multiline style
fn formatParametersMultiline(params: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
    if (params.len == 0) return;
    
    var param_start: usize = 0;
    var depth: i32 = 0;
    var in_string: bool = false;
    var string_char: u8 = 0;
    
    for (params, 0..) |char, i| {
        // Track string boundaries
        if (!in_string and (char == '\'' or char == '"')) {
            in_string = true;
            string_char = char;
        } else if (in_string and char == string_char) {
            in_string = false;
        }
        
        if (!in_string) {
            if (char == '<' or char == '(' or char == '[') {
                depth += 1;
            } else if (char == '>' or char == ')' or char == ']') {
                depth -= 1;
            } else if (char == ',' and depth == 0) {
                // Found parameter boundary
                const param = std.mem.trim(u8, params[param_start..i], " \t\n\r");
                if (param.len > 0) {
                    try builder.appendIndent();
                    try formatSingleParameter(param, builder);
                    try builder.append(",");
                    try builder.newline();
                }
                param_start = i + 1;
            }
        }
    }
    
    // Handle last parameter
    const last_param = std.mem.trim(u8, params[param_start..], " \t\n\r");
    if (last_param.len > 0) {
        try builder.appendIndent();
        try formatSingleParameter(last_param, builder);
        if (options.trailing_comma) {
            try builder.append(",");
        }
        try builder.newline();
    }
}

/// Format parameters in single line style
fn formatParametersSingleLine(params: []const u8, builder: *LineBuilder) !void {
    if (params.len == 0) return;
    
    var param_start: usize = 0;
    var depth: i32 = 0;
    var in_string: bool = false;
    var string_char: u8 = 0;
    var first_param = true;
    
    for (params, 0..) |char, i| {
        // Track string boundaries
        if (!in_string and (char == '\'' or char == '"')) {
            in_string = true;
            string_char = char;
        } else if (in_string and char == string_char) {
            in_string = false;
        }
        
        if (!in_string) {
            if (char == '<' or char == '(' or char == '[') {
                depth += 1;
            } else if (char == '>' or char == ')' or char == ']') {
                depth -= 1;
            } else if (char == ',' and depth == 0) {
                // Found parameter boundary
                const param = std.mem.trim(u8, params[param_start..i], " \t\n\r");
                if (param.len > 0) {
                    if (!first_param) try builder.append(" ");
                    try formatSingleParameter(param, builder);
                    try builder.append(",");
                    first_param = false;
                }
                param_start = i + 1;
            }
        }
    }
    
    // Handle last parameter
    const last_param = std.mem.trim(u8, params[param_start..], " \t\n\r");
    if (last_param.len > 0) {
        if (!first_param) try builder.append(" ");
        try formatSingleParameter(last_param, builder);
    }
}

/// Format a single parameter with proper type annotation spacing
fn formatSingleParameter(param: []const u8, builder: *LineBuilder) !void {
    // Look for the colon that separates param name from type
    if (std.mem.indexOf(u8, param, ":")) |colon_pos| {
        const param_name = std.mem.trim(u8, param[0..colon_pos], " \t");
        const param_type = std.mem.trim(u8, param[colon_pos + 1..], " \t");
        
        try builder.append(param_name);
        try builder.append(": ");
        try builder.append(param_type);
    } else {
        // No type annotation, just format as-is
        try builder.append(param);
    }
}

/// Format return type with proper spacing
fn formatReturnType(return_part: []const u8, builder: *LineBuilder) !void {
    const trimmed = std.mem.trim(u8, return_part, " \t");
    if (trimmed.len > 0) {
        try builder.append(trimmed);
    }
}

/// Fallback basic signature formatting
fn formatBasicSignature(signature: []const u8, builder: *LineBuilder) !void {
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

/// Format enum body from text when AST is not available
fn formatEnumBodyFromText(enum_text: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
    
    // Find the content between { and }
    const start = std.mem.indexOf(u8, enum_text, "{") orelse return;
    const end = std.mem.lastIndexOf(u8, enum_text, "}") orelse return;
    
    if (end <= start + 1) return;
    
    const body_text = enum_text[start + 1 .. end];
    
    // Check if there's a function inside (pub fn)
    if (std.mem.indexOf(u8, body_text, "pub fn") != null or std.mem.indexOf(u8, body_text, "fn ") != null) {
        // Parse enum fields and methods
        var i: usize = 0;
        var field_start: usize = 0;
        var depth: u32 = 0;
        
        while (i < body_text.len) : (i += 1) {
            const char = body_text[i];
            
            if (char == '{') {
                depth += 1;
            } else if (char == '}') {
                if (depth > 0) depth -= 1;
            } else if (char == ',' and depth == 0) {
                // Found field separator at top level
                const field = std.mem.trim(u8, body_text[field_start..i], " \t\n\r");
                if (field.len > 0) {
                    try builder.appendIndent();
                    try builder.append(field);
                    try builder.append(",");
                    try builder.newline();
                }
                field_start = i + 1;
            } else if (depth == 0) {
                // Check for function start
                if (body_text.len > i + 6 and std.mem.eql(u8, body_text[i..i + 6], "pub fn")) {
                    // Process any remaining field before the function
                    const field = std.mem.trim(u8, body_text[field_start..i], " \t\n\r,");
                    if (field.len > 0) {
                        try builder.appendIndent();
                        try builder.append(field);
                        try builder.append(",");
                        try builder.newline();
                    }
                    
                    // Add blank line before method
                    try builder.newline();
                    
                    // Find the end of the function
                    var fn_depth: u32 = 0;
                    const fn_start = i;
                    var j = i;
                    while (j < body_text.len) : (j += 1) {
                        if (body_text[j] == '{') {
                            fn_depth += 1;
                        } else if (body_text[j] == '}') {
                            if (fn_depth > 0) {
                                fn_depth -= 1;
                                if (fn_depth == 0) {
                                    // Found end of function
                                    const fn_text = body_text[fn_start..j + 1];
                                    try builder.appendIndent();
                                    try formatFunctionWithSpacing(fn_text, builder, options);
                                    try builder.newline();
                                    i = j;
                                    field_start = j + 1;
                                    break;
                                }
                            }
                        }
                    }
                }
            }
        }
        
        // Process any remaining content
        if (field_start < body_text.len) {
            const remaining = std.mem.trim(u8, body_text[field_start..], " \t\n\r,;");
            if (remaining.len > 0) {
                // Check if it's a function
                if (std.mem.indexOf(u8, remaining, "fn ") != null) {
                    try builder.newline();
                    try builder.appendIndent();
                    try formatFunctionWithSpacing(remaining, builder, options);
                    try builder.newline();
                } else {
                    // Regular field
                    try builder.appendIndent();
                    try builder.append(remaining);
                    try builder.append(",");
                    try builder.newline();
                }
            }
        }
    } else {
        // Simple enum with just fields
        var iter = std.mem.tokenizeScalar(u8, body_text, ',');
        while (iter.next()) |field| {
            const trimmed = std.mem.trim(u8, field, " \t\n\r");
            if (trimmed.len > 0) {
                try builder.appendIndent();
                try builder.append(trimmed);
                try builder.append(",");
                try builder.newline();
            }
        }
    }
}

/// Format union body from text when AST is not available
fn formatUnionBodyFromText(union_text: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
    _ = options;
    
    // Find the content between { and }
    const start = std.mem.indexOf(u8, union_text, "{") orelse return;
    const end = std.mem.lastIndexOf(u8, union_text, "}") orelse return;
    
    if (end <= start + 1) return;
    
    const body_text = union_text[start + 1 .. end];
    
    // Parse union fields
    var iter = std.mem.tokenizeScalar(u8, body_text, ',');
    while (iter.next()) |field| {
        const trimmed = std.mem.trim(u8, field, " \t\n\r");
        if (trimmed.len > 0) {
            try builder.appendIndent();
            // Add spacing around : for union fields  
            if (std.mem.indexOf(u8, trimmed, ":")) |colon_pos| {
                const field_name = std.mem.trim(u8, trimmed[0..colon_pos], " \t");
                const field_type = std.mem.trim(u8, trimmed[colon_pos + 1..], " \t");
                try builder.append(field_name);
                try builder.append(": ");
                try builder.append(field_type);
            } else {
                try builder.append(trimmed);
            }
            try builder.append(",");
            try builder.newline();
        }
    }
}

/// Format struct body from text when AST is not available
fn formatStructBodyFromText(struct_text: []const u8, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
    _ = source;
    _ = depth;
    _ = options;
    
    // Find the content between { and }
    const start = std.mem.indexOf(u8, struct_text, "{") orelse return;
    const end = std.mem.lastIndexOf(u8, struct_text, "}") orelse return;
    
    if (end <= start + 1) return;
    
    const body_text = struct_text[start + 1 .. end];
    
    // Simple field parsing for structs
    var lines = std.mem.tokenizeScalar(u8, body_text, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len > 0) {
            try builder.appendIndent();
            try formatStatementWithSpacing(trimmed, builder);
            try builder.newline();
        }
    }
}

/// Format return statement with struct literal expansion
fn formatReturnWithStruct(statement: []const u8, builder: *LineBuilder) !void {
    // Check if this is a switch expression
    if (std.mem.indexOf(u8, statement, "switch")) |_| {
        // This is a return with switch expression
        // Format the "return switch (...)" part
        if (std.mem.indexOf(u8, statement, "{")) |brace_pos| {
            var return_part = std.ArrayList(u8).init(builder.allocator);
            defer return_part.deinit();
            try return_part.appendSlice(statement[0..brace_pos]);
            
            // Apply spacing fixes to the return part
            const fixed_return = try formatSwitchExpression(return_part.items, builder.allocator);
            defer builder.allocator.free(fixed_return);
            try builder.append(fixed_return);
            try builder.append(" {");
            try builder.newline();
            
            // Format switch cases
            builder.indent();
            const body_end = std.mem.lastIndexOf(u8, statement, "}") orelse statement.len;
            const cases = statement[brace_pos + 1 .. body_end];
            
            // Split by comma to get each case
            var case_iter = std.mem.tokenizeScalar(u8, cases, ',');
            while (case_iter.next()) |case| {
                const trimmed_case = std.mem.trim(u8, case, " \t\n\r");
                if (trimmed_case.len > 0) {
                    try builder.appendIndent();
                    try formatStatementWithSpacing(trimmed_case, builder);
                    try builder.append(",");
                    try builder.newline();
                }
            }
            
            builder.dedent();
            try builder.appendIndent();
            try builder.append("}");
            return;
        }
        // Fallback
        try formatStatementWithSpacing(statement, builder);
        return;
    }
    
    // Find the struct literal part
    if (std.mem.indexOf(u8, statement, "{")) |brace_start| {
        // Extract and format struct fields
        const struct_end = std.mem.lastIndexOf(u8, statement, "}") orelse statement.len;
        const struct_content = std.mem.trim(u8, statement[brace_start + 1..struct_end], " \t\n\r");
        
        // Format "return StructName"
        const return_part = std.mem.trim(u8, statement[0..brace_start], " \t");
        try formatStatementWithSpacing(return_part, builder);
        
        if (struct_content.len > 0) {
            // Non-empty struct - use multiline format
            try builder.append("{");
            try builder.newline();
            builder.indent();
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
            
            builder.dedent();
            try builder.appendIndent();
            try builder.append("}");
        } else {
            // Empty struct - use inline format
            try builder.append("{}");
        }
    } else {
        // No struct literal, just format normally
        try formatStatementWithSpacing(statement, builder);
    }
}

/// Format switch expression header with proper spacing
fn formatSwitchExpression(expr: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();
    
    // Fix "switch(" to "switch ("
    if (std.mem.indexOf(u8, expr, "switch(")) |pos| {
        try result.appendSlice(expr[0..pos]);
        try result.appendSlice("switch (");
        try result.appendSlice(expr[pos + 7..]);
    } else {
        try result.appendSlice(expr);
    }
    
    // Fix ")  " to ") " if there are multiple spaces
    var final_result = std.ArrayList(u8).init(allocator);
    var i: usize = 0;
    var prev_was_space = false;
    while (i < result.items.len) : (i += 1) {
        const char = result.items[i];
        if (char == ' ') {
            if (!prev_was_space) {
                try final_result.append(char);
            }
            prev_was_space = true;
        } else {
            try final_result.append(char);
            prev_was_space = false;
        }
    }
    
    return final_result.toOwnedSlice();
}

/// Format statement with proper spacing around operators
fn formatStatementWithSpacing(statement: []const u8, builder: *LineBuilder) !void {
    var i: usize = 0;
    
    // Check if statement contains "switch(" and replace with "switch ("
    const fixed_statement = if (std.mem.indexOf(u8, statement, "switch(")) |pos| blk: {
        var fixed = std.ArrayList(u8).init(builder.allocator);
        defer fixed.deinit();
        try fixed.appendSlice(statement[0..pos + 6]); // up to and including "switch"
        try fixed.append(' ');
        try fixed.appendSlice(statement[pos + 6..]); // from "(" onwards
        break :blk try builder.allocator.dupe(u8, fixed.items);
    } else statement;
    defer if (fixed_statement.ptr != statement.ptr) builder.allocator.free(fixed_statement);
    
    // Check if statement contains "){"
    const spaced_statement = if (std.mem.indexOf(u8, fixed_statement, "){")) |pos| blk: {
        var spaced = std.ArrayList(u8).init(builder.allocator);
        defer spaced.deinit();
        try spaced.appendSlice(fixed_statement[0..pos + 1]); // up to and including ")"
        try spaced.append(' ');
        try spaced.appendSlice(fixed_statement[pos + 1..]); // from "{" onwards
        break :blk try builder.allocator.dupe(u8, spaced.items);
    } else fixed_statement;
    defer if (spaced_statement.ptr != fixed_statement.ptr and spaced_statement.ptr != statement.ptr) 
        builder.allocator.free(spaced_statement);
    
    while (i < spaced_statement.len) : (i += 1) {
        const char = spaced_statement[i];
        
        if (char == '=') {
            // Check for => (arrow) operator
            if (i + 1 < spaced_statement.len and spaced_statement[i + 1] == '>') {
                // This is => (arrow), add spaces around it
                if (i > 0 and spaced_statement[i-1] != ' ') {
                    try builder.append(" ");
                }
                try builder.append("=>");
                if (i + 2 < spaced_statement.len and spaced_statement[i + 2] != ' ') {
                    try builder.append(" ");
                }
                i += 1; // Skip the next >
            } else if (i + 1 < spaced_statement.len and spaced_statement[i + 1] == '=') {
                // This is == (equality), add spaces around it
                if (i > 0 and spaced_statement[i-1] != ' ') {
                    try builder.append(" ");
                }
                try builder.append("==");
                if (i + 2 < spaced_statement.len and spaced_statement[i + 2] != ' ') {
                    try builder.append(" ");
                }
                i += 1; // Skip the next =
            } else {
                // Single = (assignment), add spaces
                if (i > 0 and spaced_statement[i-1] != ' ') {
                    try builder.append(" ");
                }
                try builder.append(&[_]u8{char});
                if (i + 1 < spaced_statement.len and spaced_statement[i + 1] != ' ') {
                    try builder.append(" ");
                }
            }
        } else if (char == '+' or char == '-' or char == '*') {
            // Add spaces around arithmetic operators
            if (i > 0 and spaced_statement[i-1] != ' ') {
                try builder.append(" ");
            }
            try builder.append(&[_]u8{char});
            if (i + 1 < spaced_statement.len and spaced_statement[i + 1] != ' ') {
                try builder.append(" ");
            }
        } else if (char == '@') {
            // @ functions like @import - don't add space before if it's = @
            if (i > 0 and spaced_statement[i-1] == '=') {
                // This is after =, the space is already added by = handling
                try builder.append(&[_]u8{char});
            } else if (i > 0 and spaced_statement[i-1] != ' ') {
                try builder.append(" ");
                try builder.append(&[_]u8{char});
            } else {
                try builder.append(&[_]u8{char});
            }
        } else if (char == ',') {
            // Add space after comma if not present
            try builder.append(&[_]u8{char});
            if (i + 1 < spaced_statement.len and spaced_statement[i + 1] != ' ') {
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
                builder.indent();
                try builder.appendIndent();
                try formatFunctionBody(body_content, builder);
                try builder.newline();
                builder.dedent();
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

    // Parse and format the complete struct/enum/union declaration
    const struct_text = getNodeText(node, source);
    
    // Determine the type (struct, enum, or union)
    // Check union first since union(enum) would match both
    const is_union = std.mem.indexOf(u8, struct_text, "union") != null;
    const is_enum = !is_union and std.mem.indexOf(u8, struct_text, "enum") != null;
    
    if (is_union) {
        try formatUnionDeclaration(struct_text, builder);
        // formatUnionDeclaration now handles the complete declaration including " = union(enum)"
        try builder.append(" {");
    } else if (is_enum) {
        try formatEnumDeclaration(struct_text, builder);
        try builder.append(" = enum {");
    } else {
        try formatStructDeclaration(struct_text, builder);
        try builder.append(" = struct {");
    }

    try builder.newline();

    // Navigate to the actual struct body (ContainerDecl)
    const container_decl = findContainerDecl(node);
    if (container_decl) |container| {
        // Format struct body
        builder.indent();
        if (is_enum) {
            try formatEnumBody(container, source, builder, depth + 1, options);
        } else if (is_union) {
            try formatUnionBody(container, source, builder, depth + 1, options);
        } else {
            try formatStructBody(container, source, builder, depth + 1, options);
        }
        builder.dedent();
    } else {
        // Fallback: Try to parse the text directly when AST structure is not available
        builder.indent();
        if (is_enum) {
            try formatEnumBodyFromText(struct_text, builder, options);
        } else if (is_union) {
            try formatUnionBodyFromText(struct_text, builder, options);
        } else {
            try formatStructBodyFromText(struct_text, source, builder, depth + 1, options);
        }
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
fn formatEnumBody(container: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
    const child_count = container.childCount();
    var i: u32 = 0;
    var prev_was_field = false;
    
    while (i < child_count) : (i += 1) {
        if (container.child(i)) |child| {
            const child_type = child.kind();
            const child_text = getNodeText(child, source);
            
            if (std.mem.eql(u8, child_type, "ContainerField") or std.mem.eql(u8, child_type, "IDENTIFIER")) {
                // Format enum field
                const trimmed = std.mem.trim(u8, child_text, " \t\n\r,");
                if (trimmed.len > 0) {
                    try builder.appendIndent();
                    try builder.append(trimmed);
                    try builder.append(",");
                    try builder.newline();
                    prev_was_field = true;
                }
            } else if (std.mem.eql(u8, child_type, "pub")) {
                // Handle pub + following declaration (method in enum)
                if (i + 1 < child_count) {
                    if (container.child(i + 1)) |next_child| {
                        if (std.mem.eql(u8, next_child.kind(), "Decl")) {
                            // Add blank line before methods
                            if (prev_was_field) {
                                try builder.newline();
                            }
                            
                            try formatPubMethod(child, next_child, source, builder, depth, options);
                            prev_was_field = false;
                            i += 1; // Skip the next node since we processed it
                        }
                    }
                }
            } else if (std.mem.eql(u8, child_type, "Decl") or std.mem.eql(u8, child_type, "FnProto")) {
                // Non-pub method or function in enum
                if (prev_was_field) {
                    try builder.newline();
                }
                const node_text = getNodeText(child, source);
                // Format methods inside enums  
                if (std.mem.indexOf(u8, node_text, "fn ")) |_| {
                    try builder.appendIndent();
                    try formatFunctionWithSpacing(node_text, builder, options);
                    try builder.newline();
                } else {
                    try formatZigNode(child, source, builder, depth, options);
                }
                prev_was_field = false;
            }
            // Skip other tokens like '{', '}', ',', 'enum'
        }
    }
}

fn formatUnionBody(container: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
    const child_count = container.childCount();
    var i: u32 = 0;
    
    while (i < child_count) : (i += 1) {
        if (container.child(i)) |child| {
            const child_type = child.kind();
            
            if (std.mem.eql(u8, child_type, "ContainerField")) {
                // Format union field
                try formatUnionField(child, source, builder);
            }
            // Skip other tokens
        }
    }
    _ = depth;
    _ = options;
}

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

fn formatUnionField(node: ts.Node, source: []const u8, builder: *LineBuilder) !void {
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
    
    try builder.appendIndent();
    
    // Get the method text and format it as a public function
    const method_text = getNodeText(decl_node, source);
    const combined_text = try std.fmt.allocPrint(builder.allocator, "pub {s}", .{method_text});
    defer builder.allocator.free(combined_text);
    
    // Format the combined pub method
    try formatFunctionWithSpacing(combined_text, builder, options);
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
