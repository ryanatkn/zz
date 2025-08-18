const std = @import("std");

/// Language-specific escape sequence handling
/// Provides unified interface for escaping/unescaping strings across different formats
pub const Escaper = struct {
    allocator: std.mem.Allocator,

    const Self = @This();

    /// Language/format enumeration
    pub const Language = enum {
        json,
        zon,
        javascript,
        typescript,
        html,
        xml,
        regex,
        csv,
        shell,
        custom,
    };

    /// Escape rules for a specific language
    pub const EscapeRules = struct {
        /// Characters that must be escaped
        must_escape: []const u8,
        
        /// Escape sequences map (char -> escape sequence)
        sequences: std.AutoHashMap(u8, []const u8),
        
        /// Unicode escape format
        unicode_format: UnicodeFormat,
        
        /// Options
        escape_non_ascii: bool = false,
        escape_control: bool = true,
        preserve_newlines: bool = false,
        use_hex_for_control: bool = false,
        
        pub const UnicodeFormat = enum {
            none,           // No unicode escaping
            hex_2,          // \xXX (ZON, Python)
            hex_4,          // \uXXXX (JSON, JavaScript)
            hex_6,          // \UXXXXXX (extended Unicode)
            hex_8,          // \UXXXXXXXX (full Unicode)
            html_dec,       // &#123; (HTML decimal)
            html_hex,       // &#x7B; (HTML hex)
            percent,        // %XX (URL encoding)
        };

        pub fn deinit(self: *@This()) void {
            self.sequences.deinit();
        }
    };

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
        };
    }

    /// Get built-in rules for a language
    pub fn getRules(self: Self, language: Language) !EscapeRules {
        return switch (language) {
            .json => try self.jsonRules(),
            .zon => try self.zonRules(),
            .javascript, .typescript => try self.javascriptRules(),
            .html => try self.htmlRules(),
            .xml => try self.xmlRules(),
            .regex => try self.regexRules(),
            .csv => try self.csvRules(),
            .shell => try self.shellRules(),
            .custom => EscapeRules{
                .must_escape = "",
                .sequences = std.AutoHashMap(u8, []const u8).init(self.allocator),
                .unicode_format = .none,
            },
        };
    }

    /// Escape a string according to language rules
    pub fn escape(self: Self, text: []const u8, language: Language) ![]u8 {
        var rules = try self.getRules(language);
        defer rules.deinit();
        return self.escapeWithRules(text, &rules);
    }

    /// Escape a string with custom rules
    pub fn escapeWithRules(self: Self, text: []const u8, rules: *const EscapeRules) ![]u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        errdefer result.deinit();

        for (text) |char| {
            // Check for direct escape sequence
            if (rules.sequences.get(char)) |seq| {
                try result.appendSlice(seq);
            }
            // Check if character must be escaped
            else if (std.mem.indexOfScalar(u8, rules.must_escape, char) != null) {
                try result.append('\\');
                try result.append(char);
            }
            // Check for control characters
            else if (char < 0x20 and rules.escape_control) {
                // Special handling for newline preservation
                if (char == '\n' and rules.preserve_newlines) {
                    try result.append('\n');
                } else if (rules.use_hex_for_control) {
                    try self.appendHexEscape(&result, char);
                } else {
                    try self.appendUnicodeEscape(&result, char, rules.unicode_format);
                }
            }
            // Check for non-ASCII
            else if (char > 0x7F and rules.escape_non_ascii) {
                try self.appendUnicodeEscape(&result, char, rules.unicode_format);
            }
            // Regular character
            else {
                try result.append(char);
            }
        }

        return result.toOwnedSlice();
    }

    /// Unescape a string according to language rules
    pub fn unescape(self: Self, text: []const u8, language: Language) ![]u8 {
        var rules = try self.getRules(language);
        defer rules.deinit();
        return self.unescapeWithRules(text, &rules);
    }

    /// Unescape a string with custom rules
    pub fn unescapeWithRules(self: Self, text: []const u8, rules: *const EscapeRules) ![]u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        errdefer result.deinit();

        var i: usize = 0;
        while (i < text.len) {
            if (text[i] == '\\' and i + 1 < text.len) {
                // Try to parse escape sequence
                const unescaped = try self.parseEscapeSequence(text[i + 1..], rules);
                try result.append(unescaped.char);
                i += unescaped.consumed + 1; // +1 for backslash
            } else {
                try result.append(text[i]);
                i += 1;
            }
        }

        return result.toOwnedSlice();
    }

    /// JSON escape rules
    fn jsonRules(self: Self) !EscapeRules {
        var sequences = std.AutoHashMap(u8, []const u8).init(self.allocator);
        try sequences.put('"', "\\\"");
        try sequences.put('\\', "\\\\");
        try sequences.put(0x08, "\\b"); // Backspace
        try sequences.put(0x0C, "\\f"); // Form feed
        try sequences.put('\n', "\\n");
        try sequences.put('\r', "\\r");
        try sequences.put('\t', "\\t");

        return EscapeRules{
            .must_escape = "\"\\",
            .sequences = sequences,
            .unicode_format = .hex_4,
            .escape_control = true,
            .escape_non_ascii = false,
        };
    }

    /// ZON escape rules
    fn zonRules(self: Self) !EscapeRules {
        var sequences = std.AutoHashMap(u8, []const u8).init(self.allocator);
        try sequences.put('"', "\\\"");
        try sequences.put('\\', "\\\\");
        try sequences.put('\n', "\\n");
        try sequences.put('\r', "\\r");
        try sequences.put('\t', "\\t");

        return EscapeRules{
            .must_escape = "\"\\",
            .sequences = sequences,
            .unicode_format = .hex_2,
            .escape_control = true,
            .preserve_newlines = true, // ZON supports multiline strings
        };
    }

    /// JavaScript/TypeScript escape rules
    fn javascriptRules(self: Self) !EscapeRules {
        var sequences = std.AutoHashMap(u8, []const u8).init(self.allocator);
        try sequences.put('"', "\\\"");
        try sequences.put('\'', "\\'");
        try sequences.put('\\', "\\\\");
        try sequences.put(0x08, "\\b"); // Backspace
        try sequences.put(0x0C, "\\f"); // Form feed
        try sequences.put('\n', "\\n");
        try sequences.put('\r', "\\r");
        try sequences.put('\t', "\\t");
        try sequences.put(0x0B, "\\v"); // Vertical tab

        return EscapeRules{
            .must_escape = "\"'\\`",
            .sequences = sequences,
            .unicode_format = .hex_4,
            .escape_control = true,
        };
    }

    /// HTML escape rules
    fn htmlRules(self: Self) !EscapeRules {
        var sequences = std.AutoHashMap(u8, []const u8).init(self.allocator);
        try sequences.put('&', "&amp;");
        try sequences.put('<', "&lt;");
        try sequences.put('>', "&gt;");
        try sequences.put('"', "&quot;");
        try sequences.put('\'', "&#39;");

        return EscapeRules{
            .must_escape = "&<>\"'",
            .sequences = sequences,
            .unicode_format = .html_dec,
            .escape_control = false,
        };
    }

    /// XML escape rules
    fn xmlRules(self: Self) !EscapeRules {
        var sequences = std.AutoHashMap(u8, []const u8).init(self.allocator);
        try sequences.put('&', "&amp;");
        try sequences.put('<', "&lt;");
        try sequences.put('>', "&gt;");
        try sequences.put('"', "&quot;");
        try sequences.put('\'', "&apos;");

        return EscapeRules{
            .must_escape = "&<>\"'",
            .sequences = sequences,
            .unicode_format = .html_hex,
            .escape_control = false,
        };
    }

    /// Regex escape rules
    fn regexRules(self: Self) !EscapeRules {
        var sequences = std.AutoHashMap(u8, []const u8).init(self.allocator);
        // Regex special characters
        const special = "^$.*+?()[]{}\\|";
        for (special) |c| {
            var buf: [2]u8 = .{ '\\', c };
            try sequences.put(c, try self.allocator.dupe(u8, &buf));
        }

        return EscapeRules{
            .must_escape = special,
            .sequences = sequences,
            .unicode_format = .hex_4,
            .escape_control = false,
        };
    }

    /// CSV escape rules
    fn csvRules(self: Self) !EscapeRules {
        var sequences = std.AutoHashMap(u8, []const u8).init(self.allocator);
        try sequences.put('"', "\"\""); // Double quotes in CSV

        return EscapeRules{
            .must_escape = "\"",
            .sequences = sequences,
            .unicode_format = .none,
            .escape_control = false,
            .preserve_newlines = true,
        };
    }

    /// Shell escape rules
    fn shellRules(self: Self) !EscapeRules {
        var sequences = std.AutoHashMap(u8, []const u8).init(self.allocator);
        const special = "$`\"\\!";
        for (special) |c| {
            var buf: [2]u8 = .{ '\\', c };
            try sequences.put(c, try self.allocator.dupe(u8, &buf));
        }

        return EscapeRules{
            .must_escape = special,
            .sequences = sequences,
            .unicode_format = .none,
            .escape_control = false,
        };
    }

    /// Append unicode escape sequence
    fn appendUnicodeEscape(self: Self, result: *std.ArrayList(u8), char: u8, format: EscapeRules.UnicodeFormat) !void {
        _ = self;
        switch (format) {
            .none => try result.append(char),
            .hex_2 => try result.writer().print("\\x{x:0>2}", .{char}),
            .hex_4 => try result.writer().print("\\u{x:0>4}", .{char}),
            .hex_6 => try result.writer().print("\\U{x:0>6}", .{char}),
            .hex_8 => try result.writer().print("\\U{x:0>8}", .{char}),
            .html_dec => try result.writer().print("&#{d};", .{char}),
            .html_hex => try result.writer().print("&#x{x};", .{char}),
            .percent => try result.writer().print("%{x:0>2}", .{char}),
        }
    }

    /// Append hex escape sequence
    fn appendHexEscape(self: Self, result: *std.ArrayList(u8), char: u8) !void {
        _ = self;
        try result.writer().print("\\x{x:0>2}", .{char});
    }

    /// Parse an escape sequence
    fn parseEscapeSequence(self: Self, text: []const u8, rules: *const EscapeRules) !struct { char: u8, consumed: usize } {
        _ = rules;
        _ = self;
        
        if (text.len == 0) return .{ .char = '\\', .consumed = 0 };

        // Simple escape sequences
        const char = switch (text[0]) {
            'n' => '\n',
            'r' => '\r',
            't' => '\t',
            'b' => 0x08, // Backspace
            'f' => 0x0C, // Form feed
            'v' => 0x0B, // Vertical tab
            '\\' => '\\',
            '"' => '"',
            '\'' => '\'',
            '/' => '/',
            // Hex escape \xXX
            'x' => if (text.len >= 3) blk: {
                const hex = text[1..3];
                const value = std.fmt.parseInt(u8, hex, 16) catch {
                    break :blk text[0];
                };
                return .{ .char = value, .consumed = 3 };
            } else text[0],
            // Unicode escape \uXXXX
            'u' => if (text.len >= 5) blk: {
                const hex = text[1..5];
                const value = std.fmt.parseInt(u16, hex, 16) catch {
                    break :blk text[0];
                };
                if (value <= 0xFF) {
                    return .{ .char = @intCast(value), .consumed = 5 };
                }
                break :blk text[0]; // Can't represent in u8
            } else text[0],
            else => text[0],
        };

        return .{ .char = char, .consumed = 1 };
    }

    /// Check if a character needs escaping
    pub fn needsEscape(self: Self, text: []const u8, language: Language) !bool {
        var rules = try self.getRules(language);
        defer rules.deinit();

        for (text) |char| {
            if (rules.sequences.contains(char)) return true;
            if (std.mem.indexOfScalar(u8, rules.must_escape, char) != null) return true;
            if (char < 0x20 and rules.escape_control) return true;
            if (char > 0x7F and rules.escape_non_ascii) return true;
        }
        return false;
    }
};

