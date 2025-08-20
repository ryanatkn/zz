const std = @import("std");

/// Simple span type for packing (avoid circular import)
pub const Span = struct {
    start: u32,
    end: u32,

    pub fn init(start: u32, end: u32) Span {
        return .{ .start = start, .end = end };
    }

    pub fn len(self: Span) u32 {
        if (self.end < self.start) return 0;
        return self.end - self.start;
    }
};

/// Space-efficient span encoding: 32-bit start + 32-bit length
/// Saves 8 bytes compared to storing start and end separately
/// Critical for the 24-byte Fact struct target
pub const PackedSpan = u64;

/// Pack a span into 64 bits (32-bit start + 32-bit length)
pub inline fn packSpan(span: Span) PackedSpan {
    const length = span.len();
    return (@as(u64, span.start) << 32) | @as(u64, length);
}

/// Unpack a 64-bit value back into a Span
pub inline fn unpackSpan(ps: PackedSpan) Span {
    const start = @as(u32, @intCast(ps >> 32));
    const length = @as(u32, @intCast(ps & 0xFFFFFFFF));
    return Span.init(start, start + length);
}

/// Get just the start position from a packed span
pub inline fn getStart(ps: PackedSpan) u32 {
    return @as(u32, @intCast(ps >> 32));
}

/// Get just the length from a packed span
pub inline fn getLength(ps: PackedSpan) u32 {
    return @as(u32, @intCast(ps & 0xFFFFFFFF));
}

/// Get the end position from a packed span
pub inline fn getEnd(ps: PackedSpan) u32 {
    return getStart(ps) + getLength(ps);
}

/// Check if packed span is empty
pub inline fn isEmpty(ps: PackedSpan) bool {
    return getLength(ps) == 0;
}

/// Check if packed span contains a position
pub inline fn contains(ps: PackedSpan, pos: u32) bool {
    const start = getStart(ps);
    const length = getLength(ps);
    return pos >= start and pos < (start + length);
}

/// Check if two packed spans overlap
pub inline fn overlaps(a: PackedSpan, b: PackedSpan) bool {
    const a_start = getStart(a);
    const a_end = a_start + getLength(a);
    const b_start = getStart(b);
    const b_end = b_start + getLength(b);
    return a_start < b_end and b_start < a_end;
}

/// Create an empty packed span
pub inline fn empty() PackedSpan {
    return 0;
}

/// Create a packed span at a point
pub inline fn point(pos: u32) PackedSpan {
    return @as(u64, pos) << 32;
}

/// Format packed span for debugging
pub fn format(
    ps: PackedSpan,
    comptime fmt: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    _ = fmt;
    _ = options;
    const start = getStart(ps);
    const length = getLength(ps);
    try writer.print("PackedSpan[{d}+{d}]", .{ start, length });
}

// Tests to verify packing/unpacking correctness
test "PackedSpan round-trip" {
    const spans = [_]Span{
        Span.init(0, 0),
        Span.init(0, 100),
        Span.init(1000, 2000),
        Span.init(std.math.maxInt(u32) - 100, std.math.maxInt(u32)),
    };

    for (spans) |span| {
        const ps = packSpan(span);
        const unpacked = unpackSpan(ps);
        try std.testing.expectEqual(span.start, unpacked.start);
        try std.testing.expectEqual(span.end, unpacked.end);
    }
}

test "PackedSpan operations" {
    const span = Span.init(100, 200);
    const ps = packSpan(span);

    try std.testing.expectEqual(@as(u32, 100), getStart(ps));
    try std.testing.expectEqual(@as(u32, 100), getLength(ps));
    try std.testing.expectEqual(@as(u32, 200), getEnd(ps));

    try std.testing.expect(contains(ps, 150));
    try std.testing.expect(!contains(ps, 50));
    try std.testing.expect(!contains(ps, 250));
}

test "PackedSpan size" {
    try std.testing.expectEqual(@as(usize, 8), @sizeOf(PackedSpan));
}
