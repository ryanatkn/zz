const std = @import("std");

/// Structural Parser - Layer 1 of Stratified Parser Architecture
///
/// This module provides block boundary detection with <1ms latency,
/// error recovery regions, and structural fact generation for Layer 2.
///
/// Performance targets:
/// - Block boundary detection: <1ms for 1000 lines
/// - Single boundary update: <100μs
/// - Error recovery: <10ms worst case
/// - Memory usage: <1.5x input size

// ============================================================================
// Core Components
// ============================================================================

/// High-performance structural parser with boundary detection
pub const StructuralParser = @import("parser.zig").StructuralParser;

/// Efficient parsing state machine with O(1) transitions
pub const StateMachine = @import("state_machine.zig").StateMachine;
pub const ParseState = @import("state_machine.zig").ParseState;

/// Block boundary detection algorithms
pub const BoundaryDetector = @import("boundaries.zig").BoundaryDetector;
pub const BoundaryHint = @import("boundaries.zig").BoundaryHint;

/// Error recovery with bracket synchronization
pub const ErrorRecovery = @import("recovery.zig").ErrorRecovery;
pub const RecoveryPoint = @import("recovery.zig").RecoveryPoint;
pub const ErrorRegion = @import("recovery.zig").ErrorRegion;

/// Language-specific pattern matchers
pub const LanguageMatchers = @import("matchers.zig").LanguageMatchers;
pub const ZigMatcher = @import("matchers.zig").ZigMatcher;

// ============================================================================
// Data Types
// ============================================================================

/// Import foundation types
pub const Span = @import("../foundation/types/span.zig").Span;
pub const Fact = @import("../foundation/types/fact.zig").Fact;
pub const FactId = @import("../foundation/types/fact.zig").FactId;
pub const Generation = @import("../foundation/types/fact.zig").Generation;
pub const Predicate = @import("../foundation/types/predicate.zig").Predicate;
pub const BoundaryKind = @import("../foundation/types/predicate.zig").BoundaryKind;

/// Import lexical types
pub const Token = @import("../lexical/mod.zig").Token;
pub const TokenKind = @import("../lexical/mod.zig").TokenKind;
pub const TokenDelta = @import("../lexical/mod.zig").TokenDelta;
pub const Language = @import("../lexical/mod.zig").Language;

/// Structural delta representing boundary changes
pub const StructuralDelta = struct {
    /// Fact IDs that were removed
    removed_facts: []FactId,

    /// New structural facts that were added
    added_facts: []Fact,

    /// Total range affected by the change
    affected_range: Span,

    /// Generation this delta applies to
    generation: Generation,

    pub fn init(allocator: std.mem.Allocator) StructuralDelta {
        _ = allocator;
        return .{
            .removed_facts = &.{},
            .added_facts = &.{},
            .affected_range = Span.empty(),
            .generation = 0,
        };
    }

    pub fn deinit(self: *StructuralDelta, allocator: std.mem.Allocator) void {
        allocator.free(self.removed_facts);
        allocator.free(self.added_facts);
    }
};

/// Parse boundary information for Layer 2
pub const ParseBoundary = struct {
    /// Span of the boundary
    span: Span,

    /// Type of boundary (function, class, block, etc.)
    kind: BoundaryKind,

    /// Confidence level for this boundary (0.0 to 1.0)
    confidence: f32,

    /// Bracket depth at boundary start
    depth: u16,

    /// Whether this boundary has errors
    has_errors: bool,

    /// Error recovery points within this boundary
    recovery_points: []RecoveryPoint,

    pub fn init(span: Span, kind: BoundaryKind, depth: u16) ParseBoundary {
        return .{
            .span = span,
            .kind = kind,
            .confidence = 1.0,
            .depth = depth,
            .has_errors = false,
            .recovery_points = &.{},
        };
    }

    pub fn withErrors(self: ParseBoundary, recovery_points: []RecoveryPoint) ParseBoundary {
        var boundary = self;
        boundary.has_errors = true;
        boundary.recovery_points = recovery_points;
        return boundary;
    }

    pub fn withConfidence(self: ParseBoundary, confidence: f32) ParseBoundary {
        var boundary = self;
        boundary.confidence = confidence;
        return boundary;
    }
};

/// Result of structural parsing
pub const StructuralResult = struct {
    /// Detected boundaries for Layer 2
    boundaries: []ParseBoundary,

    /// Generated facts for indexing
    facts: []Fact,

    /// Error regions detected
    error_regions: []ErrorRegion,

    /// Total processing time in nanoseconds
    processing_time_ns: u64,

    /// Success flag
    success: bool,

    pub fn deinit(self: *StructuralResult, allocator: std.mem.Allocator) void {
        allocator.free(self.boundaries);
        allocator.free(self.facts);
        allocator.free(self.error_regions);
    }
};

// ============================================================================
// Configuration
// ============================================================================

/// Configuration for structural parsing
pub const StructuralConfig = struct {
    /// Target language for parsing
    language: Language,

    /// Whether to detect error regions
    detect_errors: bool = true,

    /// Whether to generate recovery points
    generate_recovery: bool = true,

    /// Maximum boundary nesting depth
    max_depth: u16 = 64,

    /// Performance threshold - adjusted for debug vs release builds
    performance_threshold_ns: u64 = if (std.debug.runtime_safety) 5_000_000 else 1_000_000, // 5ms debug, 1ms release

    /// Whether to include folding boundaries
    include_folding: bool = true,

    /// Whether to track indentation levels
    track_indentation: bool = true,

    pub fn forLanguage(language: Language) StructuralConfig {
        return .{
            .language = language,
        };
    }

    pub fn withErrorRecovery(self: StructuralConfig) StructuralConfig {
        var config = self;
        config.detect_errors = true;
        config.generate_recovery = true;
        return config;
    }

    pub fn withoutErrorRecovery(self: StructuralConfig) StructuralConfig {
        var config = self;
        config.detect_errors = false;
        config.generate_recovery = false;
        return config;
    }
};

