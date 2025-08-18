const std = @import("std");
const escape_mod = @import("escape.zig");

/// Quote style management for strings
/// Handles different quoting styles across languages and formats
pub const QuoteManager = struct {
    allocator: std.mem.Allocator,
    escaper: escape_mod.Escaper,

    const Self = @This();

    /// Quote style enumeration
    pub const QuoteStyle = enum {
        single,         // 'text'
        double,         // "text"
        backtick,       // `text`
        triple_single,  // '''text'''
        triple_double,  // """text"""
        heredoc,        // <<EOF...EOF
        none,          // No quotes
        auto,          // Automatically choose best style
    };

    /// Quote options
    pub const QuoteOptions = struct {
        style: QuoteStyle = .double,
        escape_inner: bool = true,
        multiline: bool = false,
        raw: bool = false, // Raw strings (no escaping)
        language: escape_mod.Escaper.Language = .json,
        prefer_single: bool = false, // For auto mode
        indent: ?usize = null, // Indentation for multiline
    };

    /// Quote detection result
    pub const QuoteInfo = struct {
        style: QuoteStyle,
        start_pos: usize,
        end_pos: usize,
        has_escapes: bool,
        multiline: bool,
    };

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .escaper = escape_mod.Escaper.init(allocator),
        };
    }

    /// Add quotes to a string
    pub fn addQuotes(self: Self, text: []const u8, options: QuoteOptions) ![]u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        errdefer result.deinit();

        const style = if (options.style == .auto) 
            self.chooseBestStyle(text, options) 
        else 
            options.style;

        // Add opening quote
        try self.appendOpeningQuote(&result, style);

        // Add content
        if (options.escape_inner and !options.raw and style != .none) {
            const escaped = try self.escapeForQuoteStyle(text, style, options.language);
            defer self.allocator.free(escaped);
            try result.appendSlice(escaped);
        } else {
            try result.appendSlice(text);
        }

        // Add closing quote
        try self.appendClosingQuote(&result, style);

        return result.toOwnedSlice();
    }

    /// Remove quotes from a string
    pub fn stripQuotes(self: Self, text: []const u8) ![]u8 {
        const info = self.detectQuoteStyle(text);
        if (info.style == .none) {
            return self.allocator.dupe(u8, text);
        }

        const quote_len = self.getQuoteLength(info.style);
        if (text.len < quote_len * 2) {
            return self.allocator.dupe(u8, text);
        }

        const content = text[quote_len..text.len - quote_len];
        
        // Unescape if needed
        if (info.has_escapes) {
            return self.unescapeQuotedString(content, info.style);
        }
        
        return self.allocator.dupe(u8, content);
    }

    /// Detect quote style used in a string
    pub fn detectQuoteStyle(self: Self, text: []const u8) QuoteInfo {
        _ = self;
        
        // Check for triple quotes first (they're longer)
        if (text.len >= 6) {
            if (std.mem.startsWith(u8, text, "'''") and std.mem.endsWith(u8, text, "'''")) {
                return .{
                    .style = .triple_single,
                    .start_pos = 0,
                    .end_pos = text.len,
                    .has_escapes = std.mem.indexOf(u8, text[3..text.len-3], "\\'") != null,
                    .multiline = std.mem.indexOf(u8, text[3..text.len-3], "\n") != null,
                };
            }
            if (std.mem.startsWith(u8, text, "\"\"\"") and std.mem.endsWith(u8, text, "\"\"\"")) {
                return .{
                    .style = .triple_double,
                    .start_pos = 0,
                    .end_pos = text.len,
                    .has_escapes = std.mem.indexOf(u8, text[3..text.len-3], "\\\"") != null,
                    .multiline = std.mem.indexOf(u8, text[3..text.len-3], "\n") != null,
                };
            }
        }

        // Check for single character quotes
        if (text.len >= 2) {
            if (text[0] == '\'' and text[text.len - 1] == '\'') {
                return .{
                    .style = .single,
                    .start_pos = 0,
                    .end_pos = text.len,
                    .has_escapes = std.mem.indexOf(u8, text[1..text.len-1], "\\'") != null,
                    .multiline = false,
                };
            }
            if (text[0] == '"' and text[text.len - 1] == '"') {
                return .{
                    .style = .double,
                    .start_pos = 0,
                    .end_pos = text.len,
                    .has_escapes = std.mem.indexOf(u8, text[1..text.len-1], "\\\"") != null,
                    .multiline = false,
                };
            }
            if (text[0] == '`' and text[text.len - 1] == '`') {
                return .{
                    .style = .backtick,
                    .start_pos = 0,
                    .end_pos = text.len,
                    .has_escapes = std.mem.indexOf(u8, text[1..text.len-1], "\\`") != null,
                    .multiline = std.mem.indexOf(u8, text[1..text.len-1], "\n") != null,
                };
            }
        }

        return .{
            .style = .none,
            .start_pos = 0,
            .end_pos = text.len,
            .has_escapes = false,
            .multiline = false,
        };
    }

    /// Convert between quote styles
    pub fn convertQuotes(self: Self, text: []const u8, to_style: QuoteStyle) ![]u8 {
        const stripped = try self.stripQuotes(text);
        defer self.allocator.free(stripped);
        
        return self.addQuotes(stripped, .{
            .style = to_style,
            .escape_inner = true,
        });
    }

    /// Choose the best quote style for a string
    fn chooseBestStyle(self: Self, text: []const u8, options: QuoteOptions) QuoteStyle {
        _ = self;
        
        // Check if multiline
        const has_newlines = std.mem.indexOf(u8, text, "\n") != null;
        if (has_newlines and options.multiline) {
            // Prefer triple quotes for multiline
            const has_triple_single = std.mem.indexOf(u8, text, "'''") != null;
            const has_triple_double = std.mem.indexOf(u8, text, "\"\"\"") != null;
            
            if (!has_triple_double) return .triple_double;
            if (!has_triple_single) return .triple_single;
            return .backtick; // Fallback for multiline
        }

        // Count quote types in string
        var single_count: usize = 0;
        var double_count: usize = 0;
        var backtick_count: usize = 0;
        
        for (text) |char| {
            switch (char) {
                '\'' => single_count += 1,
                '"' => double_count += 1,
                '`' => backtick_count += 1,
                else => {},
            }
        }

        // Choose style with fewest conflicts
        if (options.prefer_single) {
            if (single_count == 0) return .single;
            if (double_count == 0) return .double;
            if (backtick_count == 0) return .backtick;
            return if (single_count <= double_count) .single else .double;
        } else {
            if (double_count == 0) return .double;
            if (single_count == 0) return .single;
            if (backtick_count == 0) return .backtick;
            return if (double_count <= single_count) .double else .single;
        }
    }

    /// Get the quote string for a style
    fn getQuoteString(style: QuoteStyle) []const u8 {
        return switch (style) {
            .single => "'",
            .double => "\"",
            .backtick => "`",
            .triple_single => "'''",
            .triple_double => "\"\"\"",
            .heredoc => "<<EOF",
            .none => "",
            .auto => "\"", // Default to double
        };
    }

    /// Get the length of quote markers
    fn getQuoteLength(self: Self, style: QuoteStyle) usize {
        _ = self;
        return switch (style) {
            .single, .double, .backtick => 1,
            .triple_single, .triple_double => 3,
            .heredoc => 5,
            .none, .auto => 0,
        };
    }

    /// Append opening quote
    fn appendOpeningQuote(self: Self, result: *std.ArrayList(u8), style: QuoteStyle) !void {
        _ = self;
        const quote = getQuoteString(style);
        try result.appendSlice(quote);
    }

    /// Append closing quote
    fn appendClosingQuote(self: Self, result: *std.ArrayList(u8), style: QuoteStyle) !void {
        _ = self;
        const quote = switch (style) {
            .heredoc => "\nEOF",
            else => getQuoteString(style),
        };
        try result.appendSlice(quote);
    }

    /// Escape string content for specific quote style
    fn escapeForQuoteStyle(self: Self, text: []const u8, style: QuoteStyle, language: escape_mod.Escaper.Language) ![]u8 {
        // Get base rules for language
        var rules = try self.escaper.getRules(language);
        defer rules.deinit();

        // Modify rules based on quote style
        switch (style) {
            .single => {
                // Ensure single quotes are escaped
                try rules.sequences.put('\'', "\\'");
                // Remove double quote escaping if present
                _ = rules.sequences.remove('"');
            },
            .double => {
                // Ensure double quotes are escaped
                try rules.sequences.put('"', "\\\"");
                // Remove single quote escaping if present
                _ = rules.sequences.remove('\'');
            },
            .backtick => {
                // Ensure backticks are escaped
                try rules.sequences.put('`', "\\`");
                // Template literal specific: ${
                if (language == .javascript or language == .typescript) {
                    // Would need to handle ${ specially
                }
            },
            .triple_single, .triple_double => {
                // Multiline strings often have different rules
                rules.preserve_newlines = true;
            },
            else => {},
        }

        return self.escaper.escapeWithRules(text, &rules);
    }

    /// Unescape a quoted string
    fn unescapeQuotedString(self: Self, text: []const u8, style: QuoteStyle) ![]u8 {
        _ = style;
        // Use appropriate language rules
        // For now, assume JSON-like escaping
        return self.escaper.unescape(text, .json);
    }

    /// Check if text contains quotes that would need escaping
    pub fn hasQuoteConflicts(self: Self, text: []const u8, style: QuoteStyle) bool {
        _ = self;
        const quote_char = switch (style) {
            .single => '\'',
            .double => '"',
            .backtick => '`',
            else => return false,
        };
        
        return std.mem.indexOfScalar(u8, text, quote_char) != null;
    }

    /// Wrap text in quotes if not already quoted
    pub fn ensureQuoted(self: Self, text: []const u8, options: QuoteOptions) ![]u8 {
        const info = self.detectQuoteStyle(text);
        if (info.style != .none) {
            // Already quoted
            if (options.style != .auto and info.style != options.style) {
                // Convert to requested style
                return self.convertQuotes(text, options.style);
            }
            return self.allocator.dupe(u8, text);
        }
        
        // Add quotes
        return self.addQuotes(text, options);
    }

    /// Remove outer quotes if present, otherwise return as-is
    pub fn ensureUnquoted(self: Self, text: []const u8) ![]u8 {
        const info = self.detectQuoteStyle(text);
        if (info.style != .none) {
            return self.stripQuotes(text);
        }
        return self.allocator.dupe(u8, text);
    }
};

