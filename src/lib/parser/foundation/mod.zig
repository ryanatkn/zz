const std = @import("std");

/// Foundation Types for Stratified Parser Architecture
/// 
/// This module provides the core data structures and utilities needed for the
/// stratified parser system, including spans, facts, tokens, and mathematical
/// operations optimized for <1ms performance targets.

// ============================================================================
// Core Types - Fundamental data structures
// ============================================================================

/// Text position and range management
pub const Span = @import("types/span.zig").Span;

/// Immutable facts about text spans
pub const Fact = @import("types/fact.zig").Fact;
pub const FactId = @import("types/fact.zig").FactId;
pub const Generation = @import("types/fact.zig").Generation;
pub const Confidence = @import("types/fact.zig").Confidence;
pub const FactBuilder = @import("types/fact.zig").FactBuilder;
pub const FactSet = @import("types/fact.zig").FactSet;

/// Predicate types for categorizing facts
pub const Predicate = @import("types/predicate.zig").Predicate;
pub const PredicateCategory = @import("types/predicate.zig").PredicateCategory;
pub const Value = @import("types/predicate.zig").Value;

// Predicate-related enums
pub const TokenKind = @import("types/predicate.zig").TokenKind;
pub const BoundaryKind = @import("types/predicate.zig").BoundaryKind;
pub const NodeKind = @import("types/predicate.zig").NodeKind;
pub const HighlightKind = @import("types/predicate.zig").HighlightKind;
pub const DiagnosticKind = @import("types/predicate.zig").DiagnosticKind;
pub const LayerId = @import("types/predicate.zig").LayerId;

/// Enhanced token representation with bracket tracking
pub const Token = @import("types/token.zig").Token;
pub const TokenFlags = @import("types/token.zig").TokenFlags;
pub const DelimiterType = @import("types/token.zig").DelimiterType;
pub const TokenStream = @import("types/token.zig").TokenStream;

// ============================================================================
// Math Utilities - Coordinate systems and span operations
// ============================================================================

/// Line and column coordinate conversion
pub const Coordinates = @import("math/coordinates.zig").Coordinates;
pub const CoordinateConverter = @import("math/coordinates.zig").CoordinateConverter;

/// Advanced span manipulation operations
pub const SpanOps = @import("math/span_ops.zig").SpanOps;

// ============================================================================
// Collections - High-performance data structures for fact management
// ============================================================================

/// Fact indexing and storage systems
pub const collections = @import("collections/mod.zig");

// Export key collections for direct access
pub const FactIndex = collections.FactIndex;
pub const QueryCache = collections.QueryCache;
pub const Query = collections.Query;
pub const FactStorageSystem = collections.FactStorageSystem;
pub const FactPoolManager = collections.FactPoolManager;

// ============================================================================
// Convenience Functions - Common operations
// ============================================================================

/// Create a simple fact with high confidence
pub fn simpleFact(
    id: FactId,
    subject: Span,
    predicate: Predicate,
    generation: Generation,
) Fact {
    return Fact.simple(id, subject, predicate, generation);
}

/// Create a fact with a value
pub fn factWithValue(
    id: FactId,
    subject: Span,
    predicate: Predicate,
    value: Value,
    generation: Generation,
) Fact {
    return Fact.withValue(id, subject, predicate, value, generation);
}

/// Create a span from start and end positions
pub fn span(start: usize, end: usize) Span {
    return Span.init(start, end);
}

/// Create a point span at a single position
pub fn point(position: usize) Span {
    return Span.point(position);
}

/// Create coordinates from line and column
pub fn coordinates(line: usize, column: usize) Coordinates {
    return Coordinates.init(line, column);
}

/// Create a simple token
pub fn token(
    span_val: Span,
    kind: TokenKind,
    text: []const u8,
    bracket_depth: u16,
) Token {
    return Token.simple(span_val, kind, text, bracket_depth);
}

// ============================================================================
// Common Predicates - Frequently used predicate constructors
// ============================================================================

/// Create a token predicate
pub fn isToken(kind: TokenKind) Predicate {
    return Predicate{ .is_token = kind };
}

/// Create a text predicate
pub fn hasText(text: []const u8) Predicate {
    return Predicate{ .has_text = text };
}

/// Create a boundary predicate
pub fn isBoundary(kind: BoundaryKind) Predicate {
    return Predicate{ .is_boundary = kind };
}

