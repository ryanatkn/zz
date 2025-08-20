const std = @import("std");
const FactId = @import("fact.zig").FactId;
const PackedSpan = @import("../span/mod.zig").PackedSpan;

/// Atom ID for interned strings
pub const AtomId = u32;

/// Value that fits exactly in 8 bytes
///
/// DESIGN CHOICE: We use `extern union` instead of `union(enum)` for performance:
/// - Tagged unions in Zig store both tag AND data, making them 16+ bytes
/// - Extern unions are exactly 8 bytes with no tag overhead
/// - This is critical for our 24-byte Fact struct target
///
/// TYPE SAFETY STRATEGY:
/// Since extern unions don't track the active field, we ensure type safety through:
/// 1. The Predicate enum acts as external type discriminator
/// 2. Each predicate implies what Value type to expect
/// 3. Helper functions (getAtom, getFactRef) safely extract typed values
/// 4. Builder pattern ensures correct predicate-value pairing
///
/// FUTURE IMPROVEMENTS (TODO):
/// - Add comptime validation that predicate matches value type
/// - Create typed wrapper functions that enforce predicate-value contracts
/// - Add debug mode with runtime type checking via predicate
/// - Consider using a separate ValueKind enum stored in unused bits
///
/// PREDICATE-VALUE TYPE MAPPING:
/// Common patterns for which Value type to use with which Predicate:
/// - has_value, has_error → number (error codes, counts)
/// - has_parent, has_child, follows, precedes → fact ref (via getFactRef)
/// - defines_symbol, references_symbol → atom (symbol ID via getAtom)
/// - indent_level → uint (indentation count)
/// - has_text → atom (interned string ID)
/// - is_* predicates → often none or boolean
///
/// MEMORY LAYOUT:
/// All fields overlap in the same 8 bytes of memory
/// Interpretation depends on context (usually the associated Predicate)
pub const Value = extern union {
    /// No value (interpreted as 0)
    none: u64,

    /// Numeric value (8 bytes)
    number: i64,

    /// Unsigned integer (8 bytes)
    uint: u64,

    /// Span reference (8 bytes via PackedSpan)
    span: PackedSpan,

    /// Two 32-bit values (atom ID, fact ID, or other)
    pair: extern struct {
        a: u32,
        b: u32,
    },

    /// Float value (8 bytes)
    float: f64,

    /// Bytes for any 8-byte data
    bytes: [8]u8,

    /// Create a none value
    pub fn fromNone() Value {
        return .{ .none = 0 };
    }

    /// Create a number value
    pub fn fromNumber(n: i64) Value {
        return .{ .number = n };
    }

    /// Create a span value
    pub fn fromSpan(s: PackedSpan) Value {
        return .{ .span = s };
    }

    /// Create an atom value (stored in pair.a)
    pub fn fromAtom(a: AtomId) Value {
        return .{ .pair = .{ .a = a, .b = 0 } };
    }

    /// Create a fact reference value (stored in pair.b)
    pub fn fromFact(f: FactId) Value {
        return .{ .pair = .{ .a = 0, .b = f } };
    }

    /// Create an unsigned value
    pub fn fromUint(u: u64) Value {
        return .{ .uint = u };
    }

    /// Create a float value
    pub fn fromFloat(f: f64) Value {
        return .{ .float = f };
    }

    /// Create a boolean value (stored as 0 or 1 in uint)
    pub fn fromBool(b: bool) Value {
        return .{ .uint = if (b) 1 else 0 };
    }

    /// Check if value is none (all zeros)
    pub inline fn isNone(self: Value) bool {
        return self.none == 0;
    }

    /// Get atom ID if this is an atom value
    pub inline fn getAtom(self: Value) ?AtomId {
        if (self.pair.b == 0 and self.pair.a != 0) {
            return self.pair.a;
        }
        return null;
    }

    /// Get fact ID if this is a fact reference
    pub inline fn getFactRef(self: Value) ?FactId {
        if (self.pair.a == 0 and self.pair.b != 0) {
            return self.pair.b;
        }
        return null;
    }

    /// Get boolean value
    pub inline fn getBool(self: Value) bool {
        return self.uint != 0;
    }

    /// Format for debugging (simplified without tag info)
    pub fn format(
        self: Value,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        // We can't know the type without external context
        // Just print as hex for debugging
        try writer.print("Value(0x{x:0>16})", .{self.uint});
    }
};

// Size assertion - Value must be exactly 8 bytes
comptime {
    std.debug.assert(@sizeOf(Value) == 8);
}
