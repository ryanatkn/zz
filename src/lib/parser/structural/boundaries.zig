const std = @import("std");
const Token = @import("../lexical/mod.zig").Token;
const TokenKind = @import("../lexical/mod.zig").TokenKind;
const Language = @import("../lexical/mod.zig").Language;
const Span = @import("../foundation/types/span.zig").Span;
const BoundaryKind = @import("../foundation/types/predicate.zig").BoundaryKind;

/// Hint about a potential boundary detected during scanning
pub const BoundaryHint = struct {
    /// Location of the boundary
    span: Span,

    /// Type of boundary detected
    kind: BoundaryKind,

    /// Confidence level (0.0 to 1.0)
    confidence: f32,

    /// Token index where boundary starts
    start_token_idx: usize,

    /// Token index where boundary ends (if known)
    end_token_idx: ?usize,

    /// Bracket depth at boundary start
    depth: u16,

    /// Additional metadata
    metadata: BoundaryMetadata,

    pub fn init(
        span: Span,
        kind: BoundaryKind,
        confidence: f32,
        start_idx: usize,
        depth: u16,
    ) BoundaryHint {
        return .{
            .span = span,
            .kind = kind,
            .confidence = confidence,
            .start_token_idx = start_idx,
            .end_token_idx = null,
            .depth = depth,
            .metadata = BoundaryMetadata{},
        };
    }

    pub fn withEnd(self: BoundaryHint, end_idx: usize, end_span: Span) BoundaryHint {
        var hint = self;
        hint.end_token_idx = end_idx;
        hint.span = Span.init(self.span.start, end_span.end);
        return hint;
    }

    pub fn withMetadata(self: BoundaryHint, metadata: BoundaryMetadata) BoundaryHint {
        var hint = self;
        hint.metadata = metadata;
        return hint;
    }
};

/// Additional metadata about detected boundaries
pub const BoundaryMetadata = struct {
    /// Whether this boundary can be folded in editor
    is_foldable: bool = false,

    /// Whether this boundary has parameters/arguments
    has_parameters: bool = false,

    /// Whether this boundary has a return type
    has_return_type: bool = false,

    /// Whether this boundary has visibility modifiers
    is_public: bool = false,

    /// Whether this boundary is inline/short
    is_inline: bool = false,

    /// Estimated complexity (number of statements)
    complexity: u16 = 0,
};

/// Pattern for detecting specific boundary types
pub const BoundaryPattern = struct {
    /// Required token sequence
    tokens: []const TokenKind,

    /// Required literal text (if any)
    literals: []const []const u8,

    /// Boundary type this pattern detects
    boundary_kind: BoundaryKind,

    /// Base confidence for this pattern
    confidence: f32,

    /// Minimum tokens required for match
    min_tokens: usize,

    pub fn init(
        tokens: []const TokenKind,
        literals: []const []const u8,
        boundary_kind: BoundaryKind,
        confidence: f32,
    ) BoundaryPattern {
        return .{
            .tokens = tokens,
            .literals = literals,
            .boundary_kind = boundary_kind,
            .confidence = confidence,
            .min_tokens = tokens.len,
        };
    }
};

