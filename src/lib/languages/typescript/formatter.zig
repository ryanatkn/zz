const std = @import("std");
const FormatterOptions = @import("../../parsing/formatter.zig").FormatterOptions;
const LineBuilder = @import("../../parsing/formatter.zig").LineBuilder;

/// Format TypeScript source code
pub fn format(allocator: std.mem.Allocator, source: []const u8, options: FormatterOptions) ![]const u8 {
    // TODO: Implement proper TypeScript formatting with tree-sitter AST
    // For now, return formatted with basic indentation
    var builder = LineBuilder.init(allocator, options);
    defer builder.deinit();

    var lines = std.mem.splitScalar(u8, source, '\n');
    var brace_depth: u32 = 0;
    var in_multiline_comment = false;

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");

        // Handle multiline comments
        if (std.mem.indexOf(u8, trimmed, "/*") != null) {
            in_multiline_comment = true;
        }
        if (std.mem.indexOf(u8, trimmed, "*/") != null) {
            in_multiline_comment = false;
            try builder.appendIndent();
            try builder.append(trimmed);
            try builder.newline();
            continue;
        }
        if (in_multiline_comment) {
            try builder.appendIndent();
            try builder.append(trimmed);
            try builder.newline();
            continue;
        }

        // Skip empty lines
        if (trimmed.len == 0) {
            try builder.newline();
            continue;
        }

        // Adjust indent before line for closing braces
        if (std.mem.startsWith(u8, trimmed, "}") and brace_depth > 0) {
            builder.dedent();
            brace_depth -= 1;
        }

        // Add indented line
        try builder.appendIndent();
        try builder.append(trimmed);
        try builder.newline();

        // Adjust indent after line for opening braces
        if (std.mem.indexOf(u8, trimmed, "{") != null) {
            builder.indent();
            brace_depth += 1;
        }
    }

    return builder.toOwnedSlice();
}
