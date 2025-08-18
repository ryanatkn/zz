const std = @import("std");
const Token = @import("../lexical/mod.zig").Token;
const TokenKind = @import("../lexical/mod.zig").TokenKind;
const Language = @import("../lexical/mod.zig").Language;
const Span = @import("../foundation/types/span.zig").Span;
const BoundaryKind = @import("../foundation/types/predicate.zig").BoundaryKind;

/// Recovery point where parsing can resume after an error
pub const RecoveryPoint = struct {
    /// Location of the recovery point
    span: Span,

    /// Token index of recovery point
    token_idx: usize,

    /// Type of recovery strategy used
    strategy: RecoveryStrategy,

    /// Confidence that recovery is valid (0.0 to 1.0)
    confidence: f32,

    /// Bracket depth at recovery point
    bracket_depth: u16,

    /// What we were trying to parse when error occurred
    context: RecoveryContext,

    pub fn init(
        span: Span,
        token_idx: usize,
        strategy: RecoveryStrategy,
        confidence: f32,
        bracket_depth: u16,
        context: RecoveryContext,
    ) RecoveryPoint {
        return .{
            .span = span,
            .token_idx = token_idx,
            .strategy = strategy,
            .confidence = confidence,
            .bracket_depth = bracket_depth,
            .context = context,
        };
    }
};

/// Strategy used for error recovery
pub const RecoveryStrategy = enum {
    /// Skip to next balanced bracket
    bracket_sync,

    /// Skip to next statement/declaration
    statement_sync,

    /// Skip to next keyword
    keyword_sync,

    /// Skip to specific delimiter
    delimiter_sync,

    /// Skip to end of line
    line_sync,

    /// Skip to matching bracket depth
    depth_sync,

    /// No recovery possible
    no_recovery,
};

/// Context information about what was being parsed
pub const RecoveryContext = enum {
    /// In function definition
    function_definition,

    /// In struct definition
    struct_definition,

    /// In enum definition
    enum_definition,

    /// In block statement
    block_statement,

    /// In expression
    expression,

    /// In parameter list
    parameter_list,

    /// In type annotation
    type_annotation,

    /// Unknown context
    unknown,
};

/// Error region that couldn't be parsed
pub const ErrorRegion = struct {
    /// Span of the error region
    span: Span,

    /// Starting token index
    start_token_idx: usize,

    /// Ending token index (if known)
    end_token_idx: ?usize,

    /// Type of error detected
    error_kind: ErrorKind,

    /// Recovery points within this region
    recovery_points: []RecoveryPoint,

    /// Message describing the error
    message: []const u8,

    /// Severity of the error
    severity: ErrorSeverity,

    pub fn init(
        span: Span,
        start_idx: usize,
        error_kind: ErrorKind,
        message: []const u8,
    ) ErrorRegion {
        return .{
            .span = span,
            .start_token_idx = start_idx,
            .end_token_idx = null,
            .error_kind = error_kind,
            .recovery_points = &.{},
            .message = message,
            .severity = ErrorSeverity.err,
        };
    }

    pub fn withEnd(self: ErrorRegion, end_idx: usize, end_span: Span) ErrorRegion {
        var region = self;
        region.end_token_idx = end_idx;
        region.span = Span.init(self.span.start, end_span.end);
        return region;
    }

    pub fn withRecoveryPoints(self: ErrorRegion, recovery_points: []RecoveryPoint) ErrorRegion {
        var region = self;
        region.recovery_points = recovery_points;
        return region;
    }

    pub fn withSeverity(self: ErrorRegion, severity: ErrorSeverity) ErrorRegion {
        var region = self;
        region.severity = severity;
        return region;
    }
};

/// Type of parsing error
pub const ErrorKind = enum {
    /// Unexpected token
    unexpected_token,

    /// Missing expected token
    missing_token,

    /// Unmatched bracket
    unmatched_bracket,

    /// Invalid syntax
    invalid_syntax,

    /// Incomplete structure
    incomplete_structure,

    /// Unknown token
    unknown_token,

    /// Malformed expression
    malformed_expression,
};

/// Error severity level
pub const ErrorSeverity = enum {
    /// Fatal error that stops parsing
    fatal,

    /// Error that requires recovery
    err,

    /// Warning about suspicious code
    warning,

    /// Informational note
    info,
};

