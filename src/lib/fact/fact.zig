const std = @import("std");
const PackedSpan = @import("../span/mod.zig").PackedSpan;
const Predicate = @import("predicate.zig").Predicate;
const Value = @import("value.zig").Value;

/// Unique identifier for facts in the system
pub const FactId = u32;

/// Generation counter for tracking fact stream updates
pub const Generation = u32;

/// Immutable fact about a span of text (exactly 24 bytes)
/// Facts form the universal data unit in the stream-first architecture
/// 
/// DESIGN CHOICE: We use `extern struct` for precise memory control:
/// - Regular structs may add padding for alignment
/// - Extern structs give us exact field placement
/// - Critical for achieving exactly 24 bytes (3 cache lines / 8-byte words)
/// - Enables efficient array storage and SIMD operations
///
/// FIELD ORDERING:
/// Fields are ordered by size (8, 8, 4, 2, 2) to minimize padding
/// This differs from logical order but ensures optimal packing
///
/// TYPE SAFETY:
/// The predicate field determines how to interpret the Value union
/// Helper constructors (withNumber, withSpan, etc.) ensure correct pairing
pub const Fact = extern struct {
    /// Text span this fact describes (8 bytes - packed)
    subject: PackedSpan,
    
    /// Additional value associated with this predicate (8 bytes)
    object: Value,
    
    /// Unique identifier for this fact (4 bytes)
    id: FactId,
    
    /// What kind of information this fact conveys (2 bytes)
    predicate: Predicate,
    
    /// Confidence level for this fact (2 bytes)
    confidence: f16,
    
    // Total: 8 + 8 + 4 + 2 + 2 = 24 bytes
    
    /// Create a new fact
    pub fn init(
        id: FactId,
        subject: PackedSpan,
        predicate: Predicate,
        object: Value,
        confidence: f16,
    ) Fact {
        return .{
            .id = id,
            .subject = subject,
            .predicate = predicate,
            .object = object,
            .confidence = confidence,
        };
    }
    
    /// Create a fact with full confidence (1.0)
    pub fn certain(
        id: FactId,
        subject: PackedSpan,
        predicate: Predicate,
        object: Value,
    ) Fact {
        return init(id, subject, predicate, object, 1.0);
    }
    
    /// Create a fact with no object value
    pub fn simple(
        id: FactId,
        subject: PackedSpan,
        predicate: Predicate,
    ) Fact {
        return init(id, subject, predicate, Value.fromNone(), 1.0);
    }
    
    /// Create a fact with a numeric object
    pub fn withNumber(
        id: FactId,
        subject: PackedSpan,
        predicate: Predicate,
        number: i64,
    ) Fact {
        return certain(id, subject, predicate, Value.fromNumber(number));
    }
    
    /// Create a fact with a span object
    pub fn withSpan(
        id: FactId,
        subject: PackedSpan,
        predicate: Predicate,
        span: PackedSpan,
    ) Fact {
        return certain(id, subject, predicate, Value.fromSpan(span));
    }
    
    /// Create a fact referencing another fact
    pub fn withFactRef(
        id: FactId,
        subject: PackedSpan,
        predicate: Predicate,
        fact_ref: FactId,
    ) Fact {
        return certain(id, subject, predicate, Value.fromFact(fact_ref));
    }
    
    /// Check if fact has high confidence (>= 0.8)
    pub inline fn isConfident(self: Fact) bool {
        return self.confidence >= 0.8;
    }
    
    /// Check if fact is certain (confidence == 1.0)
    pub inline fn isCertain(self: Fact) bool {
        return self.confidence == 1.0;
    }
    
    /// Check if fact is uncertain (confidence < 0.5)
    pub inline fn isUncertain(self: Fact) bool {
        return self.confidence < 0.5;
    }
    
    /// Format for debugging
    pub fn format(
        self: Fact,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("Fact#{d}[{s}@{:.2} => {}]", .{
            self.id,
            @tagName(self.predicate),
            self.confidence,
            self.object,
        });
    }
};

// Size assertion to ensure we hit our 24-byte target
comptime {
    std.debug.assert(@sizeOf(Fact) == 24);
    std.debug.assert(@sizeOf(FactId) == 4);
    std.debug.assert(@sizeOf(PackedSpan) == 8);
    std.debug.assert(@sizeOf(Predicate) == 2);
    std.debug.assert(@sizeOf(Value) == 8);
    std.debug.assert(@sizeOf(f16) == 2);
}