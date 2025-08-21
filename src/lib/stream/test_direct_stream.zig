/// Tests for DirectStream - Phase 5 migration validation
const std = @import("std");
const testing = std.testing;

const DirectStream = @import("mod.zig").DirectStream;
const directFromSlice = @import("mod.zig").directFromSlice;
const Stream = @import("mod.zig").Stream;
const fromSlice = @import("mod.zig").fromSlice;

test "DirectStream basic iteration" {
    const data = [_]u32{ 1, 2, 3, 4, 5 };
    var stream = directFromSlice(u32, &data);

    var sum: u32 = 0;
    while (try stream.next()) |val| {
        sum += val;
    }

    try testing.expectEqual(@as(u32, 15), sum);
}

test "DirectStream vs Stream behavior equivalence" {
    const data = [_]u32{ 10, 20, 30, 40, 50 };

    // Test DirectStream
    var direct = directFromSlice(u32, &data);
    var direct_results = std.ArrayList(u32).init(testing.allocator);
    defer direct_results.deinit();

    while (try direct.next()) |val| {
        try direct_results.append(val);
    }

    // Test Stream
    var vtable = fromSlice(u32, &data);
    var vtable_results = std.ArrayList(u32).init(testing.allocator);
    defer vtable_results.deinit();

    while (try vtable.next()) |val| {
        try vtable_results.append(val);
    }

    // Results should be identical
    try testing.expectEqualSlices(u32, direct_results.items, vtable_results.items);
}

test "DirectStream peek functionality" {
    const data = [_]u32{ 100, 200, 300 };
    var stream = directFromSlice(u32, &data);

    // Peek should not advance
    const peeked1 = try stream.peek();
    const peeked2 = try stream.peek();
    try testing.expectEqual(peeked1, peeked2);
    try testing.expectEqual(@as(?u32, 100), peeked1);

    // Next should return peeked value
    const next = try stream.next();
    try testing.expectEqual(peeked1, next);

    // Peek after next
    const peeked3 = try stream.peek();
    try testing.expectEqual(@as(?u32, 200), peeked3);
}

test "DirectStream position tracking" {
    const data = [_]u32{ 1, 2, 3, 4, 5 };
    var stream = directFromSlice(u32, &data);

    try testing.expectEqual(@as(usize, 0), stream.getPosition());

    _ = try stream.next();
    try testing.expectEqual(@as(usize, 1), stream.getPosition());

    _ = try stream.next();
    try testing.expectEqual(@as(usize, 2), stream.getPosition());

    // Peek doesn't change position
    _ = try stream.peek();
    try testing.expectEqual(@as(usize, 2), stream.getPosition());
}

test "DirectStream performance characteristics" {
    // Large dataset for performance testing
    var data = std.ArrayList(u32).init(testing.allocator);
    defer data.deinit();

    // Create 10000 elements
    var i: u32 = 0;
    while (i < 10000) : (i += 1) {
        try data.append(i);
    }

    // Measure DirectStream iteration
    const direct_start = std.time.nanoTimestamp();
    var direct_stream = directFromSlice(u32, data.items);
    var direct_sum: u64 = 0;
    while (try direct_stream.next()) |val| {
        direct_sum += val;
    }
    const direct_time = std.time.nanoTimestamp() - direct_start;

    // Measure Stream iteration
    const vtable_start = std.time.nanoTimestamp();
    var vtable_stream = fromSlice(u32, data.items);
    var vtable_sum: u64 = 0;
    while (try vtable_stream.next()) |val| {
        vtable_sum += val;
    }
    const vtable_time = std.time.nanoTimestamp() - vtable_start;

    // Verify same results
    try testing.expectEqual(direct_sum, vtable_sum);

    // Log performance (not asserting as it's system-dependent)
    std.debug.print("\n  DirectStream iteration: {} ns\n", .{direct_time});
    std.debug.print("  Stream (vtable) iteration: {} ns\n", .{vtable_time});

    if (direct_time < vtable_time) {
        const improvement = @as(f64, @floatFromInt(vtable_time - direct_time)) /
            @as(f64, @floatFromInt(vtable_time)) * 100;
        std.debug.print("  DirectStream {d:.1}% faster\n", .{improvement});
    }
}

test "DirectStream with different types" {
    // Test with f32
    const float_data = [_]f32{ 1.5, 2.5, 3.5 };
    var float_stream = directFromSlice(f32, &float_data);

    var float_sum: f32 = 0;
    while (try float_stream.next()) |val| {
        float_sum += val;
    }
    try testing.expectApproxEqAbs(@as(f32, 7.5), float_sum, 0.01);

    // Test with bool
    const bool_data = [_]bool{ true, false, true, true };
    var bool_stream = directFromSlice(bool, &bool_data);

    var true_count: u32 = 0;
    while (try bool_stream.next()) |val| {
        if (val) true_count += 1;
    }
    try testing.expectEqual(@as(u32, 3), true_count);
}

test "DirectStream empty slice handling" {
    const empty: []const u32 = &[_]u32{};
    var stream = directFromSlice(u32, empty);

    try testing.expectEqual(@as(?u32, null), try stream.next());
    try testing.expectEqual(@as(?u32, null), try stream.peek());
    try testing.expectEqual(@as(usize, 0), stream.getPosition());
}

// TODO: Test GeneratorStream when operator migration is complete
// TODO: Test MapStream when zero-allocation operators are implemented
// TODO: Test FilterStream when zero-allocation operators are implemented
// TODO: Test BatchStream when implemented for DirectStream