/// Bracket-based error recovery system
pub const ErrorRecovery = struct {
    /// Target language for recovery strategies
    language: Language,

    /// Allocator for temporary allocations
    allocator: std.mem.Allocator,

    /// Recovery statistics
    stats: RecoveryStats,

    /// Recovery options
    options: RecoveryOptions,

    pub fn init(allocator: std.mem.Allocator, language: Language) ErrorRecovery {
        return .{
            .language = language,
            .allocator = allocator,
            .stats = RecoveryStats{},
            .options = RecoveryOptions.default(),
        };
    }

    pub fn deinit(self: *ErrorRecovery) void {
        _ = self;
        // No cleanup needed
    }

    /// Find recovery points in token stream after an error
    pub fn findRecoveryPoints(
        self: *ErrorRecovery,
        tokens: []const Token,
        error_start: usize,
        context: RecoveryContext,
    ) ![]RecoveryPoint {
        const timer = std.time.nanoTimestamp();
        defer {
            const elapsed: u64 = @intCast(std.time.nanoTimestamp() - timer);
            self.stats.total_time_ns += elapsed;
            self.stats.recovery_attempts += 1;
        }

        var points = std.ArrayList(RecoveryPoint).init(self.allocator);
        errdefer points.deinit();

        if (error_start >= tokens.len) return points.toOwnedSlice();

        const start_depth = tokens[error_start].bracket_depth;

        // Try different recovery strategies
        try self.tryBracketSync(&points, tokens, error_start, start_depth, context);
        try self.tryKeywordSync(&points, tokens, error_start, context);
        try self.tryStatementSync(&points, tokens, error_start, context);
        try self.tryDelimiterSync(&points, tokens, error_start, context);

        // Sort by confidence (highest first)
        std.sort.pdq(RecoveryPoint, points.items, {}, compareRecoveryPoints);

        self.stats.recovery_points_found += points.items.len;

        return points.toOwnedSlice();
    }

    /// Create error region from failed parse attempt
    pub fn createErrorRegion(
        self: *ErrorRecovery,
        tokens: []const Token,
        start_idx: usize,
        end_idx: ?usize,
        error_kind: ErrorKind,
        context: RecoveryContext,
    ) !ErrorRegion {
        if (start_idx >= tokens.len) {
            return ErrorRegion.init(
                Span.empty(),
                start_idx,
                error_kind,
                "Error at end of input",
            );
        }

        const start_token = tokens[start_idx];
        var region = ErrorRegion.init(
            start_token.span,
            start_idx,
            error_kind,
            self.getErrorMessage(error_kind, context),
        );

        // Set end if provided
        if (end_idx) |end| {
            if (end < tokens.len) {
                const end_token = tokens[end];
                region = region.withEnd(end, end_token.span);
            }
        }

        // Find recovery points within the error region
        // TODO: Fix memory management for recovery points
        // For now, use empty slice to avoid memory leak
        // const recovery_points = try self.findRecoveryPoints(tokens, start_idx, context);
        region = region.withRecoveryPoints(&.{});

        // Set severity based on error kind
        const severity = switch (error_kind) {
            .unexpected_token, .missing_token => ErrorSeverity.err,
            .unmatched_bracket, .invalid_syntax => ErrorSeverity.err,
            .incomplete_structure => ErrorSeverity.warning,
            .unknown_token => ErrorSeverity.info,
            .malformed_expression => ErrorSeverity.err,
        };
        region = region.withSeverity(severity);

        self.stats.error_regions_created += 1;

        return region;
    }

    /// Check if recovery was successful
    pub fn validateRecovery(
        self: *ErrorRecovery,
        tokens: []const Token,
        recovery_point: RecoveryPoint,
    ) bool {
        if (recovery_point.token_idx >= tokens.len) return false;

        const token = tokens[recovery_point.token_idx];

        // Basic validation based on recovery strategy
        return switch (recovery_point.strategy) {
            .bracket_sync =>
            // Check that we're at a balanced bracket
            token.kind == .delimiter and self.isBalancingDelimiter(token.text),
            .keyword_sync =>
            // Check that we're at a keyword that can start a new structure
            token.kind == .keyword and self.isStructuralKeyword(token.text),
            .statement_sync =>
            // Check that we're at a position where a statement can start
            self.canStartStatement(token),
            .delimiter_sync =>
            // Check that we're at an appropriate delimiter
            token.kind == .delimiter,
            .line_sync =>
            // Line sync is always valid if we found a newline
            true,
            .depth_sync =>
            // Check that bracket depth makes sense
            token.bracket_depth <= recovery_point.bracket_depth + 1,
            .no_recovery => false,
        };
    }

    /// Get recovery statistics
    pub fn getStats(self: ErrorRecovery) RecoveryStats {
        return self.stats;
    }

    /// Reset statistics
    pub fn resetStats(self: *ErrorRecovery) void {
        self.stats = RecoveryStats{};
    }

    // ========================================================================
    // Private Implementation
    // ========================================================================

    /// Try bracket-based synchronization
    fn tryBracketSync(
        self: *ErrorRecovery,
        points: *std.ArrayList(RecoveryPoint),
        tokens: []const Token,
        start_idx: usize,
        start_depth: u16,
        context: RecoveryContext,
    ) !void {
        for (tokens[start_idx..], start_idx..) |token, idx| {
            if (token.kind == .delimiter) {
                // Look for closing brackets that could end the current structure
                if (self.isClosingBracket(token.text) and token.bracket_depth < start_depth) {
                    const point = RecoveryPoint.init(
                        token.span,
                        idx,
                        .bracket_sync,
                        0.8, // High confidence for bracket sync
                        token.bracket_depth,
                        context,
                    );
                    try points.append(point);
                }

                // Look for balanced brackets at same level
                if (token.bracket_depth == start_depth and self.isBalancingDelimiter(token.text)) {
                    const point = RecoveryPoint.init(
                        token.span,
                        idx,
                        .bracket_sync,
                        0.9, // Very high confidence
                        token.bracket_depth,
                        context,
                    );
                    try points.append(point);
                }
            }
        }
    }

    /// Try keyword-based synchronization
    fn tryKeywordSync(
        self: *ErrorRecovery,
        points: *std.ArrayList(RecoveryPoint),
        tokens: []const Token,
        start_idx: usize,
        context: RecoveryContext,
    ) !void {
        for (tokens[start_idx..], start_idx..) |token, idx| {
            if (token.kind == .keyword and self.isStructuralKeyword(token.text)) {
                const point = RecoveryPoint.init(
                    token.span,
                    idx,
                    .keyword_sync,
                    0.7, // Good confidence for keywords
                    token.bracket_depth,
                    context,
                );
                try points.append(point);
            }
        }
    }

    /// Try statement-based synchronization
    fn tryStatementSync(
        self: *ErrorRecovery,
        points: *std.ArrayList(RecoveryPoint),
        tokens: []const Token,
        start_idx: usize,
        context: RecoveryContext,
    ) !void {
        for (tokens[start_idx..], start_idx..) |token, idx| {
            if (self.canStartStatement(token)) {
                const point = RecoveryPoint.init(
                    token.span,
                    idx,
                    .statement_sync,
                    0.6, // Moderate confidence
                    token.bracket_depth,
                    context,
                );
                try points.append(point);
            }
        }
    }

    /// Try delimiter-based synchronization
    fn tryDelimiterSync(
        self: *ErrorRecovery,
        points: *std.ArrayList(RecoveryPoint),
        tokens: []const Token,
        start_idx: usize,
        context: RecoveryContext,
    ) !void {
        for (tokens[start_idx..], start_idx..) |token, idx| {
            if (token.kind == .delimiter and self.isSyncDelimiter(token.text)) {
                const point = RecoveryPoint.init(
                    token.span,
                    idx,
                    .delimiter_sync,
                    0.5, // Lower confidence
                    token.bracket_depth,
                    context,
                );
                try points.append(point);
            }
        }
    }

    /// Check if text is a closing bracket
    fn isClosingBracket(self: *ErrorRecovery, text: []const u8) bool {
        _ = self;
        return std.mem.eql(u8, text, "}") or
            std.mem.eql(u8, text, ")") or
            std.mem.eql(u8, text, "]");
    }

    /// Check if text is a balancing delimiter
    fn isBalancingDelimiter(self: *ErrorRecovery, text: []const u8) bool {
        return std.mem.eql(u8, text, ";") or
            std.mem.eql(u8, text, ",") or
            self.isClosingBracket(text);
    }

    /// Check if text is a structural keyword
    fn isStructuralKeyword(self: *ErrorRecovery, text: []const u8) bool {
        return switch (self.language) {
            .zig => std.mem.eql(u8, text, "fn") or
                std.mem.eql(u8, text, "struct") or
                std.mem.eql(u8, text, "enum") or
                std.mem.eql(u8, text, "pub") or
                std.mem.eql(u8, text, "const") or
                std.mem.eql(u8, text, "var"),
            .typescript => std.mem.eql(u8, text, "function") or
                std.mem.eql(u8, text, "class") or
                std.mem.eql(u8, text, "interface") or
                std.mem.eql(u8, text, "const") or
                std.mem.eql(u8, text, "let") or
                std.mem.eql(u8, text, "var"),
            else => false,
        };
    }

    /// Check if token can start a statement
    fn canStartStatement(self: *ErrorRecovery, token: Token) bool {
        return token.kind == .keyword or
            token.kind == .identifier or
            (token.kind == .delimiter and self.isOpeningBracket(token.text));
    }

    /// Check if text is an opening bracket
    fn isOpeningBracket(self: *ErrorRecovery, text: []const u8) bool {
        _ = self;
        return std.mem.eql(u8, text, "{") or
            std.mem.eql(u8, text, "(") or
            std.mem.eql(u8, text, "[");
    }

    /// Check if delimiter is suitable for synchronization
    fn isSyncDelimiter(self: *ErrorRecovery, text: []const u8) bool {
        _ = self;
        return std.mem.eql(u8, text, ";") or
            std.mem.eql(u8, text, ",") or
            std.mem.eql(u8, text, "}");
    }

    /// Get error message for error kind and context
    fn getErrorMessage(self: *ErrorRecovery, error_kind: ErrorKind, context: RecoveryContext) []const u8 {
        _ = self;
        _ = context;

        return switch (error_kind) {
            .unexpected_token => "Unexpected token",
            .missing_token => "Missing expected token",
            .unmatched_bracket => "Unmatched bracket",
            .invalid_syntax => "Invalid syntax",
            .incomplete_structure => "Incomplete structure",
            .unknown_token => "Unknown token",
            .malformed_expression => "Malformed expression",
        };
    }
};

