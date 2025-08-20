const std = @import("std");
const testing = std.testing;

const span_mod = @import("mod.zig");
const Span = span_mod.Span;
const PackedSpan = span_mod.PackedSpan;
const packSpan = span_mod.packSpan;
const unpackSpan = span_mod.unpackSpan;
const SpanSet = span_mod.SpanSet;
const ops = span_mod.ops;

const packed_mod = @import("packed.zig");
const set = @import("set.zig");

test "Span creation and basic operations" {
    const s1 = Span.init(10, 20);
    try testing.expectEqual(@as(u32, 10), s1.start);
    try testing.expectEqual(@as(u32, 20), s1.end);
    try testing.expectEqual(@as(u32, 10), s1.len());
    try testing.expect(!s1.isEmpty());

    const s2 = Span.point(15);
    try testing.expectEqual(@as(u32, 15), s2.start);
    try testing.expectEqual(@as(u32, 15), s2.end);
    try testing.expectEqual(@as(u32, 0), s2.len());
    try testing.expect(s2.isEmpty());

    const s3 = Span.empty();
    try testing.expect(s3.isEmpty());
    try testing.expectEqual(@as(u32, 0), s3.len());
}

test "Span containment" {
    const s = Span.init(10, 20);

    try testing.expect(s.contains(10));
    try testing.expect(s.contains(15));
    try testing.expect(s.contains(19));
    try testing.expect(!s.contains(9));
    try testing.expect(!s.contains(20));
    try testing.expect(!s.contains(21));

    const s2 = Span.init(12, 18);
    try testing.expect(s.containsSpan(s2));
    try testing.expect(!s2.containsSpan(s));
}

test "Span overlap and intersection" {
    const s1 = Span.init(10, 20);
    const s2 = Span.init(15, 25);
    const s3 = Span.init(25, 30);

    try testing.expect(s1.overlaps(s2));
    try testing.expect(s2.overlaps(s1));
    try testing.expect(!s1.overlaps(s3));

    const intersection = s1.intersect(s2);
    try testing.expect(intersection != null);
    try testing.expectEqual(Span.init(15, 20), intersection.?);

    const no_intersection = s1.intersect(s3);
    try testing.expect(no_intersection == null);
}

test "Span merge" {
    const s1 = Span.init(10, 20);
    const s2 = Span.init(15, 25);
    const merged = s1.merge(s2);

    try testing.expectEqual(Span.init(10, 25), merged);

    // Non-overlapping merge
    const s3 = Span.init(30, 40);
    const merged2 = s1.merge(s3);
    try testing.expectEqual(Span.init(10, 40), merged2);
}

test "Span slice" {
    const text = "Hello, World!";
    const s = Span.init(7, 12);
    const slice = s.slice(text);
    try testing.expectEqualStrings("World", slice);

    // Out of bounds handling
    const s2 = Span.init(10, 100);
    const slice2 = s2.slice(text);
    try testing.expectEqualStrings("ld!", slice2);
}

test "PackedSpan round-trip" {
    const test_spans = [_]Span{
        Span.init(0, 0),
        Span.init(0, 100),
        Span.init(1000, 2000),
        Span.init(std.math.maxInt(u32) - 100, std.math.maxInt(u32)),
        Span.point(42),
        Span.empty(),
    };

    for (test_spans) |s| {
        const p = packSpan(s);
        const unpacked = unpackSpan(p);
        try testing.expectEqual(s.start, unpacked.start);
        try testing.expectEqual(s.end, unpacked.end);
        try testing.expectEqual(s.len(), unpacked.len());
    }
}

test "PackedSpan operations" {
    const s = Span.init(100, 200);
    const p = packSpan(s);

    try testing.expectEqual(@as(u32, 100), packed_mod.getStart(p));
    try testing.expectEqual(@as(u32, 100), packed_mod.getLength(p));
    try testing.expectEqual(@as(u32, 200), packed_mod.getEnd(p));

    try testing.expect(packed_mod.contains(p, 150));
    try testing.expect(!packed_mod.contains(p, 50));
    try testing.expect(!packed_mod.contains(p, 250));

    const s2 = Span.init(150, 250);
    const p2 = packSpan(s2);
    try testing.expect(packed_mod.overlaps(p, p2));

    const s3 = Span.init(300, 400);
    const p3 = packSpan(s3);
    try testing.expect(!packed_mod.overlaps(p, p3));
}

