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
        // Simple delegation to formatStructBody
        try formatStructBody(std.heap.page_allocator, builder, struct_text);
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

        var start: usize = 0;
        var brace_depth: i32 = 0;
        var in_string: bool = false;
        var string_char: u8 = 0;

        for (content, 0..) |char, i| {
            // Handle string boundaries
            if (!in_string and (char == '\"' or char == '\'')) {
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
            try formatFunctionSignature(allocator, builder, signature);
            try builder.append(" {");
            
            if (body.len > 0) {
                try builder.newline();
                builder.indent();
                try builder.appendIndent();
                try formatDeclarationWithSpacing(body, builder);
                try builder.newline();
                builder.dedent();
                try builder.appendIndent();
            }
            
            try builder.append("}");
        } else {
            // No body, just format the signature
            try formatFunctionSignature(allocator, builder, method);
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

    fn formatDeclarationWithSpacing(declaration: []const u8, builder: *LineBuilder) !void {
        try FormatDeclaration.formatDeclaration(declaration, builder);
    }
};