/// Recovery options and configuration
pub const RecoveryOptions = struct {
    /// Maximum distance to search for recovery points
    max_search_distance: usize = 100,

    /// Maximum number of recovery points to generate
    max_recovery_points: usize = 10,

    /// Minimum confidence required for recovery point
    min_confidence: f32 = 0.3,

    /// Whether to prefer bracket-based recovery
    prefer_bracket_sync: bool = true,

    /// Whether to generate aggressive recovery points
    aggressive_recovery: bool = false,

    pub fn default() RecoveryOptions {
        return .{};
    }

    pub fn conservative() RecoveryOptions {
        return .{
            .max_search_distance = 50,
            .max_recovery_points = 5,
            .min_confidence = 0.6,
            .prefer_bracket_sync = true,
            .aggressive_recovery = false,
        };
    }

    pub fn aggressive() RecoveryOptions {
        return .{
            .max_search_distance = 200,
            .max_recovery_points = 20,
            .min_confidence = 0.2,
            .prefer_bracket_sync = false,
            .aggressive_recovery = true,
        };
    }
};

/// Recovery statistics for monitoring
pub const RecoveryStats = struct {
    /// Total recovery attempts
    recovery_attempts: usize = 0,

    /// Total recovery points found
    recovery_points_found: usize = 0,

    /// Total error regions created
    error_regions_created: usize = 0,

    /// Successful recoveries
    successful_recoveries: usize = 0,

    /// Total processing time (nanoseconds)
    total_time_ns: u64 = 0,

    /// Recovery points by strategy
    bracket_sync_points: usize = 0,
    keyword_sync_points: usize = 0,
    statement_sync_points: usize = 0,
    delimiter_sync_points: usize = 0,

    pub fn recoveryRate(self: RecoveryStats) f64 {
        if (self.recovery_attempts == 0) return 0.0;
        return @as(f64, @floatFromInt(self.successful_recoveries)) / @as(f64, @floatFromInt(self.recovery_attempts));
    }

    pub fn averageRecoveryTime(self: RecoveryStats) f64 {
        if (self.recovery_attempts == 0) return 0.0;
        return @as(f64, @floatFromInt(self.total_time_ns)) / @as(f64, @floatFromInt(self.recovery_attempts));
    }
};