// Tests
const testing = std.testing;

test "QuoteManager - add quotes" {
    const allocator = testing.allocator;
    const manager = QuoteManager.init(allocator);

    const text = "Hello World";
    const quoted = try manager.addQuotes(text, .{ .style = .double });
    defer allocator.free(quoted);

    try testing.expectEqualStrings("\"Hello World\"", quoted);
}

test "QuoteManager - strip quotes" {
    const allocator = testing.allocator;
    const manager = QuoteManager.init(allocator);

    const text = "\"Hello World\"";
    const stripped = try manager.stripQuotes(text);
    defer allocator.free(stripped);

    try testing.expectEqualStrings("Hello World", stripped);
}

test "QuoteManager - detect quote style" {
    const allocator = testing.allocator;
    const manager = QuoteManager.init(allocator);

    const single = "'Hello'";
    const double = "\"World\"";
    const triple = "'''Multi\nline'''";
    const none = "No quotes";

    try testing.expectEqual(QuoteManager.QuoteStyle.single, manager.detectQuoteStyle(single).style);
    try testing.expectEqual(QuoteManager.QuoteStyle.double, manager.detectQuoteStyle(double).style);
    try testing.expectEqual(QuoteManager.QuoteStyle.triple_single, manager.detectQuoteStyle(triple).style);
    try testing.expectEqual(QuoteManager.QuoteStyle.none, manager.detectQuoteStyle(none).style);
}

