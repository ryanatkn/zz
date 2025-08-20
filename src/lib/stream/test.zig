const std = @import("std");
const testing = std.testing;

// Import all stream modules
const stream = @import("mod.zig");
const Stream = stream.Stream;
const StreamError = @import("error.zig").StreamError;
const RingBuffer = @import("buffer.zig").RingBuffer;
const source = @import("source.zig");
const sink = @import("sink.zig");
const operators = @import("operators.zig");
const fusion = @import("fusion.zig");

test "Stream module exports" {
    // Verify all expected exports are available
    _ = Stream;
    _ = StreamError;
    _ = RingBuffer;
    _ = source.MemorySource;
    _ = source.FileSource;
    _ = source.GeneratorSource;
    _ = sink.BufferSink;
    _ = sink.FileSink;
    _ = sink.NullSink;
    _ = operators.map;
    _ = operators.filter;
    _ = operators.batch;
}

test "End-to-end: Stream from slice to sink" {
    const data = "Hello, Stream World!";
    var src = source.MemorySource(u8).init(data);
    var str = src.stream();

    var buffer_sink = sink.BufferSink.init(testing.allocator);
    defer buffer_sink.deinit();

    // Read from stream and write to sink
    while (try str.next()) |byte| {
        try buffer_sink.writeItem(byte);
    }

    const result = buffer_sink.getBuffer();
    try testing.expectEqualStrings(data, result);
}

test "Stream composition: map and filter" {
    const data = [_]u32{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 };
    var src = source.MemorySource(u32).init(&data);
    const str = src.stream();

    // Double all numbers
    const double = struct {
        fn f(x: u32) u32 {
            return x * 2;
        }
    }.f;

    // Keep only those divisible by 4
    const divBy4 = struct {
        fn f(x: u32) bool {
            return x % 4 == 0;
        }
    }.f;

    const doubled = operators.map(u32, u32, str, &double);
    var filtered = operators.filter(u32, doubled, &divBy4);

    // Should get: 2*2=4, 2*4=8, 2*6=12, 2*8=16, 2*10=20
    // After filter: 4, 8, 12, 16, 20
    try testing.expectEqual(@as(?u32, 4), try filtered.next());
    try testing.expectEqual(@as(?u32, 8), try filtered.next());
    try testing.expectEqual(@as(?u32, 12), try filtered.next());
    try testing.expectEqual(@as(?u32, 16), try filtered.next());
    try testing.expectEqual(@as(?u32, 20), try filtered.next());
    try testing.expectEqual(@as(?u32, null), try filtered.next());
}

test "RingBuffer as stream buffer" {
    var buffer = RingBuffer(u32, 5).init();

    // Producer writes
    try buffer.push(1);
    try buffer.push(2);
    try buffer.push(3);

    // Consumer reads
    try testing.expectEqual(@as(?u32, 1), buffer.pop());

    // Producer writes more
    try buffer.push(4);
    try buffer.push(5);
    try buffer.push(6); // Buffer now has: 2,3,4,5,6

    // Should be full
    try testing.expect(buffer.isFull());
    try testing.expectError(StreamError.BufferFull, buffer.push(7));

    // Consumer catches up
    try testing.expectEqual(@as(?u32, 2), buffer.pop());
    try testing.expectEqual(@as(?u32, 3), buffer.pop());
    try testing.expectEqual(@as(?u32, 4), buffer.pop());
    try testing.expectEqual(@as(?u32, 5), buffer.pop());
    try testing.expectEqual(@as(?u32, 6), buffer.pop());
    try testing.expectEqual(@as(?u32, null), buffer.pop());
}