test "SpanSet basic operations" {
    var spans = SpanSet.init(testing.allocator);
    defer spans.deinit();

    try spans.add(Span.init(10, 20));
    try spans.add(Span.init(30, 40));
    try spans.add(Span.init(50, 60));

    try testing.expectEqual(@as(usize, 3), spans.count());
    try testing.expect(!spans.isEmpty());

    try testing.expect(spans.contains(15));
    try testing.expect(!spans.contains(25));
    try testing.expect(spans.contains(35));

    spans.clear();
    try testing.expect(spans.isEmpty());
}

test "SpanSet normalization" {
    var spans = SpanSet.init(testing.allocator);
    defer spans.deinit();

    // Add overlapping spans
    try spans.add(Span.init(0, 10));
    try spans.add(Span.init(5, 15));
    try spans.add(Span.init(8, 12));
    try spans.add(Span.init(20, 30));
    try spans.add(Span.init(25, 35));
    try spans.add(Span.init(40, 50));

    const normalized = spans.getNormalized();
    try testing.expectEqual(@as(usize, 3), normalized.len);
    try testing.expectEqual(Span.init(0, 15), normalized[0]);
    try testing.expectEqual(Span.init(20, 35), normalized[1]);
    try testing.expectEqual(Span.init(40, 50), normalized[2]);

    try testing.expectEqual(@as(u32, 40), spans.getTotalCoverage());
}

test "SpanSet union" {
    var spans = SpanSet.init(testing.allocator);
    defer spans.deinit();

    try spans.add(Span.init(10, 20));
    try spans.add(Span.init(30, 40));
    try spans.add(Span.init(50, 60));

    const union_span = spans.getUnion();
    try testing.expect(union_span != null);
    try testing.expectEqual(Span.init(10, 60), union_span.?);
}

test "Span operations" {
    const s = Span.init(20, 30);

    // Distance
    const before_span = Span.init(5, 10);
    const after_span = Span.init(40, 50);
    try testing.expectEqual(@as(u32, 10), ops.distance(before_span, s));
    try testing.expectEqual(@as(u32, 10), ops.distance(s, after_span));
    try testing.expectEqual(@as(u32, 0), ops.distance(s, Span.init(25, 35)));

    // Before/After
    try testing.expect(ops.before(before_span, s));
    try testing.expect(ops.after(after_span, s));
    try testing.expect(!ops.before(s, before_span));

    // Extend
    const extended = ops.extend(s, 35);
    try testing.expectEqual(Span.init(20, 36), extended);

    // Expand/Shrink
    const expanded = ops.expand(s, 5);
    try testing.expectEqual(Span.init(15, 35), expanded);
    const shrunk = ops.shrink(s, 3);
    try testing.expectEqual(Span.init(23, 27), shrunk);

    // Shift
    const shifted_right = ops.shift(s, 10);
    try testing.expectEqual(Span.init(30, 40), shifted_right);
    const shifted_left = ops.shift(s, -5);
    try testing.expectEqual(Span.init(15, 25), shifted_left);

    // Split
    const parts = ops.split(s, 25);
    try testing.expectEqual(Span.init(20, 25), parts.left);
    try testing.expectEqual(Span.init(25, 30), parts.right);

    // Center
    try testing.expectEqual(@as(u32, 25), ops.center(s));

    // Clamp
    try testing.expectEqual(@as(u32, 20), ops.clamp(s, 10));
    try testing.expectEqual(@as(u32, 30), ops.clamp(s, 40));
    try testing.expectEqual(@as(u32, 25), ops.clamp(s, 25));
}

test "Span size assertions" {
    try testing.expectEqual(@as(usize, 8), @sizeOf(Span));
    try testing.expectEqual(@as(usize, 8), @sizeOf(PackedSpan));
}

test "Span formatting" {
    const s = Span.init(10, 20);
    const output = try std.fmt.allocPrint(testing.allocator, "{}", .{s});
    defer testing.allocator.free(output);
    try testing.expectEqualStrings("[10..20]", output);
}