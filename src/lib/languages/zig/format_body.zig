const std = @import("std");
const ts = @import("tree-sitter");
const LineBuilder = @import("../../parsing/formatter.zig").LineBuilder;
const FormatterOptions = @import("../../parsing/formatter.zig").FormatterOptions;
const ZigUtils = @import("zig_utils.zig").ZigUtils;
const FormatDeclaration = @import("format_declaration.zig").FormatDeclaration;
const builders = @import("../../text/builders.zig");
const collections = @import("../../core/collections.zig");
const ZigFormattingHelpers = @import("formatting_helpers.zig").ZigFormattingHelpers;

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
        
        // Format the declaration with proper spacing - handle "const Point=" case
        if (declaration_part.len > 0) {
            if (std.mem.endsWith(u8, declaration_part, "=")) {
                // Remove the = and add it back with proper spacing
                const name_part = std.mem.trimRight(u8, declaration_part[0..declaration_part.len-1], " \t");
                try builder.append(name_part);
                try builder.append(" = ");
            } else {
                try builder.append(declaration_part);
                try builder.append(" = ");
            }
        }
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
        
        // Only add semicolon if input had one after the struct body
        if (brace_end < struct_text.len) {
            const after_brace = std.mem.trim(u8, struct_text[brace_end..], " \t\n\r");
            if (std.mem.startsWith(u8, after_brace, ";")) {
                try builder.append(";");
            }
        }
    }

    /// Format enum body from text (compatibility function)
    pub fn formatEnumBodyFromText(enum_text: []const u8, builder: *LineBuilder) !void {
        // Parse the entire enum declaration and format it properly
        
        // Find "enum" keyword
        const enum_keyword_pos = std.mem.indexOf(u8, enum_text, "enum") orelse {
            // Fallback: just append the text
            try builder.append(enum_text);
            return;
        };
        
        // Find opening brace after "enum"
        const brace_start = std.mem.indexOfPos(u8, enum_text, enum_keyword_pos, "{") orelse {
            // Fallback: just append the text
            try builder.append(enum_text);
            return;
        };
        
        // Find matching closing brace
        var brace_depth: u32 = 1;
        var brace_end = brace_start + 1;
        while (brace_end < enum_text.len and brace_depth > 0) {
            if (enum_text[brace_end] == '{') {
                brace_depth += 1;
            } else if (enum_text[brace_end] == '}') {
                brace_depth -= 1;
            }
            brace_end += 1;
        }
        
        if (brace_depth != 0) {
            // Unmatched braces, fallback
            try builder.append(enum_text);
            return;
        }
        
        // Extract components
        const declaration_part = std.mem.trim(u8, enum_text[0..enum_keyword_pos], " \t");
        const body_content = std.mem.trim(u8, enum_text[brace_start + 1..brace_end - 1], " \t\n\r");
        
        // Format the declaration with proper spacing
        if (declaration_part.len > 0) {
            if (std.mem.endsWith(u8, declaration_part, "=")) {
                // Remove the = and add it back with proper spacing
                const name_part = std.mem.trimRight(u8, declaration_part[0..declaration_part.len-1], " \t");
                try builder.append(name_part);
                try builder.append(" = ");
            } else {
                try builder.append(declaration_part);
                try builder.append(" = ");
            }
        }
        try builder.append("enum {");
        try builder.newline();
        builder.indent();
        
        // Format the body content with enum-specific logic
        if (body_content.len > 0) {
            try formatEnumBodyContent(std.heap.page_allocator, builder, body_content);
        }
        
        builder.dedent();
        try builder.appendIndent();
        try builder.append("}");
        
        // Only add semicolon if input had one after the enum body
        if (brace_end < enum_text.len) {
            const after_brace = std.mem.trim(u8, enum_text[brace_end..], " \t\n\r");
            if (std.mem.startsWith(u8, after_brace, ";")) {
                try builder.append(";");
            }
        }
    }

    /// Format union body from text (compatibility function)
    pub fn formatUnionBodyFromText(union_text: []const u8, builder: *LineBuilder) !void {
        // Parse the entire union declaration and format it properly
        
        // Find "union" keyword
        const union_keyword_pos = std.mem.indexOf(u8, union_text, "union") orelse {
            // Fallback: just append the text
            try builder.append(union_text);
            return;
        };
        
        // Find opening brace after "union"
        const brace_start = std.mem.indexOfPos(u8, union_text, union_keyword_pos, "{") orelse {
            // Fallback: just append the text
            try builder.append(union_text);
            return;
        };
        
        // Find matching closing brace
        var brace_depth: u32 = 1;
        var brace_end = brace_start + 1;
        while (brace_end < union_text.len and brace_depth > 0) {
            if (union_text[brace_end] == '{') {
                brace_depth += 1;
            } else if (union_text[brace_end] == '}') {
                brace_depth -= 1;
            }
            brace_end += 1;
        }
        
        if (brace_depth != 0) {
            // Unmatched braces, fallback
            try builder.append(union_text);
            return;
        }
        
        // Extract components
        const declaration_part = std.mem.trim(u8, union_text[0..union_keyword_pos], " \t");
        const union_type_part = std.mem.trim(u8, union_text[union_keyword_pos..brace_start], " \t");
        const body_content = std.mem.trim(u8, union_text[brace_start + 1..brace_end - 1], " \t\n\r");
        
        // Format the declaration with proper spacing
        if (declaration_part.len > 0) {
            if (std.mem.endsWith(u8, declaration_part, "=")) {
                // Remove the = and add it back with proper spacing
                const name_part = std.mem.trimRight(u8, declaration_part[0..declaration_part.len-1], " \t");
                try builder.append(name_part);
                try builder.append(" = ");
            } else {
                try builder.append(declaration_part);
                try builder.append(" = ");
            }
        }
        // Format union type part with proper spacing (e.g., "union(enum)")
        try formatUnionTypeDeclaration(union_type_part, builder);
        try builder.append(" {");
        try builder.newline();
        builder.indent();
        
        // Format the body content
        if (body_content.len > 0) {
            try formatUnionBodyContent(std.heap.page_allocator, builder, body_content);
        }
        
        builder.dedent();
        try builder.appendIndent();
        try builder.append("}");
        
        // Only add semicolon if input had one after the union body
        if (brace_end < union_text.len) {
            const after_brace = std.mem.trim(u8, union_text[brace_end..], " \t\n\r");
            if (std.mem.startsWith(u8, after_brace, ";")) {
                try builder.append(";");
            }
        }
    }

    /// Format struct body with fields and methods
    pub fn formatStructBody(allocator: std.mem.Allocator, builder: *LineBuilder, content: []const u8) !void {
        // Use consolidated helper for member parsing
        const members = try ZigFormattingHelpers.parseContainerMembers(allocator, content);
        defer {
            for (members) |member| {
                allocator.free(member);
            }
            allocator.free(members);
        }

        var first_function = true;
        for (members, 0..) |member, i| {
            if (ZigFormattingHelpers.isFunctionDeclaration(member)) {
                // Add blank line before first function
                if (first_function) {
                    try builder.newline();
                    first_function = false;
                }
                
                try builder.appendIndent();
                try formatStructMethod(allocator, builder, member);
                try builder.newline();
                // Add blank line after methods (except last)
                if (i < members.len - 1) {
                    try builder.newline();
                }
            } else {
                try builder.appendIndent();
                try formatFieldDeclaration(member, builder);
                try builder.append(",");
                try builder.newline();
            }
        }
    }

    /// Format enum body content (AST-based - for when we have parsed enum body)
    pub fn formatEnumBody(allocator: std.mem.Allocator, builder: *LineBuilder, content: []const u8) !void {
        try formatEnumBodyContent(allocator, builder, content);
    }

    /// Format enum body content (shared between AST and text-based)
    fn formatEnumBodyContent(allocator: std.mem.Allocator, builder: *LineBuilder, content: []const u8) !void {
        // Use the new helper to parse members (both values and methods)
        const ZigHelpers = @import("formatting_helpers.zig").ZigFormattingHelpers;
        const members = try ZigHelpers.parseContainerMembers(allocator, content);
        defer {
            for (members) |member| {
                allocator.free(member);
            }
            allocator.free(members);
        }

        var first_function = true;
        for (members, 0..) |member, i| {
            if (ZigHelpers.isFunctionDeclaration(member)) {
                // Add blank line before first function
                if (first_function) {
                    try builder.newline();
                    first_function = false;
                }
                
                try builder.appendIndent();
                try formatEnumMethod(allocator, builder, member);
                try builder.newline();
                // Add blank line after methods (except last)
                if (i < members.len - 1) {
                    try builder.newline();
                }
            } else {
                // Enum value
                try builder.appendIndent();
                try formatEnumValue(member, builder);
                try builder.append(",");
                try builder.newline();
            }
        }
    }

    /// Format union body (AST-based - for when we have parsed union body)
    pub fn formatUnionBody(allocator: std.mem.Allocator, builder: *LineBuilder, content: []const u8) !void {
        try formatUnionBodyContent(allocator, builder, content);
    }
    
    /// Format union body content (shared between AST and text-based)
    fn formatUnionBodyContent(allocator: std.mem.Allocator, builder: *LineBuilder, content: []const u8) !void {
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
                var statements = collections.List([]const u8).init(allocator);
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
        // Use consolidated helper for field formatting
        try ZigFormattingHelpers.formatFieldWithColon(field, builder);
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

    /// Format enum method (similar to struct method)
    fn formatEnumMethod(allocator: std.mem.Allocator, builder: *LineBuilder, method: []const u8) !void {
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
                
                // Format body statements
                try formatFunctionBodyStatements(allocator, builder, body);
                
                builder.dedent();
                try builder.appendIndent();
            }
            
            try builder.append("}");
        } else {
            // No body, just format the signature
            try formatFunctionSignatureWithSpacing(allocator, builder, method);
        }
    }

    /// Format union method (similar to enum method)
    fn formatUnionMethod(allocator: std.mem.Allocator, builder: *LineBuilder, method: []const u8) !void {
        try formatEnumMethod(allocator, builder, method);
    }

    /// Format function body statements
    fn formatFunctionBodyStatements(allocator: std.mem.Allocator, builder: *LineBuilder, body: []const u8) !void {
        // Split body by semicolons to get statements
        var statements = collections.List([]const u8).init(allocator);
        defer statements.deinit();
        
        var stmt_start: usize = 0;
        var in_string = false;
        var brace_depth: u32 = 0;
        
        for (body, 0..) |c, i| {
            if (c == '"' and (i == 0 or body[i-1] != '\\')) {
                in_string = !in_string;
            }
            
            if (!in_string) {
                if (c == '{') {
                    brace_depth += 1;
                } else if (c == '}') {
                    brace_depth -= 1;
                } else if (c == ';' and brace_depth == 0) {
                    const stmt = std.mem.trim(u8, body[stmt_start..i], " \t\n\r");
                    if (stmt.len > 0) {
                        try statements.append(stmt);
                    }
                    stmt_start = i + 1;
                }
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
    }

    /// Check if member is a function declaration
    fn isFunctionDeclaration(text: []const u8) bool {
        return ZigFormattingHelpers.isFunctionDeclaration(text);
    }

    // Forward declarations to avoid circular dependencies
    fn formatFunctionSignature(allocator: std.mem.Allocator, builder: *LineBuilder, signature: []const u8) !void {
        _ = allocator;
        // Use consolidated helper for signature formatting
        const trimmed = std.mem.trim(u8, signature, " \t");
        try ZigFormattingHelpers.formatWithZigSpacing(trimmed, builder);
    }
    
    fn formatFunctionSignatureWithSpacing(allocator: std.mem.Allocator, builder: *LineBuilder, signature: []const u8) !void {
        _ = allocator;
        // Use consolidated helper for function signature formatting
        try ZigFormattingHelpers.formatWithZigSpacing(signature, builder);
    }
    
    fn formatStatementWithSpacing(statement: []const u8, builder: *LineBuilder) !void {
        // Check if this statement contains a struct literal
        if (std.mem.indexOf(u8, statement, "{") != null and std.mem.indexOf(u8, statement, "}") != null) {
            try formatStatementWithStructLiteral(std.heap.page_allocator, statement, builder);
            return;
        }
        
        // Use consolidated helper for statement spacing
        try ZigFormattingHelpers.formatWithZigSpacing(statement, builder);
    }
    
    /// Format statement that contains struct literals
    fn formatStatementWithStructLiteral(allocator: std.mem.Allocator, statement: []const u8, builder: *LineBuilder) !void {
        // Find struct literal pattern: TypeName{...}
        if (std.mem.indexOf(u8, statement, "{")) |brace_start| {
            // Get the part before the brace
            const before_brace = std.mem.trim(u8, statement[0..brace_start], " \t");
            try builder.append(before_brace);
            try builder.append("{");
            
            // Find matching closing brace
            if (std.mem.lastIndexOf(u8, statement, "}")) |brace_end| {
                const content = std.mem.trim(u8, statement[brace_start + 1..brace_end], " \t");
                
                if (content.len > 0) {
                    try builder.newline();
                    builder.indent();
                    
                    // Format the struct literal content
                    try formatStructLiteralContent(allocator, builder, content);
                    
                    builder.dedent();
                    try builder.appendIndent();
                }
                
                try builder.append("}");
                
                // Handle any content after the closing brace
                const after_brace = std.mem.trim(u8, statement[brace_end + 1..], " \t");
                if (after_brace.len > 0) {
                    try builder.append(after_brace);
                }
            }
        } else {
            // Fallback: just append the statement as-is
            try builder.append(statement);
        }
    }

    fn formatDeclarationWithSpacing(declaration: []const u8, builder: *LineBuilder) !void {
        try FormatDeclaration.formatDeclaration(declaration, builder);
    }
    
    /// Format union type declaration (e.g. "union(enum)" with proper spacing)
    fn formatUnionTypeDeclaration(union_type: []const u8, builder: *LineBuilder) !void {
        // Look for parentheses in union type
        if (std.mem.indexOf(u8, union_type, "(")) |paren_start| {
            if (std.mem.lastIndexOf(u8, union_type, ")")) |paren_end| {
                const before_paren = std.mem.trim(u8, union_type[0..paren_start], " \t");
                const inside_paren = std.mem.trim(u8, union_type[paren_start + 1..paren_end], " \t");
                const after_paren = std.mem.trim(u8, union_type[paren_end + 1..], " \t");
                
                try builder.append(before_paren);
                try builder.append("(");
                try builder.append(inside_paren);
                try builder.append(")");
                
                if (after_paren.len > 0) {
                    try builder.append(" ");
                    try builder.append(after_paren);
                }
            } else {
                // Malformed, just append as-is
                try builder.append(union_type);
            }
        } else {
            // Simple union, just append
            try builder.append(union_type);
        }
    }
};