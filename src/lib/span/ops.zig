const std = @import("std");
const Span = @import("span.zig").Span;

/// Compare two spans by start position (for sorting)
pub fn compareByStart(_: void, a: Span, b: Span) bool {
    if (a.start != b.start) return a.start < b.start;
    return a.end < b.end;
}

/// Compare two spans by end position
pub fn compareByEnd(_: void, a: Span, b: Span) bool {
    if (a.end != b.end) return a.end < b.end;
    return a.start < b.start;
}

/// Compare two spans by length
pub fn compareByLength(_: void, a: Span, b: Span) bool {
    const a_len = a.len();
    const b_len = b.len();
    if (a_len != b_len) return a_len < b_len;
    return a.start < b.start;
}

/// Check if spans are equal
pub inline fn equal(a: Span, b: Span) bool {
    return a.start == b.start and a.end == b.end;
}

/// Get the distance between two spans (0 if overlapping)
pub fn distance(a: Span, b: Span) u32 {
    if (a.overlaps(b)) return 0;
    if (a.end <= b.start) return b.start - a.end;
    return a.start - b.end;
}

/// Check if span a comes before span b (no overlap)
pub inline fn before(a: Span, b: Span) bool {
    return a.end <= b.start;
}

/// Check if span a comes after span b (no overlap)
pub inline fn after(a: Span, b: Span) bool {
    return a.start >= b.end;
}

/// Extend span to include a position
pub fn extend(span: Span, pos: u32) Span {
    return Span.init(
        @min(span.start, pos),
        @max(span.end, pos + 1),
    );
}

/// Shrink span by amount from both ends
pub fn shrink(span: Span, amount: u32) Span {
    const new_start = span.start + amount;
    const new_end = if (span.end > amount) span.end - amount else span.start;
    if (new_start >= new_end) return Span.empty();
    return Span.init(new_start, new_end);
}

/// Expand span by amount on both ends
pub fn expand(span: Span, amount: u32) Span {
    const new_start = if (span.start > amount) span.start - amount else 0;
    const new_end = span.end + amount;
    return Span.init(new_start, new_end);
}

/// Shift span by offset (positive or negative)
pub fn shift(span: Span, offset: i32) Span {
    if (offset >= 0) {
        const off = @as(u32, @intCast(offset));
        return Span.init(span.start + off, span.end + off);
    } else {
        const off = @as(u32, @intCast(-offset));
        const new_start = if (span.start > off) span.start - off else 0;
        const new_end = if (span.end > off) span.end - off else 0;
        return Span.init(new_start, new_end);
    }
}

/// Split span at position
pub fn split(span: Span, pos: u32) struct { left: Span, right: Span } {
    if (pos <= span.start) {
        return .{ .left = Span.empty(), .right = span };
    }
    if (pos >= span.end) {
        return .{ .left = span, .right = Span.empty() };
    }
    return .{
        .left = Span.init(span.start, pos),
        .right = Span.init(pos, span.end),
    };
}

/// Get relative position within span (0.0 to 1.0)
pub fn relativePosition(span: Span, pos: u32) f32 {
    if (span.isEmpty()) return 0.0;
    if (pos <= span.start) return 0.0;
    if (pos >= span.end) return 1.0;
    const offset = pos - span.start;
    const length = span.len();
    return @as(f32, @floatFromInt(offset)) / @as(f32, @floatFromInt(length));
}

/// Clamp position to span bounds
pub inline fn clamp(span: Span, pos: u32) u32 {
    if (pos < span.start) return span.start;
    if (pos > span.end) return span.end;
    return pos;
}

/// Get the center position of a span
pub inline fn center(span: Span) u32 {
    return span.start + (span.len() / 2);
}

// Tests
test "span operations" {
    const a = Span.init(10, 20);
    const b = Span.init(30, 40);

    try std.testing.expect(before(a, b));
    try std.testing.expect(after(b, a));
    try std.testing.expectEqual(@as(u32, 10), distance(a, b));

    const extended = extend(a, 25);
    try std.testing.expectEqual(Span.init(10, 26), extended);

    const expanded = expand(a, 5);
    try std.testing.expectEqual(Span.init(5, 25), expanded);

    const shifted = shift(a, 10);
    try std.testing.expectEqual(Span.init(20, 30), shifted);

    const parts = split(a, 15);
    try std.testing.expectEqual(Span.init(10, 15), parts.left);
    try std.testing.expectEqual(Span.init(15, 20), parts.right);
}

test "span comparisons" {
    const spans = [_]Span{
        Span.init(20, 30),
        Span.init(10, 15),
        Span.init(10, 20),
    };

    var sorted = spans;
    std.sort.insertion(Span, &sorted, {}, compareByStart);
    
    try std.testing.expectEqual(Span.init(10, 15), sorted[0]);
    try std.testing.expectEqual(Span.init(10, 20), sorted[1]);
    try std.testing.expectEqual(Span.init(20, 30), sorted[2]);
}