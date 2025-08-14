const std = @import("std");

/// Format options for different output contexts
pub const FormatOptions = struct {
    strip_colors: bool = false,
    markdown_code_blocks: bool = false,
    max_line_width: usize = 100,
    indent_size: usize = 2,
};

/// Format demo output for README insertion
pub fn formatForReadme(
    allocator: std.mem.Allocator,
    raw_output: []const u8,
) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();
    
    // Add markdown code block wrapper
    try result.appendSlice("```console\n");
    
    // Strip ANSI colors and clean up the output
    const cleaned = try stripAnsiCodes(allocator, raw_output);
    defer allocator.free(cleaned);
    
    try result.appendSlice(cleaned);
    
    // Ensure proper newline before closing
    if (!std.mem.endsWith(u8, cleaned, "\n")) {
        try result.append('\n');
    }
    
    try result.appendSlice("```");
    
    return result.toOwnedSlice();
}

/// Strip ANSI escape codes from text
pub fn stripAnsiCodes(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();
    
    var i: usize = 0;
    while (i < text.len) {
        if (i + 1 < text.len and text[i] == '\x1b' and text[i + 1] == '[') {
            // Skip ANSI escape sequence
            i += 2;
            // Skip until we find a letter (command character)
            while (i < text.len) {
                const c = text[i];
                i += 1;
                if (std.ascii.isAlphabetic(c)) {
                    break;
                }
            }
        } else {
            try result.append(text[i]);
            i += 1;
        }
    }
    
    return result.toOwnedSlice();
}

/// Format a command line for display
pub fn formatCommand(
    allocator: std.mem.Allocator,
    command: []const u8,
    args: []const []const u8,
    prefix: []const u8,
) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();
    
    try result.appendSlice(prefix);
    try result.appendSlice(command);
    
    for (args) |arg| {
        try result.append(' ');
        
        // Quote arguments that contain spaces or special characters
        const needs_quoting = std.mem.indexOfAny(u8, arg, " \t\n'\"\\$*?[]{}();&|<>") != null;
        if (needs_quoting) {
            try result.append('\'');
            // Escape single quotes in the argument
            for (arg) |c| {
                if (c == '\'') {
                    try result.appendSlice("'\\''");
                } else {
                    try result.append(c);
                }
            }
            try result.append('\'');
        } else {
            try result.appendSlice(arg);
        }
    }
    
    return result.toOwnedSlice();
}

/// Wrap text to a specific line width
pub fn wrapText(
    allocator: std.mem.Allocator,
    text: []const u8,
    max_width: usize,
    indent: usize,
) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();
    
    var lines = std.mem.tokenize(u8, text, "\n");
    while (lines.next()) |line| {
        if (line.len <= max_width) {
            // Line fits, add as-is
            for (0..indent) |_| {
                try result.append(' ');
            }
            try result.appendSlice(line);
            try result.append('\n');
        } else {
            // Need to wrap the line
            var pos: usize = 0;
            while (pos < line.len) {
                const end = @min(pos + max_width - indent, line.len);
                
                // Try to break at a word boundary
                var break_pos = end;
                if (end < line.len) {
                    // Look backwards for a space
                    var i = end;
                    while (i > pos) : (i -= 1) {
                        if (line[i] == ' ') {
                            break_pos = i;
                            break;
                        }
                    }
                }
                
                // Add indentation
                for (0..indent) |_| {
                    try result.append(' ');
                }
                
                // Add the line segment
                try result.appendSlice(line[pos..break_pos]);
                try result.append('\n');
                
                // Skip past any spaces at the break point
                pos = break_pos;
                while (pos < line.len and line[pos] == ' ') : (pos += 1) {}
            }
        }
    }
    
    return result.toOwnedSlice();
}

/// Format output as a markdown section
pub fn formatAsMarkdownSection(
    allocator: std.mem.Allocator,
    title: []const u8,
    content: []const u8,
    level: u8,
) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();
    
    // Add markdown heading
    for (0..level) |_| {
        try result.append('#');
    }
    try result.append(' ');
    try result.appendSlice(title);
    try result.append('\n');
    try result.append('\n');
    
    // Add content
    try result.appendSlice(content);
    
    // Ensure proper spacing
    if (!std.mem.endsWith(u8, content, "\n\n")) {
        if (!std.mem.endsWith(u8, content, "\n")) {
            try result.append('\n');
        }
        try result.append('\n');
    }
    
    return result.toOwnedSlice();
}

/// Clean up terminal output for documentation
pub fn cleanTerminalOutput(
    allocator: std.mem.Allocator,
    output: []const u8,
) ![]u8 {
    // Strip ANSI codes
    const no_ansi = try stripAnsiCodes(allocator, output);
    defer allocator.free(no_ansi);
    
    // Remove excessive blank lines
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();
    
    var blank_count: usize = 0;
    var lines = std.mem.tokenize(u8, no_ansi, "\n");
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) {
            blank_count += 1;
            if (blank_count <= 1) {
                try result.append('\n');
            }
        } else {
            blank_count = 0;
            try result.appendSlice(line);
            try result.append('\n');
        }
    }
    
    return result.toOwnedSlice();
}