/// Compare recovery points by confidence (highest first)
fn compareRecoveryPoints(_: void, a: RecoveryPoint, b: RecoveryPoint) bool {
    return a.confidence > b.confidence;
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "error recovery initialization" {
    var recovery = ErrorRecovery.init(testing.allocator, .zig);
    defer recovery.deinit();

    try testing.expectEqual(Language.zig, recovery.language);
    try testing.expectEqual(@as(usize, 0), recovery.stats.recovery_attempts);
}

test "bracket-based recovery" {
    var recovery = ErrorRecovery.init(testing.allocator, .zig);
    defer recovery.deinit();

    // Create tokens with unmatched bracket
    const tokens = [_]Token{
        Token.simple(Span.init(0, 2), .keyword, "fn", 0),
        Token.simple(Span.init(3, 7), .identifier, "test", 0),
        Token.simple(Span.init(7, 8), .delimiter, "(", 1),
        // Missing closing paren
        Token.simple(Span.init(10, 11), .delimiter, "{", 1),
        Token.simple(Span.init(20, 21), .delimiter, "}", 0), // Recovery point
    };

    const points = try recovery.findRecoveryPoints(&tokens, 2, .function_definition);
    defer testing.allocator.free(points);

    try testing.expect(points.len > 0);
    try testing.expectEqual(RecoveryStrategy.bracket_sync, points[0].strategy);
}

test "error region creation" {
    var recovery = ErrorRecovery.init(testing.allocator, .zig);
    defer recovery.deinit();

    const tokens = [_]Token{
        Token.simple(Span.init(0, 3), .keyword, "bad", 0),
    };

    const region = try recovery.createErrorRegion(
        &tokens,
        0,
        null,
        .unknown_token,
        .unknown,
    );

    try testing.expectEqual(ErrorKind.unknown_token, region.error_kind);
    try testing.expectEqual(ErrorSeverity.info, region.severity);
}
