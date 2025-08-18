const std = @import("std");
const char = @import("../char/mod.zig");

/// Smart indentation management extracted from formatters
/// Provides language-agnostic indentation detection, manipulation, and conversion
pub const IndentManager = struct {
    allocator: std.mem.Allocator,
    default_style: IndentStyle,
    default_size: u32,

    const Self = @This();

    pub const IndentStyle = enum {
        spaces,
        tabs,
        mixed, // Tabs for indentation, spaces for alignment
    };

    pub const IndentInfo = struct {
        style: IndentStyle,
        size: u32, // Number of spaces per indent level (or tab width)
        inconsistent: bool,
        mixed_lines: []const usize, // Line numbers with mixed indentation
    };

    pub fn init(allocator: std.mem.Allocator) IndentManager {
        return .{
            .allocator = allocator,
            .default_style = .spaces,
            .default_size = 4,
        };
    }

    pub fn initWithDefaults(allocator: std.mem.Allocator, style: IndentStyle, size: u32) IndentManager {
        return .{
            .allocator = allocator,
            .default_style = style,
            .default_size = size,
        };
    }

    /// Detect indentation style from text
    pub fn detectStyle(self: Self, text: []const u8) !IndentInfo {
        var space_lines: u32 = 0;
        var tab_lines: u32 = 0;
        var mixed_count: u32 = 0;
        var mixed_lines = std.ArrayList(usize).init(self.allocator);
        defer mixed_lines.deinit();

        var indent_sizes = std.ArrayList(u32).init(self.allocator);
        defer indent_sizes.deinit();

        var line_start: usize = 0;
        var line_num: usize = 0;

        // Analyze each line
        for (text, 0..) |ch, i| {
            if (ch == '\n' or i == text.len - 1) {
                const line_end = if (ch == '\n') i else i + 1;
                const line = text[line_start..line_end];

                // Check leading whitespace
                var spaces: u32 = 0;
                var tabs: u32 = 0;
                var j: usize = 0;

                while (j < line.len) : (j += 1) {
                    if (line[j] == ' ') {
                        spaces += 1;
                    } else if (line[j] == '\t') {
                        tabs += 1;
                    } else {
                        break; // Non-whitespace character
                    }
                }

                // Classify line
                if (spaces > 0 and tabs > 0) {
                    mixed_count += 1;
                    try mixed_lines.append(line_num);
                } else if (tabs > 0) {
                    tab_lines += 1;
                } else if (spaces > 0) {
                    space_lines += 1;
                    try indent_sizes.append(spaces);
                }

                line_start = i + 1;
                line_num += 1;
            }
        }

        // Determine style
        const style: IndentStyle = if (mixed_count > 0) .mixed else if (tab_lines > space_lines) .tabs else .spaces;

        // Calculate common indent size for spaces
        var common_size: u32 = self.default_size;
        if (indent_sizes.items.len > 0) {
            // Find GCD of all indent sizes to determine indent unit
            common_size = indent_sizes.items[0];
            for (indent_sizes.items[1..]) |size| {
                common_size = gcd(common_size, size);
            }
            if (common_size == 0 or common_size > 8) {
                common_size = self.default_size;
            }
        }

        return IndentInfo{
            .style = style,
            .size = common_size,
            .inconsistent = mixed_count > 0,
            .mixed_lines = try self.allocator.dupe(usize, mixed_lines.items),
        };
    }

    /// Indent text by specified levels
    pub fn indent(self: Self, text: []const u8, levels: u32, style: ?IndentStyle) ![]u8 {
        const use_style = style orelse self.default_style;
        const indent_str = try self.getIndentString(levels, use_style, self.default_size);
        defer self.allocator.free(indent_str);

        var result = std.ArrayList(u8).init(self.allocator);
        errdefer result.deinit();

        var line_start: usize = 0;
        for (text, 0..) |ch, i| {
            if (ch == '\n') {
                // Add indentation at start of line if non-empty
                if (line_start < i) {
                    try result.appendSlice(indent_str);
                    try result.appendSlice(text[line_start..i]);
                }
                try result.append('\n');
                line_start = i + 1;
            }
        }

        // Handle last line
        if (line_start < text.len) {
            try result.appendSlice(indent_str);
            try result.appendSlice(text[line_start..]);
        }

        return result.toOwnedSlice();
    }

    /// Remove one level of indentation
    pub fn dedent(self: Self, text: []const u8) ![]u8 {
        const info = try self.detectStyle(text);
        defer self.allocator.free(info.mixed_lines);
        const indent_str = try self.getIndentString(1, info.style, info.size);
        defer self.allocator.free(indent_str);

        var result = std.ArrayList(u8).init(self.allocator);
        errdefer result.deinit();

        var line_start: usize = 0;
        for (text, 0..) |ch, i| {
            if (ch == '\n') {
                const line = text[line_start..i];
                
                // Remove one level of indentation if present
                if (std.mem.startsWith(u8, line, indent_str)) {
                    try result.appendSlice(line[indent_str.len..]);
                } else {
                    try result.appendSlice(line);
                }
                try result.append('\n');
                line_start = i + 1;
            }
        }

        // Handle last line
        if (line_start < text.len) {
            const line = text[line_start..];
            if (std.mem.startsWith(u8, line, indent_str)) {
                try result.appendSlice(line[indent_str.len..]);
            } else {
                try result.appendSlice(line);
            }
        }

        return result.toOwnedSlice();
    }

    /// Convert between indentation styles
    pub fn convertStyle(
        self: Self,
        text: []const u8,
        to_style: IndentStyle,
        to_size: u32,
    ) ![]u8 {
        const from_info = try self.detectStyle(text);
        defer self.allocator.free(from_info.mixed_lines);
        
        var result = std.ArrayList(u8).init(self.allocator);
        errdefer result.deinit();

        var line_start: usize = 0;
        for (text, 0..) |ch, i| {
            if (ch == '\n') {
                const line = text[line_start..i];
                const converted_line = try self.convertLine(line, from_info, to_style, to_size);
                defer self.allocator.free(converted_line);
                try result.appendSlice(converted_line);
                try result.append('\n');
                line_start = i + 1;
            }
        }

        // Handle last line
        if (line_start < text.len) {
            const line = text[line_start..];
            const converted_line = try self.convertLine(line, from_info, to_style, to_size);
            defer self.allocator.free(converted_line);
            try result.appendSlice(converted_line);
        }

        return result.toOwnedSlice();
    }

    /// Get indentation string for level (caller owns returned memory)
    pub fn getIndentString(self: Self, level: u32, style: ?IndentStyle, size: ?u32) ![]u8 {
        const use_style = style orelse self.default_style;
        const use_size = size orelse self.default_size;

        const total_chars = switch (use_style) {
            .tabs, .mixed => level,
            .spaces => level * use_size,
        };

        var result = try self.allocator.alloc(u8, total_chars);
        
        switch (use_style) {
            .tabs, .mixed => {
                for (0..total_chars) |i| {
                    result[i] = '\t';
                }
            },
            .spaces => {
                for (0..total_chars) |i| {
                    result[i] = ' ';
                }
            },
        }

        return result;
    }

    /// Calculate indentation level of a line
    pub fn getLevel(self: Self, line: []const u8, style: ?IndentStyle, size: ?u32) u32 {
        const use_style = style orelse self.default_style;
        const use_size = size orelse self.default_size;

        var level: u32 = 0;
        for (line) |ch| {
            switch (use_style) {
                .tabs, .mixed => {
                    if (ch == '\t') {
                        level += 1;
                    } else if (ch != ' ') {
                        break;
                    }
                },
                .spaces => {
                    if (ch == ' ') {
                        level += 1;
                    } else {
                        break;
                    }
                },
            }
        }

        return switch (use_style) {
            .tabs, .mixed => level,
            .spaces => level / use_size,
        };
    }

    /// Helper: Convert a single line's indentation
    fn convertLine(self: Self, line: []const u8, from: IndentInfo, to_style: IndentStyle, to_size: u32) ![]u8 {
        // Count current indentation level
        const level = self.getLevel(line, from.style, from.size);
        
        // Skip past existing indentation
        var content_start: usize = 0;
        while (content_start < line.len and (line[content_start] == ' ' or line[content_start] == '\t')) {
            content_start += 1;
        }

        // Build new line with converted indentation
        var result = std.ArrayList(u8).init(self.allocator);
        errdefer result.deinit();

        const new_indent = try self.getIndentString(level, to_style, to_size);
        defer self.allocator.free(new_indent);
        try result.appendSlice(new_indent);
        try result.appendSlice(line[content_start..]);

        return result.toOwnedSlice();
    }

    /// Helper: Calculate GCD for indent size detection
    fn gcd(a: u32, b: u32) u32 {
        var x = a;
        var y = b;
        while (y != 0) {
            const temp = y;
            y = x % y;
            x = temp;
        }
        return x;
    }
};

