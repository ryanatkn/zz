const std = @import("std");

/// Lexical Layer - Layer 0 of Stratified Parser Architecture
///
/// This module provides streaming tokenization with <0.1ms viewport latency,
/// character-level incremental updates, and zero-copy token generation.
///
/// Performance targets:
/// - Viewport tokenization: <100μs (50 lines)
/// - Single-line edit: <10μs update
/// - Full file (1000 lines): <1ms
/// - Memory usage: <2x file size

// ============================================================================
// Core Components
// ============================================================================

/// High-performance streaming tokenizer with incremental updates
pub const StreamingLexer = @import("tokenizer.zig").StreamingLexer;

/// Character-level scanning with UTF-8 support and SIMD preparation
pub const Scanner = @import("scanner.zig").Scanner;

/// Real-time bracket depth tracking and pair matching
pub const BracketTracker = @import("brackets.zig").BracketTracker;
pub const BracketPair = @import("brackets.zig").BracketPair;
pub const BracketInfo = @import("brackets.zig").BracketInfo;

/// Zero-copy buffer management for token generation
pub const Buffer = @import("buffer.zig").Buffer;
pub const BufferView = @import("buffer.zig").BufferView;

// ============================================================================
// Data Types
// ============================================================================

/// Import foundation types
pub const Span = @import("../foundation/types/span.zig").Span;
pub const Token = @import("../foundation/types/token.zig").Token;
pub const TokenKind = @import("../foundation/types/predicate.zig").TokenKind;
pub const DelimiterType = @import("../foundation/types/token.zig").DelimiterType;
pub const Generation = @import("../foundation/types/fact.zig").Generation;

/// Incremental edit representation
pub const Edit = struct {
    /// Range of text being modified
    range: Span,

    /// New text to replace the range
    new_text: []const u8,

    /// Generation this edit belongs to
    generation: Generation,

    pub fn init(range: Span, new_text: []const u8, generation: Generation) Edit {
        return .{
            .range = range,
            .new_text = new_text,
            .generation = generation,
        };
    }
};

/// Delta representing changes in token stream
pub const TokenDelta = struct {
    /// Token IDs that were removed
    removed: []u32,

    /// New tokens that were added
    added: []Token,

    /// Total range affected by the change
    affected_range: Span,

    /// Generation this delta applies to
    generation: Generation,

    pub fn init(allocator: std.mem.Allocator) TokenDelta {
        _ = allocator;
        return .{
            .removed = &.{},
            .added = &.{},
            .affected_range = Span.empty(),
            .generation = 0,
        };
    }

    pub fn deinit(self: *TokenDelta, allocator: std.mem.Allocator) void {
        // Only free if not pointing to static empty slices
        if (self.removed.len > 0) {
            allocator.free(self.removed);
        }
        if (self.added.len > 0) {
            allocator.free(self.added);
        }
    }
};

/// Token stream for managing sequences of tokens
pub const TokenStream = struct {
    /// Array of tokens
    tokens: std.ArrayList(Token),

    /// Current generation
    generation: Generation,

    /// Allocator for token management
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) TokenStream {
        return .{
            .tokens = std.ArrayList(Token).init(allocator),
            .generation = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TokenStream) void {
        self.tokens.deinit();
    }

    /// Add a token to the stream
    pub fn addToken(self: *TokenStream, token: Token) !void {
        try self.tokens.append(token);
    }

    /// Get tokens in a range
    pub fn getTokensInRange(self: TokenStream, range: Span) []const Token {
        // Binary search implementation for tokens in range
        var result = std.ArrayList(Token).init(self.allocator);

        for (self.tokens.items) |token| {
            if (range.overlaps(token.span)) {
                result.append(token) catch break;
            }
        }

        return result.toOwnedSlice() catch &.{};
    }

    /// Clear all tokens
    pub fn clear(self: *TokenStream) void {
        self.tokens.clearRetainingCapacity();
    }

    /// Get current token count
    pub fn count(self: TokenStream) usize {
        return self.tokens.items.len;
    }
};

// ============================================================================
// Lexer Configuration
// ============================================================================

/// Configuration for language-specific tokenization
pub const LexerConfig = struct {
    /// Language being tokenized
    language: Language,

    /// Whether to include trivia tokens (whitespace, comments)
    include_trivia: bool = false,

    /// Whether to track bracket depth during tokenization
    track_brackets: bool = true,

    /// Maximum bracket nesting depth to track
    max_bracket_depth: u16 = 256,

    /// Buffer size for tokenization
    buffer_size: usize = 8192,

    pub fn forLanguage(language: Language) LexerConfig {
        return .{
            .language = language,
        };
    }

    pub fn withTrivia(self: LexerConfig) LexerConfig {
        var config = self;
        config.include_trivia = true;
        return config;
    }
};

/// Supported languages for tokenization
pub const Language = enum {
    zig,
    typescript,
    json,
    css,
    html,
    generic,

    pub fn fromExtension(ext: []const u8) Language {
        if (std.mem.eql(u8, ext, ".zig")) return .zig;
        if (std.mem.eql(u8, ext, ".ts")) return .typescript;
        if (std.mem.eql(u8, ext, ".json")) return .json;
        if (std.mem.eql(u8, ext, ".css")) return .css;
        if (std.mem.eql(u8, ext, ".html") or std.mem.eql(u8, ext, ".htm")) return .html;
        return .generic;
    }
};

// ============================================================================
// Performance Utilities
// ============================================================================