/// High-performance boundary detector using pattern matching
pub const BoundaryDetector = struct {
    /// Language-specific patterns
    patterns: []const BoundaryPattern,

    /// Current language
    language: Language,

    /// Allocator for temporary allocations
    allocator: std.mem.Allocator,

    /// Statistics for performance monitoring
    stats: DetectorStats,

    pub fn init(allocator: std.mem.Allocator, language: Language) BoundaryDetector {
        const patterns = switch (language) {
            .zig => &ZIG_PATTERNS,
            .typescript => &TS_PATTERNS,
            .json => &JSON_PATTERNS,
            else => &GENERIC_PATTERNS,
        };

        return .{
            .patterns = patterns,
            .language = language,
            .allocator = allocator,
            .stats = DetectorStats{},
        };
    }

    pub fn deinit(self: *BoundaryDetector) void {
        _ = self;
        // No cleanup needed for static patterns
    }

    /// Detect boundaries in a token stream
    pub fn detectBoundaries(
        self: *BoundaryDetector,
        tokens: []const Token,
    ) ![]BoundaryHint {
        const timer = std.time.nanoTimestamp();
        defer {
            const elapsed: u64 = @intCast(std.time.nanoTimestamp() - timer);
            self.stats.total_time_ns += elapsed;
            self.stats.detection_runs += 1;
        }

        var hints = std.ArrayList(BoundaryHint).init(self.allocator);
        errdefer hints.deinit();

        var i: usize = 0;
        while (i < tokens.len) {
            // Try each pattern at current position
            if (try self.detectBoundaryAtPosition(tokens, i)) |hint| {
                try hints.append(hint);
                self.stats.boundaries_detected += 1;

                // Skip past the detected boundary to avoid overlaps
                // Use the pattern length to skip at minimum, or end token if available
                const min_skip = self.getPatternLength(hint.kind);
                const skip_distance = if (hint.end_token_idx) |end_idx|
                    @max(end_idx + 1 - i, min_skip)
                else
                    min_skip;

                i += skip_distance;
            } else {
                i += 1;
            }
        }

        self.stats.tokens_processed += tokens.len;
        return hints.toOwnedSlice();
    }

    /// Detect single boundary at specific position
    pub fn detectBoundaryAtPosition(
        self: *BoundaryDetector,
        tokens: []const Token,
        position: usize,
    ) !?BoundaryHint {
        if (position >= tokens.len) return null;

        // Try each pattern, but prioritize longer patterns first
        // This prevents "fn" from matching when "pub fn" should match
        var best_hint: ?BoundaryHint = null;
        var best_pattern_length: usize = 0;

        for (self.patterns) |pattern| {
            if (try self.matchPattern(tokens, position, pattern)) |hint| {
                // Prefer longer patterns (more specific matches)
                if (pattern.min_tokens > best_pattern_length) {
                    best_hint = hint;
                    best_pattern_length = pattern.min_tokens;
                }
            }
        }

        return best_hint;
    }

    /// Find matching closing boundary for an opening boundary
    pub fn findClosingBoundary(
        self: *BoundaryDetector,
        tokens: []const Token,
        start_idx: usize,
        boundary_kind: BoundaryKind,
    ) ?usize {
        if (start_idx >= tokens.len) return null;

        const start_depth = tokens[start_idx].bracket_depth;

        // Look for matching bracket depth and appropriate closing token
        for (tokens[start_idx + 1 ..], start_idx + 1..) |token, idx| {
            // If we're back to the same depth and see a closing delimiter
            if (token.bracket_depth == start_depth and
                self.isClosingToken(token, boundary_kind))
            {
                return idx;
            }
        }

        return null;
    }

    /// Get detection statistics
    pub fn getStats(self: BoundaryDetector) DetectorStats {
        return self.stats;
    }

    /// Reset statistics
    pub fn resetStats(self: *BoundaryDetector) void {
        self.stats = DetectorStats{};
    }

    /// Get minimum pattern length for a boundary kind
    fn getPatternLength(self: *BoundaryDetector, kind: BoundaryKind) usize {
        // Find the shortest pattern for this boundary kind
        var min_length: usize = 1;
        for (self.patterns) |pattern| {
            if (pattern.boundary_kind == kind) {
                min_length = @max(min_length, pattern.min_tokens);
            }
        }
        return min_length;
    }

    // ========================================================================
    // Private Implementation
    // ========================================================================

    /// Match a pattern against tokens at given position
    fn matchPattern(
        self: *BoundaryDetector,
        tokens: []const Token,
        position: usize,
        pattern: BoundaryPattern,
    ) !?BoundaryHint {
        if (position + pattern.min_tokens > tokens.len) return null;

        // Check token kinds match
        for (pattern.tokens, 0..) |expected_kind, i| {
            if (position + i >= tokens.len) return null;

            const actual_token = tokens[position + i];
            if (actual_token.kind != expected_kind) return null;
        }

        // Check literal text matches (if specified)
        for (pattern.literals, 0..) |expected_literal, i| {
            if (position + i >= tokens.len) return null;

            const actual_token = tokens[position + i];
            if (!std.mem.eql(u8, actual_token.text, expected_literal)) return null;
        }

        // Pattern matched - create boundary hint
        const start_token = tokens[position];
        const start_span = start_token.span;

        var hint = BoundaryHint.init(
            start_span,
            pattern.boundary_kind,
            pattern.confidence,
            position,
            start_token.bracket_depth,
        );

        // Try to find the end of this boundary
        if (self.findClosingBoundary(tokens, position, pattern.boundary_kind)) |end_idx| {
            const end_token = tokens[end_idx];
            hint = hint.withEnd(end_idx, end_token.span);
        }

        // Add metadata based on pattern analysis
        hint = hint.withMetadata(self.analyzeBoundaryMetadata(tokens, position, pattern));

        return hint;
    }

    /// Check if token is a closing token for boundary type
    fn isClosingToken(self: *BoundaryDetector, token: Token, boundary_kind: BoundaryKind) bool {
        _ = self;
        return switch (boundary_kind) {
            .function, .struct_, .struct_definition, .enum_, .enum_definition, .class, .block => token.kind == .delimiter and std.mem.eql(u8, token.text, "}"),
            .module, .namespace =>
            // Modules typically don't have explicit closing
            false,
        };
    }

    /// Analyze boundary metadata from context
    fn analyzeBoundaryMetadata(
        self: *BoundaryDetector,
        tokens: []const Token,
        position: usize,
        pattern: BoundaryPattern,
    ) BoundaryMetadata {
        _ = self;
        _ = pattern;

        var metadata = BoundaryMetadata{};

        // Look ahead for parameters, return types, etc.
        const lookahead_limit = @min(position + 10, tokens.len);
        for (tokens[position..lookahead_limit]) |token| {
            switch (token.kind) {
                .delimiter => {
                    if (std.mem.eql(u8, token.text, "(")) {
                        metadata.has_parameters = true;
                    }
                },
                .operator => {
                    // Look for return type indicators like "->"
                    if (std.mem.eql(u8, token.text, "->")) {
                        metadata.has_return_type = true;
                    }
                },
                .keyword => {
                    if (std.mem.eql(u8, token.text, "pub")) {
                        metadata.is_public = true;
                    }
                },
                else => {},
            }
        }

        // Most boundaries are foldable by default
        metadata.is_foldable = true;

        return metadata;
    }
};

