const std = @import("std");
const LineBuilder = @import("../../parsing/formatter.zig").LineBuilder;
const FormatterOptions = @import("../../parsing/formatter.zig").FormatterOptions;

/// TypeScript-specific utilities extracted from generic helpers
pub const TypeScriptUtils = struct {

    /// Split text by delimiter, respecting nested structures
    pub fn splitByDelimiter(allocator: std.mem.Allocator, text: []const u8, delimiter: u8) ![][]const u8 {
        var parts = std.ArrayList([]const u8).init(allocator);
        defer parts.deinit();

        var start: usize = 0;
        var depth: i32 = 0;
        var in_string: bool = false;
        var string_char: u8 = 0;

        for (text, 0..) |char, i| {
            // Track string boundaries
            if (!in_string and (char == '"' or char == '\'' or char == '`')) {
                in_string = true;
                string_char = char;
            } else if (in_string and char == string_char) {
                in_string = false;
            }

            if (!in_string) {
                switch (char) {
                    '(', '[', '{', '<' => depth += 1,
                    ')', ']', '}', '>' => depth -= 1,
                    else => {
                        if (char == delimiter and depth == 0) {
                            const part = std.mem.trim(u8, text[start..i], " \t\n\r");
                            if (part.len > 0) {
                                try parts.append(try allocator.dupe(u8, part));
                            }
                            start = i + 1;
                        }
                    },
                }
            }
        }

        // Handle final part
        const final_part = std.mem.trim(u8, text[start..], " \t\n\r");
        if (final_part.len > 0) {
            try parts.append(try allocator.dupe(u8, final_part));
        }

        return parts.toOwnedSlice();
    }

    /// Format declaration with TypeScript-style spacing
    pub fn formatDeclarationWithSpacing(declaration: []const u8, builder: *LineBuilder) !void {
        var i: usize = 0;
        while (i < declaration.len) : (i += 1) {
            const char = declaration[i];
            
            if (char == ':') {
                // TypeScript style: no space before colon, space after colon
                try builder.append(":");
                if (i + 1 < declaration.len and declaration[i + 1] != ' ') {
                    try builder.append(" ");
                }
            } else if (char == '=') {
                // Add spacing around equals
                if (i > 0 and declaration[i-1] != ' ') {
                    try builder.append(" ");
                }
                try builder.append("=");
                if (i + 1 < declaration.len and declaration[i + 1] != ' ') {
                    try builder.append(" ");
                }
            } else {
                try builder.append(&[_]u8{char});
            }
        }
    }

    /// Format field declaration
    pub fn formatFieldDeclaration(field: []const u8, builder: *LineBuilder) !void {
        const trimmed = std.mem.trim(u8, field, " \t\n\r");
        try formatDeclarationWithSpacing(trimmed, builder);
    }

    /// Format parameter list with TypeScript-style spacing
    pub fn formatParameterList(allocator: std.mem.Allocator, builder: *LineBuilder, params_text: []const u8, options: FormatterOptions) !void {
        if (params_text.len == 0) {
            try builder.append("()");
            return;
        }

        const params = try splitByDelimiter(allocator, params_text, ',');
        defer allocator.free(params);

        // Calculate total length for multiline decision
        var total_length: u32 = 2; // For parentheses
        for (params) |param| {
            total_length += @intCast(param.len + 2); // +2 for ", "
        }

        const use_multiline = total_length > options.line_width;
        
        try builder.append("(");
        
        if (use_multiline) {
            try builder.newline();
            builder.indent();
            
            for (params, 0..) |param, i| {
                try builder.appendIndent();
                try formatSingleParameter(param, builder);
                if (i < params.len - 1) {
                    try builder.append(",");
                }
                try builder.newline();
            }
            
            builder.dedent();
            try builder.appendIndent();
        } else {
            for (params, 0..) |param, i| {
                try formatSingleParameter(param, builder);
                if (i < params.len - 1) {
                    try builder.append(", ");
                }
            }
        }
        
        try builder.append(")");
    }

    /// Format single parameter with TypeScript-style type annotations
    fn formatSingleParameter(param: []const u8, builder: *LineBuilder) !void {
        // TypeScript style: space before and after colon
        const trimmed = std.mem.trim(u8, param, " \t\n\r");
        try formatDeclarationWithSpacing(trimmed, builder);
    }

    /// Format function signature with TypeScript conventions
    pub fn formatFunctionSignature(allocator: std.mem.Allocator, builder: *LineBuilder, signature: []const u8, options: FormatterOptions) !void {
        // Find parameters and return type
        if (std.mem.indexOf(u8, signature, "(")) |paren_start| {
            if (std.mem.lastIndexOf(u8, signature, ")")) |paren_end| {
                // Format function name
                const name_part = std.mem.trim(u8, signature[0..paren_start], " \t");
                try formatDeclarationWithSpacing(name_part, builder);
                
                // Format parameters
                const params_text = signature[paren_start + 1..paren_end];
                try formatParameterList(allocator, builder, params_text, options);
                
                // Format return type
                if (paren_end + 1 < signature.len) {
                    const return_part = std.mem.trim(u8, signature[paren_end + 1..], " \t");
                    if (return_part.len > 0 and !std.mem.startsWith(u8, return_part, "{")) {
                        try formatDeclarationWithSpacing(return_part, builder);
                    }
                }
            }
        } else {
            // No parameters, just format as declaration
            try formatDeclarationWithSpacing(signature, builder);
        }
    }

    /// Format method chain
    pub fn formatMethodChain(allocator: std.mem.Allocator, builder: *LineBuilder, chain_text: []const u8, options: FormatterOptions) !void {
        _ = allocator;
        _ = options;
        // Simple method chain formatting
        const trimmed = std.mem.trim(u8, chain_text, " \t\n\r");
        try builder.append(trimmed);
    }

    /// Check if text represents a function declaration
    pub fn isFunctionDeclaration(text: []const u8) bool {
        const trimmed = std.mem.trim(u8, text, " \t\n\r");
        return std.mem.indexOf(u8, trimmed, "function ") != null or
               std.mem.indexOf(u8, trimmed, "() =>") != null or
               std.mem.indexOf(u8, trimmed, " => ") != null;
    }

    /// Check if text represents an interface declaration
    pub fn isInterfaceDeclaration(text: []const u8) bool {
        const trimmed = std.mem.trim(u8, text, " \t\n\r");
        return std.mem.startsWith(u8, trimmed, "interface ") or
               std.mem.startsWith(u8, trimmed, "export interface ");
    }

    /// Check if text represents a class declaration
    pub fn isClassDeclaration(text: []const u8) bool {
        const trimmed = std.mem.trim(u8, text, " \t\n\r");
        return std.mem.startsWith(u8, trimmed, "class ") or
               std.mem.startsWith(u8, trimmed, "export class ");
    }

    /// Format type annotation
    pub fn formatTypeAnnotation(type_text: []const u8, builder: *LineBuilder) !void {
        const trimmed = std.mem.trim(u8, type_text, " \t\n\r");
        try builder.append(trimmed);
    }
};