// ============================================================================
// Performance Utilities
// ============================================================================

/// Timer for measuring structural parsing performance
pub const StructuralTimer = struct {
    start_time: i128,

    pub fn start() StructuralTimer {
        return .{
            .start_time = std.time.nanoTimestamp(),
        };
    }

    pub fn elapsedNs(self: StructuralTimer) u64 {
        const end_time = std.time.nanoTimestamp();
        return @intCast(end_time - self.start_time);
    }

    pub fn elapsedMs(self: StructuralTimer) f64 {
        const ns = self.elapsedNs();
        return @as(f64, @floatFromInt(ns)) / 1_000_000.0;
    }

    pub fn checkTarget(self: StructuralTimer, threshold_ns: u64) bool {
        return self.elapsedNs() < threshold_ns;
    }

    pub fn checkMsTarget(self: StructuralTimer) bool {
        return self.elapsedMs() < 1.0; // <1ms target
    }
};

/// Structural parsing statistics
pub const StructuralStats = struct {
    /// Total boundaries detected
    boundaries_detected: usize = 0,

    /// Total facts generated
    facts_generated: usize = 0,

    /// Total error regions found
    error_regions_found: usize = 0,

    /// Total tokens processed
    tokens_processed: usize = 0,

    /// Total processing time (nanoseconds)
    total_time_ns: u64 = 0,

    /// Number of incremental updates
    incremental_updates: usize = 0,

    /// Peak memory usage
    peak_memory: usize = 0,

    /// Parse success rate
    successful_parses: usize = 0,
    total_parses: usize = 0,

    pub fn reset(self: *StructuralStats) void {
        self.* = StructuralStats{};
    }

    pub fn boundariesPerSecond(self: StructuralStats) f64 {
        if (self.total_time_ns == 0) return 0.0;
        const seconds = @as(f64, @floatFromInt(self.total_time_ns)) / 1_000_000_000.0;
        return @as(f64, @floatFromInt(self.boundaries_detected)) / seconds;
    }

    pub fn tokensPerSecond(self: StructuralStats) f64 {
        if (self.total_time_ns == 0) return 0.0;
        const seconds = @as(f64, @floatFromInt(self.total_time_ns)) / 1_000_000_000.0;
        return @as(f64, @floatFromInt(self.tokens_processed)) / seconds;
    }

    pub fn successRate(self: StructuralStats) f64 {
        if (self.total_parses == 0) return 0.0;
        return @as(f64, @floatFromInt(self.successful_parses)) / @as(f64, @floatFromInt(self.total_parses));
    }

    pub fn averageProcessingTime(self: StructuralStats) f64 {
        if (self.total_parses == 0) return 0.0;
        return @as(f64, @floatFromInt(self.total_time_ns)) / @as(f64, @floatFromInt(self.total_parses));
    }
};

// ============================================================================
// Convenience Functions
// ============================================================================

/// Create a structural parser for a specific language
pub fn createParser(allocator: std.mem.Allocator, language: Language) !StructuralParser {
    const config = StructuralConfig.forLanguage(language);
    return StructuralParser.init(allocator, config);
}

/// Parse token stream to detect boundaries
pub fn parseTokens(allocator: std.mem.Allocator, tokens: []const Token, language: Language) !StructuralResult {
    var parser = try createParser(allocator, language);
    defer parser.deinit();

    return parser.parse(tokens);
}

/// Check if a token indicates a potential boundary start
pub fn isBoundaryToken(token: Token, language: Language) bool {
    return switch (language) {
        .zig => ZigMatcher.isBoundaryStart(token),
        else => false, // Generic fallback
    };
}

/// Get confidence level for a boundary detection
pub fn getBoundaryConfidence(tokens: []const Token, start_idx: usize, kind: BoundaryKind, language: Language) f32 {
    return switch (language) {
        .zig => ZigMatcher.getBoundaryConfidence(tokens, start_idx, kind),
        else => 0.5, // Default confidence
    };
}

// ============================================================================
// Tests
// ============================================================================

test "structural module exports" {
    const testing = std.testing;

    // Test that all main types are accessible
    const config = StructuralConfig.forLanguage(.zig);
    try testing.expectEqual(Language.zig, config.language);

    const stats = StructuralStats{};
    try testing.expectEqual(@as(usize, 0), stats.boundaries_detected);

    const timer = StructuralTimer.start();
    try testing.expect(timer.start_time > 0);
}

test "boundary detection helpers" {
    const testing = std.testing;

    const span = Span.init(0, 10);
    const boundary = ParseBoundary.init(span, .function, 0);

    try testing.expectEqual(BoundaryKind.function, boundary.kind);
    try testing.expectEqual(@as(f32, 1.0), boundary.confidence);
    try testing.expect(!boundary.has_errors);
}

test "structural delta operations" {
    const testing = std.testing;

    var delta = StructuralDelta.init(testing.allocator);
    defer delta.deinit(testing.allocator);

    try testing.expectEqual(@as(usize, 0), delta.removed_facts.len);
    try testing.expectEqual(@as(usize, 0), delta.added_facts.len);
}
