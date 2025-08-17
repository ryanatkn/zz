const std = @import("std");
const ts = @import("tree-sitter");
const LineBuilder = @import("../../parsing/formatter.zig").LineBuilder;
const FormatterOptions = @import("../../parsing/formatter.zig").FormatterOptions;
const ZigUtils = @import("zig_utils.zig").ZigUtils;
const FormatDeclaration = @import("format_declaration.zig").FormatDeclaration;

/// Zig-specific body formatting for structs, enums, and unions
pub const FormatBody = struct {

    /// Format struct body from text (compatibility function)
    pub fn formatStructBodyFromText(struct_text: []const u8, builder: *LineBuilder) !void {
        // Extract the struct declaration components
        // Pattern: const Name = struct { ... }
        
        // Find "struct" keyword
        const struct_keyword_pos = std.mem.indexOf(u8, struct_text, "struct") orelse {
            // Fallback: just append the text
            try builder.append(struct_text);
            return;
        };
        
        // Find opening brace after "struct"
        const brace_start = std.mem.indexOfPos(u8, struct_text, struct_keyword_pos, "{") orelse {
            // Fallback: just append the text
            try builder.append(struct_text);
            return;
        };
        
        // Find matching closing brace
        var brace_depth: u32 = 1;
        var brace_end = brace_start + 1;
        while (brace_end < struct_text.len and brace_depth > 0) {
            if (struct_text[brace_end] == '{') {
                brace_depth += 1;
            } else if (struct_text[brace_end] == '}') {
                brace_depth -= 1;
            }
            brace_end += 1;
        }
        
        if (brace_depth != 0) {
            // Unmatched braces, fallback
            try builder.append(struct_text);
            return;
        }
        
        // Extract components
        const declaration_part = std.mem.trim(u8, struct_text[0..struct_keyword_pos], " \t");
        const body_content = std.mem.trim(u8, struct_text[brace_start + 1..brace_end - 1], " \t\n\r");
        
        // Format the declaration
        try builder.append(declaration_part);
        try builder.append("struct {");
        try builder.newline();
        builder.indent();
        
        // Format the body content
        if (body_content.len > 0) {
            try formatStructBody(std.heap.page_allocator, builder, body_content);
        }
        
        builder.dedent();
        try builder.appendIndent();
        try builder.append("}");
        
        // Add semicolon if present in original
        if (brace_end < struct_text.len) {
            const after_brace = std.mem.trim(u8, struct_text[brace_end..], " \t");
            if (std.mem.startsWith(u8, after_brace, ";")) {
                try builder.append(";");
            }
        }
    }

    /// Format enum body from text (compatibility function)
    pub fn formatEnumBodyFromText(enum_text: []const u8, builder: *LineBuilder) !void {
        // Simple delegation to formatEnumBody
        try formatEnumBody(std.heap.page_allocator, builder, enum_text);
    }

    /// Format union body from text (compatibility function)
    pub fn formatUnionBodyFromText(union_text: []const u8, builder: *LineBuilder) !void {
        // Simple delegation to formatUnionBody
        try formatUnionBody(std.heap.page_allocator, builder, union_text);
    }

    /// Format struct body with fields and methods
    pub fn formatStructBody(allocator: std.mem.Allocator, builder: *LineBuilder, content: []const u8) !void {
        const members = try parseStructMembers(allocator, content);
        defer {
            for (members) |member| {
                allocator.free(member);
            }
            allocator.free(members);
        }

        for (members, 0..) |member, i| {
            try builder.appendIndent();
            
            if (isFunctionDeclaration(member)) {
                try formatStructMethod(allocator, builder, member);
                // Add blank line after methods
                if (i < members.len - 1) {
                    try builder.newline();
                    try builder.newline();
                }
            } else {
                try formatFieldDeclaration(member, builder);
                try builder.append(",");
                try builder.newline();
            }
        }
    }

    /// Format enum body with proper value alignment
    pub fn formatEnumBody(allocator: std.mem.Allocator, builder: *LineBuilder, content: []const u8) !void {
        const values = try ZigUtils.splitByDelimiter(allocator, content, ',');
        defer allocator.free(values);

        for (values, 0..) |value, i| {
            const trimmed = std.mem.trim(u8, value, " \t\n\r");
            if (trimmed.len > 0) {
                try builder.appendIndent();
                try formatEnumValue(trimmed, builder);
                if (i < values.len - 1) {
                    try builder.append(",");
                }
                try builder.newline();
            }
        }
    }

    /// Format union body similar to enum
    pub fn formatUnionBody(allocator: std.mem.Allocator, builder: *LineBuilder, content: []const u8) !void {
        const values = try ZigUtils.splitByDelimiter(allocator, content, ',');
        defer allocator.free(values);

        for (values, 0..) |value, i| {
            const trimmed = std.mem.trim(u8, value, " \t\n\r");
            if (trimmed.len > 0) {
                try builder.appendIndent();
                try formatUnionValue(trimmed, builder);
                if (i < values.len - 1) {
                    try builder.append(",");
                }
                try builder.newline();
            }
        }
    }

    /// Format struct literal content with proper spacing
    pub fn formatStructLiteralContent(allocator: std.mem.Allocator, builder: *LineBuilder, content: []const u8) !void {
        const fields = try ZigUtils.splitByDelimiter(allocator, content, ',');
        defer allocator.free(fields);

        for (fields) |field| {
            const trimmed_field = std.mem.trim(u8, field, " \t\n\r");
            if (trimmed_field.len > 0) {
                try builder.appendIndent();
                
                // Format the field with proper spacing around =
                try formatStructLiteralField(builder, trimmed_field);
                
                // Always add trailing comma for struct literals (Zig style)
                try builder.append(",");
                try builder.newline();
            }
        }
    }

    /// Parse struct content into individual members (fields and methods)
    fn parseStructMembers(allocator: std.mem.Allocator, content: []const u8) ![][]const u8 {
        var members = std.ArrayList([]const u8).init(allocator);
        defer members.deinit();

        // Simple approach: look for commas at top level and "pub fn" patterns
        var pos: usize = 0;
        
        // First, extract simple fields (before any functions)
        // Look for pattern: name:type,name:type
        while (pos < content.len) {
            // Skip whitespace
            while (pos < content.len and (content[pos] == ' ' or content[pos] == '\t' or content[pos] == '\n')) {
                pos += 1;
            }
            
            if (pos >= content.len) break;
            
            // Check if we hit a function
            if (std.mem.startsWith(u8, content[pos..], "pub fn") or
                (pos > 0 and content[pos-1] == ',' and std.mem.startsWith(u8, content[pos..], "pub fn"))) {
                break; // Stop field parsing, functions start here
            }
            
            // Look for field pattern: identifier:type
            const field_start = pos;
            var colon_pos: ?usize = null;
            
            // Find the colon
            while (pos < content.len and content[pos] != ',' and !std.mem.startsWith(u8, content[pos..], "pub fn")) {
                if (content[pos] == ':' and colon_pos == null) {
                    colon_pos = pos;
                }
                pos += 1;
            }
            
            if (colon_pos) |_| {
                // We found a field
                const field_end = pos;
                if (pos < content.len and content[pos] == ',') {
                    pos += 1; // Skip comma
                }
                
                const field = std.mem.trim(u8, content[field_start..field_end], " \t\n\r,");
                if (field.len > 0) {
                    try members.append(try allocator.dupe(u8, field));
                }
            } else {
                // Not a field, move on
                if (pos < content.len and content[pos] == ',') {
                    pos += 1;
                }
            }
        }
        
        // Now extract functions
        while (pos < content.len) {
            // Skip whitespace
            while (pos < content.len and (content[pos] == ' ' or content[pos] == '\t' or content[pos] == '\n')) {
                pos += 1;
            }
            
            if (pos >= content.len) break;
            
            // Look for function start
            if (std.mem.startsWith(u8, content[pos..], "pub fn") or std.mem.startsWith(u8, content[pos..], "fn")) {
                // Find the end of the function (matching closing brace)
                if (std.mem.indexOfPos(u8, content, pos, "{")) |fn_brace_start| {
                    var brace_depth: u32 = 1;
                    var fn_end = fn_brace_start + 1;
                    while (fn_end < content.len and brace_depth > 0) {
                        if (content[fn_end] == '{') {
                            brace_depth += 1;
                        } else if (content[fn_end] == '}') {
                            brace_depth -= 1;
                        }
                        fn_end += 1;
                    }
                    
                    if (brace_depth == 0) {
                        const function = content[pos..fn_end];
                        try members.append(try allocator.dupe(u8, function));
                        pos = fn_end;
                    } else {
                        // Unmatched braces, skip
                        pos += 1;
                    }
                } else {
                    // No opening brace found, skip
                    pos += 1;
                }
            } else {
                pos += 1;
            }
        }

        return members.toOwnedSlice();
    }

    /// Format struct method with proper spacing
    fn formatStructMethod(allocator: std.mem.Allocator, builder: *LineBuilder, method: []const u8) !void {
        // Find the method signature and body
        if (std.mem.indexOf(u8, method, "{")) |brace_pos| {
            const signature = std.mem.trim(u8, method[0..brace_pos], " \t");
            const body_end = std.mem.lastIndexOf(u8, method, "}") orelse method.len;
            const body = std.mem.trim(u8, method[brace_pos + 1..body_end], " \t\n\r");
            
            // Format the signature with proper spacing
            try formatFunctionSignatureWithSpacing(allocator, builder, signature);
            try builder.append(" {");
            
            if (body.len > 0) {
                try builder.newline();
                builder.indent();
                
                // Parse body statements
                var statements = std.ArrayList([]const u8).init(allocator);
                defer statements.deinit();
                
                // Split body by semicolons or other statement boundaries
                var stmt_start: usize = 0;
                var in_string = false;
                for (body, 0..) |c, i| {
                    if (c == '"' and (i == 0 or body[i-1] != '\\')) {
                        in_string = !in_string;
                    }
                    
                    if (!in_string and c == ';') {
                        const stmt = std.mem.trim(u8, body[stmt_start..i], " \t\n\r");
                        if (stmt.len > 0) {
                            try statements.append(stmt);
                        }
                        stmt_start = i + 1;
                    }
                }
                
                // Add last statement if no trailing semicolon
                if (stmt_start < body.len) {
                    const stmt = std.mem.trim(u8, body[stmt_start..], " \t\n\r");
                    if (stmt.len > 0) {
                        try statements.append(stmt);
                    }
                }
                
                // Format each statement
                for (statements.items) |stmt| {
                    try builder.appendIndent();
                    try formatStatementWithSpacing(stmt, builder);
                    try builder.append(";");
                    try builder.newline();
                }
                
                builder.dedent();
                try builder.appendIndent();
            }
            
            try builder.append("}");
        } else {
            // No body, just format the signature
            try formatFunctionSignatureWithSpacing(allocator, builder, method);
        }
    }

    /// Format field declaration with proper spacing
    fn formatFieldDeclaration(field: []const u8, builder: *LineBuilder) !void {
        // Look for colon to separate field name from type
        if (std.mem.indexOf(u8, field, ":")) |colon_pos| {
            const field_name = std.mem.trim(u8, field[0..colon_pos], " \t");
            const field_type = std.mem.trim(u8, field[colon_pos + 1..], " \t");
            
            try builder.append(field_name);
            try builder.append(": ");
            try builder.append(field_type);
        } else {
            // No type annotation or different format
            try builder.append(std.mem.trim(u8, field, " \t"));
        }
    }

    /// Format enum value with optional explicit value
    fn formatEnumValue(value: []const u8, builder: *LineBuilder) !void {
        // Check for explicit value assignment
        if (std.mem.indexOf(u8, value, "=")) |equals_pos| {
            const enum_name = std.mem.trim(u8, value[0..equals_pos], " \t");
            const enum_value = std.mem.trim(u8, value[equals_pos + 1..], " \t");
            
            try builder.append(enum_name);
            try builder.append(" = ");
            try builder.append(enum_value);
        } else {
            // Simple enum value
            try builder.append(std.mem.trim(u8, value, " \t"));
        }
    }

    /// Format union value (similar to enum but may have type)
    fn formatUnionValue(value: []const u8, builder: *LineBuilder) !void {
        // Union values can have type annotations like enums
        if (std.mem.indexOf(u8, value, ":")) |colon_pos| {
            const union_name = std.mem.trim(u8, value[0..colon_pos], " \t");
            const union_type = std.mem.trim(u8, value[colon_pos + 1..], " \t");
            
            try builder.append(union_name);
            try builder.append(": ");
            try builder.append(union_type);
        } else {
            // Simple union value
            try builder.append(std.mem.trim(u8, value, " \t"));
        }
    }

    /// Format a single struct literal field (e.g., ".x = value")
    fn formatStructLiteralField(builder: *LineBuilder, field: []const u8) !void {
        // Look for the = sign and add proper spacing
        if (std.mem.indexOf(u8, field, "=")) |equals_pos| {
            const field_name = std.mem.trim(u8, field[0..equals_pos], " \t");
            const field_value = std.mem.trim(u8, field[equals_pos + 1..], " \t");
            
            try builder.append(field_name);
            try builder.append(" = ");
            try builder.append(field_value);
        } else {
            // No equals sign, just append as-is
            try builder.append(field);
        }
    }

    /// Check if member is a function declaration
    fn isFunctionDeclaration(text: []const u8) bool {
        return FormatDeclaration.isFunctionDecl(text);
    }

    // Forward declarations to avoid circular dependencies
    fn formatFunctionSignature(allocator: std.mem.Allocator, builder: *LineBuilder, signature: []const u8) !void {
        _ = allocator;
        // Simple signature formatting - delegate to more specialized function if needed
        try builder.append(std.mem.trim(u8, signature, " \t"));
    }
    
    fn formatFunctionSignatureWithSpacing(allocator: std.mem.Allocator, builder: *LineBuilder, signature: []const u8) !void {
        _ = allocator;
        // Format function signature with proper spacing
        var i: usize = 0;
        while (i < signature.len) {
            const c = signature[i];
            
            // Add spacing around colons
            if (c == ':') {
                try builder.append(": ");
                i += 1;
                // Skip any spaces after colon in original
                while (i < signature.len and signature[i] == ' ') {
                    i += 1;
                }
                continue;
            }
            
            // Add spacing around parentheses
            if (c == '(') {
                try builder.append("(");
                i += 1;
                continue;
            }
            
            if (c == ')') {
                try builder.append(")");
                i += 1;
                // Check if there's a return type after
                while (i < signature.len and signature[i] == ' ') {
                    i += 1;
                }
                continue;
            }
            
            // Add spacing around equals
            if (c == '=') {
                try builder.append(" = ");
                i += 1;
                // Skip any spaces after equals in original
                while (i < signature.len and signature[i] == ' ') {
                    i += 1;
                }
                continue;
            }
            
            try builder.append(&[_]u8{c});
            i += 1;
        }
    }
    
    fn formatStatementWithSpacing(statement: []const u8, builder: *LineBuilder) !void {
        // Format statement with proper spacing
        var i: usize = 0;
        while (i < statement.len) {
            const c = statement[i];
            
            // Add spacing around operators
            if (c == '=' and i > 0 and statement[i-1] != '=' and i + 1 < statement.len and statement[i+1] != '=') {
                try builder.append(" = ");
                i += 1;
                // Skip any spaces after equals in original
                while (i < statement.len and statement[i] == ' ') {
                    i += 1;
                }
                continue;
            }
            
            if (c == '-' or c == '+' or c == '*' or c == '/') {
                // Check if it's an operator (not part of number or @sqrt)
                if (i > 0 and statement[i-1] != '@' and statement[i-1] != '.' and 
                    i + 1 < statement.len and statement[i+1] != '.' and statement[i+1] != '=') {
                    try builder.append(" ");
                    try builder.append(&[_]u8{c});
                    try builder.append(" ");
                    i += 1;
                    // Skip any spaces after operator in original
                    while (i < statement.len and statement[i] == ' ') {
                        i += 1;
                    }
                    continue;
                }
            }
            
            // Handle builtin functions like @sqrt
            if (c == '@') {
                // Copy the entire builtin function call
                var end = i + 1;
                while (end < statement.len and (std.ascii.isAlphabetic(statement[end]) or statement[end] == '(')) {
                    end += 1;
                }
                try builder.append(statement[i..end]);
                i = end;
                continue;
            }
            
            try builder.append(&[_]u8{c});
            i += 1;
        }
    }

    fn formatDeclarationWithSpacing(declaration: []const u8, builder: *LineBuilder) !void {
        try FormatDeclaration.formatDeclaration(declaration, builder);
    }
};