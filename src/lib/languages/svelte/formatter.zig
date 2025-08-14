const std = @import("std");
const FormatterOptions = @import("../../parsing/formatter.zig").FormatterOptions;
const LineBuilder = @import("../../parsing/formatter.zig").LineBuilder;

/// Format Svelte source code (basic implementation)
pub fn format(allocator: std.mem.Allocator, source: []const u8, options: FormatterOptions) ![]const u8 {
    // For now, return basic formatting with consistent indentation
    var builder = LineBuilder.init(allocator, options);
    defer builder.deinit();
    
    var lines = std.mem.splitScalar(u8, source, '\n');
    var in_script = false;
    var in_style = false;
    
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r\n");
        
        if (trimmed.len == 0) {
            try builder.newline();
            continue;
        }
        
        // Track sections
        if (std.mem.startsWith(u8, trimmed, "<script")) {
            in_script = true;
        } else if (std.mem.startsWith(u8, trimmed, "</script>")) {
            in_script = false;
        } else if (std.mem.startsWith(u8, trimmed, "<style")) {
            in_style = true;
        } else if (std.mem.startsWith(u8, trimmed, "</style>")) {
            in_style = false;
        }
        
        // Basic indentation for HTML-like content
        if (!in_script and !in_style) {
            if (std.mem.startsWith(u8, trimmed, "<") and !std.mem.startsWith(u8, trimmed, "</")) {
                try builder.appendIndent();
                try builder.append(trimmed);
                try builder.newline();
                if (!std.mem.endsWith(u8, trimmed, "/>")) {
                    builder.indent();
                }
            } else if (std.mem.startsWith(u8, trimmed, "</")) {
                builder.dedent();
                try builder.appendIndent();
                try builder.append(trimmed);
                try builder.newline();
            } else {
                try builder.appendIndent();
                try builder.append(trimmed);
                try builder.newline();
            }
        } else {
            // Keep script/style content as-is for now
            try builder.append(line);
            try builder.newline();
        }
    }
    
    return builder.toOwnedSlice();
}