/// Detection statistics for performance monitoring
pub const DetectorStats = struct {
    /// Total boundaries detected
    boundaries_detected: usize = 0,

    /// Total tokens processed
    tokens_processed: usize = 0,

    /// Number of detection runs
    detection_runs: usize = 0,

    /// Total processing time (nanoseconds)
    total_time_ns: u64 = 0,

    /// Pattern match attempts
    pattern_attempts: usize = 0,

    /// Successful pattern matches
    pattern_matches: usize = 0,

    pub fn boundariesPerSecond(self: DetectorStats) f64 {
        if (self.total_time_ns == 0) return 0.0;
        const seconds = @as(f64, @floatFromInt(self.total_time_ns)) / 1_000_000_000.0;
        return @as(f64, @floatFromInt(self.boundaries_detected)) / seconds;
    }

    pub fn tokensPerSecond(self: DetectorStats) f64 {
        if (self.total_time_ns == 0) return 0.0;
        const seconds = @as(f64, @floatFromInt(self.total_time_ns)) / 1_000_000_000.0;
        return @as(f64, @floatFromInt(self.tokens_processed)) / seconds;
    }

    pub fn patternMatchRate(self: DetectorStats) f64 {
        if (self.pattern_attempts == 0) return 0.0;
        return @as(f64, @floatFromInt(self.pattern_matches)) / @as(f64, @floatFromInt(self.pattern_attempts));
    }
};

// ============================================================================
// Language-Specific Patterns
// ============================================================================