// Tests
const testing = std.testing;

test "Escaper - JSON escaping" {
    const allocator = testing.allocator;
    const escaper = Escaper.init(allocator);

    const input = "Hello \"World\"\n\tTab";
    const escaped = try escaper.escape(input, .json);
    defer allocator.free(escaped);

    try testing.expectEqualStrings("Hello \\\"World\\\"\\n\\tTab", escaped);
}

test "Escaper - JSON unescaping" {
    const allocator = testing.allocator;
    const escaper = Escaper.init(allocator);

    const input = "Hello \\\"World\\\"\\n\\tTab";
    const unescaped = try escaper.unescape(input, .json);
    defer allocator.free(unescaped);

    try testing.expectEqualStrings("Hello \"World\"\n\tTab", unescaped);
}

test "Escaper - HTML escaping" {
    const allocator = testing.allocator;
    const escaper = Escaper.init(allocator);

    const input = "<div class=\"test\">&copy;</div>";
    const escaped = try escaper.escape(input, .html);
    defer allocator.free(escaped);

    try testing.expectEqualStrings("&lt;div class=&quot;test&quot;&gt;&amp;copy;&lt;/div&gt;", escaped);
}

test "Escaper - needs escape check" {
    const allocator = testing.allocator;
    const escaper = Escaper.init(allocator);

    try testing.expect(try escaper.needsEscape("Hello \"World\"", .json));
    try testing.expect(!try escaper.needsEscape("Hello World", .json));
    try testing.expect(try escaper.needsEscape("Tab\there", .json));
}