/// Timer for measuring tokenization performance
pub const LexerTimer = struct {
    start_time: i128,

    pub fn start() LexerTimer {
        return .{
            .start_time = std.time.nanoTimestamp(),
        };
    }

    pub fn elapsedNs(self: LexerTimer) u64 {
        const end_time = std.time.nanoTimestamp();
        return @intCast(end_time - self.start_time);
    }

    pub fn elapsedUs(self: LexerTimer) f64 {
        const ns = self.elapsedNs();
        return @as(f64, @floatFromInt(ns)) / 1_000.0;
    }

    pub fn checkViewportTarget(self: LexerTimer) bool {
        return self.elapsedUs() < 100.0; // <100μs target
    }

    pub fn checkEditTarget(self: LexerTimer) bool {
        return self.elapsedUs() < 10.0; // <10μs target
    }
};

/// Tokenization statistics for performance monitoring
pub const LexerStats = struct {
    /// Total tokens processed
    tokens_processed: usize = 0,

    /// Total characters processed
    chars_processed: usize = 0,

    /// Number of edits processed
    edits_processed: usize = 0,

    /// Total tokenization time (nanoseconds)
    total_time_ns: u64 = 0,

    /// Peak memory usage
    peak_memory: usize = 0,

    /// Cache hit rate for bracket matching
    bracket_cache_hits: usize = 0,
    bracket_cache_misses: usize = 0,

    pub fn reset(self: *LexerStats) void {
        self.* = LexerStats{};
    }

    pub fn tokensPerSecond(self: LexerStats) f64 {
        if (self.total_time_ns == 0) return 0.0;
        const seconds = @as(f64, @floatFromInt(self.total_time_ns)) / 1_000_000_000.0;
        return @as(f64, @floatFromInt(self.tokens_processed)) / seconds;
    }

    pub fn charsPerSecond(self: LexerStats) f64 {
        if (self.total_time_ns == 0) return 0.0;
        const seconds = @as(f64, @floatFromInt(self.total_time_ns)) / 1_000_000_000.0;
        return @as(f64, @floatFromInt(self.chars_processed)) / seconds;
    }

    pub fn bracketCacheHitRate(self: LexerStats) f64 {
        const total = self.bracket_cache_hits + self.bracket_cache_misses;
        if (total == 0) return 0.0;
        return @as(f64, @floatFromInt(self.bracket_cache_hits)) / @as(f64, @floatFromInt(total));
    }
};

// ============================================================================
// Convenience Functions
// ============================================================================

/// Create a quick tokenizer for a specific language
pub fn createLexer(allocator: std.mem.Allocator, language: Language) !StreamingLexer {
    const config = LexerConfig.forLanguage(language);
    return StreamingLexer.init(allocator, config);
}

/// Tokenize a string quickly without incremental features
pub fn tokenizeString(allocator: std.mem.Allocator, text: []const u8, language: Language) ![]Token {
    var lexer = try createLexer(allocator, language);
    defer lexer.deinit();

    const span = Span.init(0, text.len);
    return lexer.tokenizeRange(text, span);
}

/// Check if a character is a bracket
pub fn isBracket(ch: u8) bool {
    return switch (ch) {
        '(', ')', '[', ']', '{', '}' => true,
        else => false,
    };
}

/// Get bracket type for a character
pub fn getBracketType(ch: u8) ?DelimiterType {
    return switch (ch) {
        '(' => .open_paren,
        ')' => .close_paren,
        '[' => .open_bracket,
        ']' => .close_bracket,
        '{' => .open_brace,
        '}' => .close_brace,
        else => null,
    };
}

// ============================================================================
// Tests
// ============================================================================

test "lexical module exports" {
    const testing = std.testing;

    // Test that all main types are accessible
    const config = LexerConfig.forLanguage(.zig);
    try testing.expectEqual(Language.zig, config.language);

    const stats = LexerStats{};
    try testing.expectEqual(@as(usize, 0), stats.tokens_processed);

    const timer = LexerTimer.start();
    try testing.expect(timer.start_time > 0);
}

test "language detection" {
    const testing = std.testing;

    try testing.expectEqual(Language.zig, Language.fromExtension(".zig"));
    try testing.expectEqual(Language.typescript, Language.fromExtension(".ts"));
    try testing.expectEqual(Language.json, Language.fromExtension(".json"));
    try testing.expectEqual(Language.css, Language.fromExtension(".css"));
    try testing.expectEqual(Language.html, Language.fromExtension(".html"));
    try testing.expectEqual(Language.html, Language.fromExtension(".htm"));
    try testing.expectEqual(Language.generic, Language.fromExtension(".xyz"));
}

test "bracket detection" {
    const testing = std.testing;

    try testing.expect(isBracket('('));
    try testing.expect(isBracket(')'));
    try testing.expect(isBracket('['));
    try testing.expect(isBracket(']'));
    try testing.expect(isBracket('{'));
    try testing.expect(isBracket('}'));
    try testing.expect(!isBracket('a'));
    try testing.expect(!isBracket(' '));

    try testing.expectEqual(DelimiterType.open_paren, getBracketType('(').?);
    try testing.expectEqual(DelimiterType.close_paren, getBracketType(')').?);
    try testing.expectEqual(@as(?DelimiterType, null), getBracketType('a'));
}

test "token stream operations" {
    const testing = std.testing;

    var stream = TokenStream.init(testing.allocator);
    defer stream.deinit();

    const span1 = Span.init(0, 5);
    const token1 = Token.simple(span1, .identifier, "hello", 0);

    try stream.addToken(token1);
    try testing.expectEqual(@as(usize, 1), stream.count());

    stream.clear();
    try testing.expectEqual(@as(usize, 0), stream.count());
}
