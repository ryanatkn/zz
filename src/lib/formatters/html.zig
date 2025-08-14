const std = @import("std");
const FormatterOptions = @import("../parsing/formatter.zig").FormatterOptions;
const LineBuilder = @import("../parsing/formatter.zig").LineBuilder;

pub fn format(allocator: std.mem.Allocator, source: []const u8, options: FormatterOptions) ![]const u8 {
    // For now, basic indentation fixing
    var builder = LineBuilder.init(allocator, options);
    defer builder.deinit();

    var lines = std.mem.tokenizeScalar(u8, source, '\n');
    var in_pre = false;

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");

        // Check for <pre> tags
        if (std.mem.indexOf(u8, trimmed, "<pre") != null) {
            in_pre = true;
        } else if (std.mem.indexOf(u8, trimmed, "</pre>") != null) {
            in_pre = false;
        }

        // Preserve content inside <pre> tags
        if (in_pre) {
            try builder.append(line);
            try builder.newline();
            continue;
        }

        // Auto-dedent for closing tags
        if (trimmed.len > 0 and trimmed[0] == '<' and trimmed[1] == '/') {
            if (builder.indent_level > 0) builder.dedent();
        }

        // Skip empty lines unless preserving
        if (trimmed.len == 0) {
            if (options.preserve_newlines) {
                try builder.newline();
            }
            continue;
        }

        try builder.appendIndent();
        try builder.append(trimmed);
        try builder.newline();

        // Auto-indent for opening tags (simple heuristic)
        if (shouldIndentAfter(trimmed)) {
            builder.indent();
        }
    }

    return builder.toOwnedSlice();
}

fn shouldIndentAfter(line: []const u8) bool {
    // Simple heuristic: indent after opening tags that aren't self-closing
    if (line.len < 2) return false;
    if (line[0] != '<') return false;
    if (line[1] == '/') return false; // Closing tag
    if (line[1] == '!') return false; // Comment or DOCTYPE

    // Check for self-closing tags
    const self_closing = [_][]const u8{ "<br", "<hr", "<img", "<input", "<meta", "<link", "<area", "<base", "<col", "<embed", "<source", "<track", "<wbr" };

    for (self_closing) |tag| {
        if (std.mem.startsWith(u8, line, tag)) {
            return false;
        }
    }

    // Check if tag closes on same line
    if (std.mem.indexOf(u8, line, "</") != null) {
        return false;
    }

    return true;
}