test "QuoteManager - convert quotes" {
    const allocator = testing.allocator;
    const manager = QuoteManager.init(allocator);

    const input = "'Hello World'";
    const converted = try manager.convertQuotes(input, .double);
    defer allocator.free(converted);

    try testing.expectEqualStrings("\"Hello World\"", converted);
}

test "QuoteManager - auto quote style" {
    const allocator = testing.allocator;
    const manager = QuoteManager.init(allocator);

    // Text with double quotes should use single quotes
    const text1 = "Hello \"World\"";
    const quoted1 = try manager.addQuotes(text1, .{ .style = .auto });
    defer allocator.free(quoted1);
    try testing.expect(quoted1[0] == '\'');

    // Text with single quotes should use double quotes
    const text2 = "It's great";
    const quoted2 = try manager.addQuotes(text2, .{ .style = .auto, .prefer_single = false });
    defer allocator.free(quoted2);
    try testing.expect(quoted2[0] == '"');
}

test "QuoteManager - escape inner quotes" {
    const allocator = testing.allocator;
    const manager = QuoteManager.init(allocator);

    const text = "Say \"Hello\"";
    const quoted = try manager.addQuotes(text, .{ 
        .style = .double,
        .escape_inner = true,
    });
    defer allocator.free(quoted);

    try testing.expectEqualStrings("\"Say \\\"Hello\\\"\"", quoted);
}

test "QuoteManager - ensure quoted/unquoted" {
    const allocator = testing.allocator;
    const manager = QuoteManager.init(allocator);

    // Ensure quoted when not quoted
    const unquoted = "Hello";
    const result1 = try manager.ensureQuoted(unquoted, .{ .style = .double });
    defer allocator.free(result1);
    try testing.expectEqualStrings("\"Hello\"", result1);

    // Ensure quoted when already quoted
    const quoted = "\"Hello\"";
    const result2 = try manager.ensureQuoted(quoted, .{ .style = .double });
    defer allocator.free(result2);
    try testing.expectEqualStrings("\"Hello\"", result2);

    // Ensure unquoted
    const result3 = try manager.ensureUnquoted(quoted);
    defer allocator.free(result3);
    try testing.expectEqualStrings("Hello", result3);
}