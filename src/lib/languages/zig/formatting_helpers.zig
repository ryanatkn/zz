const std = @import("std");
const ts = @import("tree-sitter");
const LineBuilder = @import("../../parsing/formatter.zig").LineBuilder;
const FormatterOptions = @import("../../parsing/formatter.zig").FormatterOptions;
const ZigUtils = @import("zig_utils.zig").ZigUtils;
const ZigParameterFormatter = @import("parameter_formatter.zig").ZigParameterFormatter;
const ZigDeclarationFormatter = @import("declaration_formatter.zig").ZigDeclarationFormatter;
const ZigBodyFormatter = @import("body_formatter.zig").ZigBodyFormatter;
const ZigStatementFormatter = @import("statement_formatter.zig").ZigStatementFormatter;

/// Zig-specific formatting helpers
pub const ZigFormattingHelpers = struct {

    /// Format Zig function signature with comptime support
    pub fn formatFunctionSignature(allocator: std.mem.Allocator, builder: *LineBuilder, signature: []const u8, options: FormatterOptions) !void {
        // Handle comptime parameters specially
        if (std.mem.indexOf(u8, signature, "comptime")) |_| {
            try formatComptimeSignature(allocator, builder, signature, options);
        } else {
            try ZigUtils.formatFunctionSignature(allocator, builder, signature, options);
        }
    }

    /// Format comptime function signatures
    fn formatComptimeSignature(allocator: std.mem.Allocator, builder: *LineBuilder, signature: []const u8, options: FormatterOptions) !void {
        // Split by opening paren
        if (std.mem.indexOf(u8, signature, "(")) |paren_pos| {
            // Format the function name part (e.g., "fn ArrayList")
            const name_part = std.mem.trim(u8, signature[0..paren_pos], " \t");
            try ZigUtils.formatDeclarationWithSpacing(name_part, builder);
            
            // Extract and format parameters with comptime handling
            if (std.mem.lastIndexOf(u8, signature, ")")) |close_paren| {
                const params = signature[paren_pos + 1..close_paren];
                try formatComptimeParameters(allocator, builder, params, options);
                
                // Handle return type
                if (close_paren + 1 < signature.len) {
                    const return_part = std.mem.trim(u8, signature[close_paren + 1..], " \t");
                    if (return_part.len > 0 and !std.mem.startsWith(u8, return_part, "{")) {
                        try builder.append(" ");
                        try ZigUtils.formatDeclarationWithSpacing(return_part, builder);
                    }
                }
            }
        }
    }

    /// Format parameters with comptime support
    fn formatComptimeParameters(allocator: std.mem.Allocator, builder: *LineBuilder, params_text: []const u8, options: FormatterOptions) !void {
        try ZigParameterFormatter.formatComptimeParameters(allocator, builder, params_text, options);
    }


    /// Format struct body with fields and methods
    pub fn formatStructBody(allocator: std.mem.Allocator, builder: *LineBuilder, content: []const u8) !void {
        try ZigBodyFormatter.formatStructBody(allocator, builder, content);
    }

    /// Parse struct content into individual members (fields and methods)
    fn parseStructMembers(allocator: std.mem.Allocator, content: []const u8) ![][]const u8 {
        var members = std.ArrayList([]const u8).init(allocator);
        defer members.deinit();

        var start: usize = 0;
        var brace_depth: i32 = 0;
        var in_string: bool = false;
        var string_char: u8 = 0;

        for (content, 0..) |char, i| {
            // Handle string boundaries
            if (!in_string and (char == '"' or char == '\'')) {
                in_string = true;
                string_char = char;
            } else if (in_string and char == string_char) {
                in_string = false;
            }

            if (!in_string) {
                switch (char) {
                    '{' => brace_depth += 1,
                    '}' => {
                        brace_depth -= 1;
                        // If we're back to depth 0, this might be the end of a method
                        if (brace_depth == 0) {
                            const member = std.mem.trim(u8, content[start..i+1], " \t\n\r");
                            if (member.len > 0) {
                                try members.append(try allocator.dupe(u8, member));
                            }
                            start = i + 1;
                        }
                    },
                    ',' => {
                        // Field separator at top level
                        if (brace_depth == 0) {
                            const member = std.mem.trim(u8, content[start..i], " \t\n\r");
                            if (member.len > 0) {
                                try members.append(try allocator.dupe(u8, member));
                            }
                            start = i + 1;
                        }
                    },
                    else => {},
                }
            }
        }

        // Handle final member if no trailing comma
        if (start < content.len) {
            const member = std.mem.trim(u8, content[start..], " \t\n\r");
            if (member.len > 0) {
                try members.append(try allocator.dupe(u8, member));
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
            
            // Format signature
            try formatFunctionSignature(allocator, builder, signature, .{});
            try builder.append(" {");
            
            if (body.len > 0) {
                try builder.newline();
                builder.indent();
                try builder.appendIndent();
                try ZigUtils.formatDeclarationWithSpacing(body, builder);
                try builder.newline();
                builder.dedent();
                try builder.appendIndent();
            }
            
            try builder.append("}");
        } else {
            // No body, just format the signature
            try formatFunctionSignature(allocator, builder, method, .{});
        }
    }

    /// Format enum body with proper value alignment
    pub fn formatEnumBody(allocator: std.mem.Allocator, builder: *LineBuilder, content: []const u8) !void {
        try ZigBodyFormatter.formatEnumBody(allocator, builder, content);
    }

    /// Format union body similar to enum
    pub fn formatUnionBody(allocator: std.mem.Allocator, builder: *LineBuilder, content: []const u8) !void {
        try ZigBodyFormatter.formatUnionBody(allocator, builder, content);
    }

    /// Check if a Zig declaration is a function
    pub fn isFunctionDecl(text: []const u8) bool {
        return ZigDeclarationFormatter.isFunctionDecl(text);
    }

    /// Check if a Zig declaration is a type declaration
    pub fn isTypeDecl(text: []const u8) bool {
        return ZigDeclarationFormatter.isTypeDecl(text);
    }

    /// Check if a Zig declaration is an import
    pub fn isImportDecl(text: []const u8) bool {
        return ZigDeclarationFormatter.isImportDecl(text);
    }

    /// Format return statement with struct support
    pub fn formatReturnWithStruct(allocator: std.mem.Allocator, builder: *LineBuilder, statement: []const u8) !void {
        try ZigStatementFormatter.formatReturnWithStruct(allocator, builder, statement);
    }

    /// Format return statement with struct type definition
    fn formatStructTypeReturn(allocator: std.mem.Allocator, builder: *LineBuilder, statement: []const u8) !void {
        if (std.mem.indexOf(u8, statement, "{")) |brace_start| {
            // Format "return struct"
            const return_part = std.mem.trim(u8, statement[0..brace_start], " \t");
            try ZigUtils.formatDeclarationWithSpacing(return_part, builder);
            try builder.append(" {");
            try builder.newline();
            
            // Extract and format struct body
            const struct_end = std.mem.lastIndexOf(u8, statement, "}") orelse statement.len;
            const struct_content = std.mem.trim(u8, statement[brace_start + 1..struct_end], " \t\n\r");
            
            if (struct_content.len > 0) {
                builder.indent();
                try formatStructBody(allocator, builder, struct_content);
                builder.dedent();
            }
            
            try builder.appendIndent();
            try builder.append("}");
        }
    }

    /// Format return statement with struct literal
    fn formatStructLiteralReturn(builder: *LineBuilder, statement: []const u8) !void {
        if (std.mem.indexOf(u8, statement, "{")) |brace_start| {
            const return_part = std.mem.trim(u8, statement[0..brace_start], " \t");
            try ZigUtils.formatDeclarationWithSpacing(return_part, builder);
            
            const struct_end = std.mem.lastIndexOf(u8, statement, "}") orelse statement.len;
            const struct_content = std.mem.trim(u8, statement[brace_start + 1..struct_end], " \t\n\r");
            
            if (struct_content.len > 0) {
                try builder.append("{");
                try builder.newline();
                builder.indent();
                
                // Format struct literal fields with proper spacing
                try formatStructLiteralFields(builder.allocator, builder, struct_content);
                
                builder.dedent();
                try builder.appendIndent();
                try builder.append("}");
            } else {
                try builder.append("{}");
            }
        }
    }

    /// Format struct literal fields with proper spacing around = signs
    fn formatStructLiteralFields(allocator: std.mem.Allocator, builder: *LineBuilder, content: []const u8) !void {
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
};