/// Create a node predicate
pub fn isNode(kind: NodeKind) Predicate {
    return Predicate{ .is_node = kind };
}

/// Create a highlight predicate
pub fn highlightAs(kind: HighlightKind) Predicate {
    return Predicate{ .highlight_color = kind };
}

// ============================================================================
// Test Support - Functions for testing and validation
// ============================================================================

/// Initialize foundation types for testing
pub fn initTesting(allocator: std.mem.Allocator) void {
    _ = allocator;
    // Reserved for future testing infrastructure
}

/// Validate a fact stream for consistency
pub fn validateFactStream(facts: []const Fact) bool {
    // Check that fact IDs are unique
    var seen_ids = std.HashMap(FactId, void, std.hash_map.AutoContext(FactId), std.hash_map.default_max_load_percentage).init(std.testing.allocator);
    defer seen_ids.deinit();
    
    for (facts) |fact| {
        if (seen_ids.contains(fact.id)) {
            return false; // Duplicate ID
        }
        seen_ids.put(fact.id, {}) catch return false;
    }
    
    return true;
}

// ============================================================================
// Performance Monitoring - Utilities for tracking performance
// ============================================================================

/// Performance timer for measuring operation latency
pub const PerfTimer = struct {
    start_time: i128,
    
    pub fn start() PerfTimer {
        return .{
            .start_time = std.time.nanoTimestamp(),
        };
    }
    
    pub fn elapsed(self: PerfTimer) u64 {
        const end_time = std.time.nanoTimestamp();
        return @intCast(end_time - self.start_time);
    }
    
    pub fn elapsedMs(self: PerfTimer) f64 {
        const ns = self.elapsed();
        return @as(f64, @floatFromInt(ns)) / 1_000_000.0;
    }
    
    pub fn elapsedUs(self: PerfTimer) f64 {
        const ns = self.elapsed();
        return @as(f64, @floatFromInt(ns)) / 1_000.0;
    }
};

// ============================================================================
// Module Tests - Ensure all components work together
// ============================================================================

test "foundation types integration" {
    const testing = std.testing;
    
    // Create a span
    const text_span = span(10, 20);
    try testing.expectEqual(@as(usize, 10), text_span.len());
    
    // Create a fact about the span
    const fact = simpleFact(1, text_span, isToken(.identifier), 0);
    try testing.expectEqual(@as(FactId, 1), fact.id);
    try testing.expect(fact.subject.eql(text_span));
    
    // Create a token for the span
    const tok = token(text_span, .identifier, "hello", 0);
    try testing.expectEqualStrings("hello", tok.text);
    try testing.expect(tok.isKind(.identifier));
}

test "coordinate conversion integration" {
    const testing = std.testing;
    
    const input = "hello\nworld";
    var converter = try CoordinateConverter.init(testing.allocator, input);
    defer converter.deinit();
    
    // Test round trip
    const pos = 7; // 'o' in "world"
    const coords = converter.positionToCoordinates(pos);
    const round_trip = converter.coordinatesToPosition(coords);
    
    try testing.expectEqual(@as(?usize, pos), round_trip);
}

test "span operations integration" {
    const testing = std.testing;
    
    const spans = [_]Span{
        span(10, 20),
        span(15, 25),
        span(30, 40),
    };
    
    // Test union
    const union_span = SpanOps.unionOf(&spans);
    try testing.expectEqual(@as(usize, 10), union_span.start);
    try testing.expectEqual(@as(usize, 40), union_span.end);
    
    // Test merging overlapping spans
    const merged = try SpanOps.mergeOverlapping(&spans, testing.allocator);
    defer testing.allocator.free(merged);
    
    try testing.expectEqual(@as(usize, 2), merged.len);
    try testing.expect(merged[0].eql(span(10, 25)));
    try testing.expect(merged[1].eql(span(30, 40)));
}

test "performance timer" {
    const timer = PerfTimer.start();
    
    // Simulate some work
    var sum: u64 = 0;
    for (0..1000) |i| {
        sum += i;
    }
    
    const elapsed_ns = timer.elapsed();
    const elapsed_us = timer.elapsedUs();
    
    // Should complete very quickly
    try std.testing.expect(elapsed_ns > 0);
    try std.testing.expect(elapsed_us >= 0);
    
    // Prevent optimization
    std.testing.expect(sum > 0) catch {};
}