// Tests
const testing = std.testing;

test "IndentManager - detect spaces" {
    const allocator = testing.allocator;
    const manager = IndentManager.init(allocator);

    const text =
        \\function test() {
        \\  const x = 1;
        \\  if (x > 0) {
        \\    return true;
        \\  }
        \\}
    ;

    const info = try manager.detectStyle(text);
    defer allocator.free(info.mixed_lines);

    try testing.expectEqual(IndentManager.IndentStyle.spaces, info.style);
    try testing.expectEqual(@as(u32, 2), info.size);
    try testing.expect(!info.inconsistent);
}

test "IndentManager - detect tabs" {
    const allocator = testing.allocator;
    const manager = IndentManager.init(allocator);

    const text = "function test() {\n\tconst x = 1;\n\treturn x;\n}";

    const info = try manager.detectStyle(text);
    defer allocator.free(info.mixed_lines);

    try testing.expectEqual(IndentManager.IndentStyle.tabs, info.style);
    try testing.expect(!info.inconsistent);
}

test "IndentManager - indent text" {
    const allocator = testing.allocator;
    const manager = IndentManager.init(allocator);

    const text =
        \\line 1
        \\line 2
        \\line 3
    ;

    const indented = try manager.indent(text, 1, .spaces);
    defer allocator.free(indented);

    try testing.expectEqualStrings(
        \\    line 1
        \\    line 2
        \\    line 3
    , indented);
}

test "IndentManager - dedent text" {
    const allocator = testing.allocator;
    const manager = IndentManager.init(allocator);

    const text =
        \\    line 1
        \\    line 2
        \\    line 3
    ;

    const dedented = try manager.dedent(text);
    defer allocator.free(dedented);

    try testing.expectEqualStrings(
        \\line 1
        \\line 2
        \\line 3
    , dedented);
}

test "IndentManager - convert spaces to tabs" {
    const allocator = testing.allocator;
    const manager = IndentManager.init(allocator);

    const text =
        \\function test() {
        \\    const x = 1;
        \\    return x;
        \\}
    ;

    const converted = try manager.convertStyle(text, .tabs, 4);
    defer allocator.free(converted);

    // Check that tabs are present
    try testing.expect(std.mem.indexOf(u8, converted, "\t") != null);
}