/// Zig language boundary patterns
const ZIG_PATTERNS = [_]BoundaryPattern{
    // Function definition: "pub fn" or "fn"
    BoundaryPattern.init(
        &[_]TokenKind{ .keyword, .keyword }, // "pub fn"
        &[_][]const u8{ "pub", "fn" },
        .function,
        0.95,
    ),
    BoundaryPattern.init(
        &[_]TokenKind{.keyword}, // "fn"
        &[_][]const u8{"fn"},
        .function,
        0.9,
    ),

    // Struct definition
    BoundaryPattern.init(
        &[_]TokenKind{ .keyword, .keyword }, // "pub struct"
        &[_][]const u8{ "pub", "struct" },
        .struct_,
        0.95,
    ),
    BoundaryPattern.init(
        &[_]TokenKind{.keyword}, // "struct"
        &[_][]const u8{"struct"},
        .struct_,
        0.9,
    ),

    // Enum definition
    BoundaryPattern.init(
        &[_]TokenKind{ .keyword, .keyword }, // "pub enum"
        &[_][]const u8{ "pub", "enum" },
        .enum_,
        0.95,
    ),
    BoundaryPattern.init(
        &[_]TokenKind{.keyword}, // "enum"
        &[_][]const u8{"enum"},
        .enum_,
        0.9,
    ),
};

/// TypeScript boundary patterns
const TS_PATTERNS = [_]BoundaryPattern{
    // Function definition
    BoundaryPattern.init(
        &[_]TokenKind{.keyword}, // "function"
        &[_][]const u8{"function"},
        .function,
        0.9,
    ),

    // Class definition
    BoundaryPattern.init(
        &[_]TokenKind{.keyword}, // "class"
        &[_][]const u8{"class"},
        .class,
        0.9,
    ),
};

/// JSON boundary patterns (simple)
const JSON_PATTERNS = [_]BoundaryPattern{
    // Object boundary
    BoundaryPattern.init(
        &[_]TokenKind{.delimiter}, // "{"
        &[_][]const u8{"{"},
        .block,
        0.95,
    ),
};

/// Generic boundary patterns
const GENERIC_PATTERNS = [_]BoundaryPattern{
    // Generic block
    BoundaryPattern.init(
        &[_]TokenKind{.delimiter}, // "{"
        &[_][]const u8{"{"},
        .block,
        0.7,
    ),
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "boundary detector initialization" {
    var detector = BoundaryDetector.init(testing.allocator, .zig);
    defer detector.deinit();

    try testing.expectEqual(Language.zig, detector.language);
    try testing.expectEqual(@as(usize, 0), detector.stats.boundaries_detected);
}

test "zig function pattern matching" {
    var detector = BoundaryDetector.init(testing.allocator, .zig);
    defer detector.deinit();

    // Create mock tokens for "fn test() {"
    const tokens = [_]Token{
        Token.simple(Span.init(0, 2), .keyword, "fn", 0),
        Token.simple(Span.init(3, 7), .identifier, "test", 0),
        Token.simple(Span.init(7, 8), .delimiter, "(", 1),
        Token.simple(Span.init(8, 9), .delimiter, ")", 0),
        Token.simple(Span.init(10, 11), .delimiter, "{", 1),
    };

    const hint = try detector.detectBoundaryAtPosition(&tokens, 0);
    try testing.expect(hint != null);
    try testing.expectEqual(BoundaryKind.function, hint.?.kind);
    try testing.expectEqual(@as(f32, 0.9), hint.?.confidence);
}

test "boundary detection performance" {
    var detector = BoundaryDetector.init(testing.allocator, .zig);
    defer detector.deinit();

    // Create a larger token stream
    var tokens = std.ArrayList(Token).init(testing.allocator);
    defer tokens.deinit();

    // Add 100 function definitions
    for (0..100) |i| {
        const offset = i * 5;
        try tokens.append(Token.simple(Span.init(offset, offset + 2), .keyword, "fn", 0));
        try tokens.append(Token.simple(Span.init(offset + 3, offset + 7), .identifier, "test", 0));
        try tokens.append(Token.simple(Span.init(offset + 7, offset + 8), .delimiter, "(", 1));
        try tokens.append(Token.simple(Span.init(offset + 8, offset + 9), .delimiter, ")", 0));
        try tokens.append(Token.simple(Span.init(offset + 10, offset + 11), .delimiter, "{", 1));
    }

    const hints = try detector.detectBoundaries(tokens.items);
    defer testing.allocator.free(hints);

    try testing.expectEqual(@as(usize, 100), hints.len);
    try testing.expect(detector.stats.boundariesPerSecond() > 1000); // Should be very fast
}
