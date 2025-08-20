/// Span module - Efficient text position and range management
/// Provides 8-byte Span, PackedSpan optimization, and SpanSet collections
const std = @import("std");

// Core span type
pub const Span = @import("span.zig").Span;

// Packed span utilities
pub const PackedSpan = @import("packed.zig").PackedSpan;

// We need to provide conversion functions since packed.zig has its own Span type
const packed_mod = @import("packed.zig");

/// Pack a Span into a space-efficient PackedSpan
pub inline fn packSpan(span: Span) PackedSpan {
    // Convert our Span to packed.zig's internal Span
    const packed_span = packed_mod.Span.init(span.start, span.end);
    return packed_mod.packSpan(packed_span);
}

/// Unpack a PackedSpan back into a Span
pub inline fn unpackSpan(ps: PackedSpan) Span {
    // Convert packed.zig's Span back to our Span
    const packed_span = packed_mod.unpackSpan(ps);
    return Span.init(packed_span.start, packed_span.end);
}

// Span collections
pub const SpanSet = @import("set.zig").SpanSet;

// Span operations
pub const ops = @import("ops.zig");

// Size assertions
comptime {
    std.debug.assert(@sizeOf(Span) == 8);
    std.debug.assert(@sizeOf(PackedSpan) == 8);
}