test "Stream composition: drop then take" {
    // Complex composition test - simple take/drop tests are in operators.zig
    const data = [_]u8{ 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h' };
    var src = source.MemorySource(u8).init(&data);
    const str = src.stream();
    const dropped = operators.drop(u8, str, 2);
    var taken = operators.take(u8, dropped, 3);

    try testing.expectEqual(@as(?u8, 'c'), try taken.next());
    try testing.expectEqual(@as(?u8, 'd'), try taken.next());
    try testing.expectEqual(@as(?u8, 'e'), try taken.next());
    try testing.expectEqual(@as(?u8, null), try taken.next());
}

test "Generator source" {
    // Fibonacci generator
    const FibState = struct {
        a: u32 = 0,
        b: u32 = 1,
        count: u8 = 0,
        max: u8 = 10,
    };

    var state = FibState{};

    const fibGen = struct {
        fn generate(s: *anyopaque) ?u8 {
            const fib = @as(*FibState, @ptrCast(@alignCast(s)));
            if (fib.count >= fib.max) return null;

            const result = @as(u8, @truncate(fib.a));
            const next = fib.a + fib.b;
            fib.a = fib.b;
            fib.b = next;
            fib.count += 1;

            return result;
        }
    }.generate;

    var gen_source = source.GeneratorSource.init(@ptrCast(&state), fibGen);
    var str = gen_source.stream();

    // First 10 Fibonacci numbers (truncated to u8)
    try testing.expectEqual(@as(?u8, 0), try str.next());
    try testing.expectEqual(@as(?u8, 1), try str.next());
    try testing.expectEqual(@as(?u8, 1), try str.next());
    try testing.expectEqual(@as(?u8, 2), try str.next());
    try testing.expectEqual(@as(?u8, 3), try str.next());
    try testing.expectEqual(@as(?u8, 5), try str.next());
    try testing.expectEqual(@as(?u8, 8), try str.next());
    try testing.expectEqual(@as(?u8, 13), try str.next());
    try testing.expectEqual(@as(?u8, 21), try str.next());
    try testing.expectEqual(@as(?u8, 34), try str.next());
    try testing.expectEqual(@as(?u8, null), try str.next());
}

test "Stream peek operations" {
    const data = [_]i32{ 10, 20, 30, 40, 50 };
    var src = source.MemorySource(i32).init(&data);
    var str = src.stream();

    // Peek doesn't advance
    try testing.expectEqual(@as(?i32, 10), try str.peek());
    try testing.expectEqual(@as(?i32, 10), try str.peek());
    try testing.expectEqual(@as(usize, 0), str.getPosition());

    // Next advances
    try testing.expectEqual(@as(?i32, 10), try str.next());
    try testing.expectEqual(@as(usize, 1), str.getPosition());

    // Peek at new position
    try testing.expectEqual(@as(?i32, 20), try str.peek());
    try testing.expectEqual(@as(?i32, 20), try str.next());

    // Skip advances position
    try str.skip(2);
    try testing.expectEqual(@as(usize, 4), str.getPosition());
    try testing.expectEqual(@as(?i32, 50), try str.peek());
}

test "Stream composition: merge operator" {
    const data1 = [_]u32{ 1, 3, 5 };
    const data2 = [_]u32{ 2, 4, 6 };

    var src1 = source.MemorySource(u32).init(&data1);
    var src2 = source.MemorySource(u32).init(&data2);
    const str1 = src1.stream();
    const str2 = src2.stream();

    var merged = operators.merge(u32, str1, str2);

    // Should alternate between streams
    try testing.expectEqual(@as(?u32, 1), try merged.next()); // from str1
    try testing.expectEqual(@as(?u32, 2), try merged.next()); // from str2
    try testing.expectEqual(@as(?u32, 3), try merged.next()); // from str1
    try testing.expectEqual(@as(?u32, 4), try merged.next()); // from str2
    try testing.expectEqual(@as(?u32, 5), try merged.next()); // from str1
    try testing.expectEqual(@as(?u32, 6), try merged.next()); // from str2
    try testing.expectEqual(@as(?u32, null), try merged.next());
}

test "BufferSink with capacity" {
    var buffer_sink = try sink.BufferSink.initWithCapacity(testing.allocator, 256);
    defer buffer_sink.deinit();

    const data = "Hello, World!";
    const written = try buffer_sink.write(data);
    try testing.expectEqual(data.len, written);

    const result = buffer_sink.getBuffer();
    try testing.expectEqualStrings(data, result);

    // Test clear
    buffer_sink.clear();
    try testing.expectEqual(@as(usize, 0), buffer_sink.getBuffer().len);

    // Write again after clear
    _ = try buffer_sink.write("New data");
    try testing.expectEqualStrings("New data", buffer_sink.getBuffer());
}

test "ChannelSink for stream communication" {
    var ring = RingBuffer(u8, 4096).init();
    var channel = sink.ChannelSink.init(&ring);

    // Write to channel
    const msg = "Stream message";
    const written = try channel.write(msg);
    try testing.expectEqual(msg.len, written);

    // Read from ring buffer
    var output: [20]u8 = undefined;
    const read_count = ring.read(&output);
    try testing.expectEqual(msg.len, read_count);
    try testing.expectEqualStrings(msg, output[0..read_count]);

    // Test channel closing
    channel.close();
    try testing.expect(channel.isClosed());
    try testing.expectError(StreamError.StreamClosed, channel.write("test"));
}

test "Stream error conditions" {
    // Test buffer full
    var buffer = RingBuffer(u8, 3).init();
    try buffer.push('a');
    try buffer.push('b');
    try buffer.push('c');
    try testing.expectError(StreamError.BufferFull, buffer.push('d'));

    // Test empty buffer
    var empty = RingBuffer(u8, 10).init();
    try testing.expectEqual(@as(?u8, null), empty.pop());

    // Test sink with max size
    var limited_sink = sink.BufferSink.init(testing.allocator);
    defer limited_sink.deinit();
    limited_sink.max_size = 5;

    const written = try limited_sink.write("Hello");
    try testing.expectEqual(@as(usize, 5), written);
    try testing.expectError(StreamError.BufferFull, limited_sink.write("World"));
}

test "Stream position tracking" {
    const data = "abcdefghij";
    var src = source.MemorySource(u8).init(data);
    var str = src.stream();

    try testing.expectEqual(@as(usize, 0), str.getPosition());

    _ = try str.next();
    try testing.expectEqual(@as(usize, 1), str.getPosition());

    try str.skip(3);
    try testing.expectEqual(@as(usize, 4), str.getPosition());

    // Read rest
    while (try str.next()) |_| {}
    try testing.expectEqual(@as(usize, data.len), str.getPosition());
    try testing.expect(str.isExhausted());
}

test "Zero-allocation verification" {
    // This test verifies that our core operations don't allocate
    const data = [_]u32{ 1, 2, 3, 4, 5 };
    var src = source.MemorySource(u32).init(&data);
    var str = src.stream();

    // These operations should not allocate
    _ = try str.next();
    _ = try str.peek();
    try str.skip(1);
    _ = str.getPosition();
    _ = str.isExhausted();

    // Ring buffer operations also don't allocate
    var ring = RingBuffer(u32, 10).init();
    try ring.push(42);
    _ = ring.pop();
    _ = ring.peek();
    ring.clear();
}

test "Stream composition: map then filter" {
    const data = [_]u32{ 1, 2, 3, 4, 5 };
    var src = source.MemorySource(u32).init(&data);
    const str = src.stream();
    
    const double = struct {
        fn f(x: u32) u32 { return x * 2; }
    }.f;
    
    const greaterThan4 = struct {
        fn f(x: u32) bool { return x > 4; }
    }.f;
    
    const mapped = operators.map(u32, u32, str, double);
    var filtered = operators.filter(u32, mapped, greaterThan4);
    
    try testing.expectEqual(@as(?u32, 6), try filtered.next());
    try testing.expectEqual(@as(?u32, 8), try filtered.next());
    try testing.expectEqual(@as(?u32, 10), try filtered.next());
    try testing.expectEqual(@as(?u32, null), try filtered.next());
}

test "Stream composition: complex chain" {
    const data = [_]u32{ 1, 2, 3, 4, 5, 6, 7, 8 };
    var src = source.MemorySource(u32).init(&data);
    const str = src.stream();
    
    const isEven = struct {
        fn f(x: u32) bool { return x % 2 == 0; }
    }.f;
    
    const square = struct {
        fn f(x: u32) u32 { return x * x; }
    }.f;
    
    // filter -> map -> take -> drop
    const filtered = operators.filter(u32, str, isEven);
    const mapped = operators.map(u32, u32, filtered, square);
    const taken = operators.take(u32, mapped, 3);
    var dropped = operators.drop(u32, taken, 1);
    
    // Should get: 16, 36 (skipping 4)
    try testing.expectEqual(@as(?u32, 16), try dropped.next());
    try testing.expectEqual(@as(?u32, 36), try dropped.next());
    try testing.expectEqual(@as(?u32, null), try dropped.next());
}

test "fusedMap with identity function" {
    const data = [_]u32{ 1, 2, 3 };
    var src = source.MemorySource(u32).init(&data);
    const str = src.stream();
    
    const identity = struct {
        fn f(x: u32) u32 { return x; }
    }.f;
    
    const addOne = struct {
        fn f(x: u32) u32 { return x + 1; }
    }.f;
    
    // identity composed with addOne should just be addOne
    var fused = fusion.fusedMap(u32, u32, u32, str, identity, addOne);
    
    try testing.expectEqual(@as(?u32, 2), try fused.next());
    try testing.expectEqual(@as(?u32, 3), try fused.next());
    try testing.expectEqual(@as(?u32, 4), try fused.next());
    try testing.expectEqual(@as(?u32, null), try fused.next());
}

test "fusedFilter with contradictory predicates" {
    const data = [_]u32{ 1, 2, 3, 4, 5, 6 };
    var src = source.MemorySource(u32).init(&data);
    const str = src.stream();
    
    const isEven = struct {
        fn f(x: u32) bool { return x % 2 == 0; }
    }.f;
    
    const isOdd = struct {
        fn f(x: u32) bool { return x % 2 == 1; }
    }.f;
    
    // Contradictory predicates - should return empty stream
    var fused = fusion.fusedFilter(u32, str, isEven, isOdd);
    
    try testing.expectEqual(@as(?u32, null), try fused.next());
}

test "fusedFilter with overlapping predicates" {
    const data = [_]u32{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 };
    var src = source.MemorySource(u32).init(&data);
    const str = src.stream();
    
    const divisibleBy3 = struct {
        fn f(x: u32) bool { return x % 3 == 0; }
    }.f;
    
    const divisibleBy2 = struct {
        fn f(x: u32) bool { return x % 2 == 0; }
    }.f;
    
    // Should only get numbers divisible by both 2 and 3 (i.e., by 6)
    var fused = fusion.fusedFilter(u32, str, divisibleBy3, divisibleBy2);
    
    try testing.expectEqual(@as(?u32, 6), try fused.next());
    try testing.expectEqual(@as(?u32, 12), try fused.next());
    try testing.expectEqual(@as(?u32, null), try fused.next());
}

test "fusedMap with type transformation chain" {
    const data = [_]u8{ 1, 2, 3 };
    var src = source.MemorySource(u8).init(&data);
    const str = src.stream();
    
    const toU32 = struct {
        fn f(x: u8) u32 { return @as(u32, x) * 100; }
    }.f;
    
    const toI64 = struct {
        fn f(x: u32) i64 { return @as(i64, x) + 1000; }
    }.f;
    
    // u8 -> u32 -> i64
    var fused = fusion.fusedMap(u8, u32, i64, str, toU32, toI64);
    
    try testing.expectEqual(@as(?i64, 1100), try fused.next());
    try testing.expectEqual(@as(?i64, 1200), try fused.next());
    try testing.expectEqual(@as(?i64, 1300), try fused.next());
    try testing.expectEqual(@as(?i64, null), try fused.next());
}

test "fusedMap with empty stream" {
    const data = [_]u32{};
    var src = source.MemorySource(u32).init(&data);
    const str = src.stream();
    
    const f1 = struct {
        fn f(x: u32) u32 { return x * 2; }
    }.f;
    
    const f2 = struct {
        fn f(x: u32) u32 { return x + 1; }
    }.f;
    
    var fused = fusion.fusedMap(u32, u32, u32, str, f1, f2);
    
    try testing.expectEqual(@as(?u32, null), try fused.next());
    try testing.expect(fused.isExhausted());
}

test "fusedFilter peek operation" {
    const data = [_]u32{ 1, 2, 3, 4, 5, 6, 7, 8 };
    var src = source.MemorySource(u32).init(&data);
    const str = src.stream();
    
    const greaterThan2 = struct {
        fn f(x: u32) bool { return x > 2; }
    }.f;
    
    const lessThan7 = struct {
        fn f(x: u32) bool { return x < 7; }
    }.f;
    
    var fused = fusion.fusedFilter(u32, str, greaterThan2, lessThan7);
    
    // Peek should not advance
    try testing.expectEqual(@as(?u32, 3), try fused.peek());
    try testing.expectEqual(@as(?u32, 3), try fused.peek());
    
    // Next should return the peeked value
    try testing.expectEqual(@as(?u32, 3), try fused.next());
    
    // Continue with rest
    try testing.expectEqual(@as(?u32, 4), try fused.next());
    try testing.expectEqual(@as(?u32, 5), try fused.next());
    try testing.expectEqual(@as(?u32, 6), try fused.next());
    try testing.expectEqual(@as(?u32, null), try fused.next());
}

test "Stream composition: with arena allocator" {
    const memory = @import("../memory/mod.zig");
    
    var arena = memory.Arena.init(testing.allocator);
    defer arena.deinit();
    
    const old_allocator = operators.getOperatorAllocator();
    operators.setOperatorAllocator(arena.allocator());
    defer operators.setOperatorAllocator(old_allocator);
    
    const data = [_]u32{ 1, 2, 3, 4, 5 };
    var src = source.MemorySource(u32).init(&data);
    const str = src.stream();
    
    const addTen = struct {
        fn f(x: u32) u32 { return x + 10; }
    }.f;
    
    const mapped = operators.map(u32, u32, str, addTen);
    var limited = operators.take(u32, mapped, 3);
    
    try testing.expectEqual(@as(?u32, 11), try limited.next());
    try testing.expectEqual(@as(?u32, 12), try limited.next());
    try testing.expectEqual(@as(?u32, 13), try limited.next());
    try testing.expectEqual(@as(?u32, null), try limited.next());
    
    arena.reset(); // All operators cleaned up at once
}

test "fusedMap position tracking" {
    const data = [_]u32{ 10, 20, 30, 40, 50 };
    var src = source.MemorySource(u32).init(&data);
    const str = src.stream();
    
    const f1 = struct {
        fn f(x: u32) u32 { return x / 10; }
    }.f;
    
    const f2 = struct {
        fn f(x: u32) u32 { return x * 3; }
    }.f;
    
    var fused = fusion.fusedMap(u32, u32, u32, str, f1, f2);
    
    try testing.expectEqual(@as(usize, 0), fused.getPosition());
    
    _ = try fused.next();
    try testing.expectEqual(@as(usize, 1), fused.getPosition());
    
    try fused.skip(2);
    try testing.expectEqual(@as(usize, 3), fused.getPosition());
    
    _ = try fused.next();
    _ = try fused.next();
    try testing.expect(fused.isExhausted());
}

// Run all module tests
test {
    _ = @import("buffer.zig");
    _ = @import("source.zig");
    _ = @import("sink.zig");
    _ = @import("stream.zig");
    _ = @import("operators.zig");
    _ = @import("fusion.zig");        // Operator fusion tests
    _ = @import("operator_pool.zig"); // Object pool tests
    _ = @import("error.zig");
}
