/// Performance benchmarks comparing DirectStream vs vtable Stream
const std = @import("std");
const builtin = @import("builtin");

const stream_mod = @import("../lib/stream/mod.zig");
const Stream = stream_mod.Stream;
const DirectStream = stream_mod.DirectStream;
const directFromSlice = stream_mod.directFromSlice;

pub const BenchmarkResult = struct {
    avg_cycles: f64,
    total_time_us: f64,
    throughput_mops: f64, // Million operations per second
};

/// Get CPU timestamp counter for cycle measurements
inline fn rdtsc() u64 {
    if (builtin.cpu.arch == .x86_64) {
        var low: u32 = undefined;
        var high: u32 = undefined;
        asm volatile ("rdtsc"
            : [low] "={eax}" (low),
              [high] "={edx}" (high),
        );
        return (@as(u64, high) << 32) | @as(u64, low);
    } else {
        // Fallback for non-x86 architectures
        return @intCast(std.time.nanoTimestamp());
    }
}

/// Benchmark DirectStream with tagged union dispatch
pub fn benchmarkDirectStream(allocator: std.mem.Allocator, data: []const i32) !BenchmarkResult {
    _ = allocator;
    
    const iterations = 1000;
    var total_cycles: u64 = 0;
    var total_time: u64 = 0;
    
    // Warm up
    for (0..10) |_| {
        var stream = directFromSlice(i32, data);
        while (try stream.next()) |_| {}
    }
    
    // Actual benchmark
    const start_time = std.time.nanoTimestamp();
    
    for (0..iterations) |_| {
        var stream = directFromSlice(i32, data);
        
        const start_cycles = rdtsc();
        var count: usize = 0;
        while (try stream.next()) |_| {
            count += 1;
        }
        const end_cycles = rdtsc();
        
        total_cycles += end_cycles - start_cycles;
    }
    
    const end_time = std.time.nanoTimestamp();
    total_time = @intCast(end_time - start_time);
    
    const avg_cycles_per_op = @as(f64, @floatFromInt(total_cycles)) / 
                              @as(f64, @floatFromInt(iterations * data.len));
    const total_time_us = @as(f64, @floatFromInt(total_time)) / 1000.0;
    const throughput = @as(f64, @floatFromInt(iterations * data.len)) / 
                       (@as(f64, @floatFromInt(total_time)) / 1e9) / 1e6;
    
    return BenchmarkResult{
        .avg_cycles = avg_cycles_per_op,
        .total_time_us = total_time_us,
        .throughput_mops = throughput,
    };
}

/// Benchmark vtable Stream with indirect dispatch
pub fn benchmarkVtableStream(allocator: std.mem.Allocator, data: []const i32) !BenchmarkResult {
    _ = allocator;
    const iterations = 1000;
    var total_cycles: u64 = 0;
    var total_time: u64 = 0;
    
    // Warm up
    for (0..10) |_| {
        var stream = stream_mod.fromSlice(i32, data);
        while (try stream.next()) |_| {}
    }
    
    // Actual benchmark
    const start_time = std.time.nanoTimestamp();
    
    for (0..iterations) |_| {
        var stream = stream_mod.fromSlice(i32, data);
        
        const start_cycles = rdtsc();
        var count: usize = 0;
        while (try stream.next()) |_| {
            count += 1;
        }
        const end_cycles = rdtsc();
        
        total_cycles += end_cycles - start_cycles;
    }
    
    const end_time = std.time.nanoTimestamp();
    total_time = @intCast(end_time - start_time);
    
    const avg_cycles_per_op = @as(f64, @floatFromInt(total_cycles)) / 
                              @as(f64, @floatFromInt(iterations * data.len));
    const total_time_us = @as(f64, @floatFromInt(total_time)) / 1000.0;
    const throughput = @as(f64, @floatFromInt(iterations * data.len)) / 
                       (@as(f64, @floatFromInt(total_time)) / 1e9) / 1e6;
    
    return BenchmarkResult{
        .avg_cycles = avg_cycles_per_op,
        .total_time_us = total_time_us,
        .throughput_mops = throughput,
    };
}

/// Benchmark DirectStream with operator chaining
pub fn benchmarkDirectStreamOperators(allocator: std.mem.Allocator, data: []const i32) !BenchmarkResult {
    _ = allocator;
    const iterations = 1000;
    var total_cycles: u64 = 0;
    var total_time: u64 = 0;
    
    const directFilter = @import("../lib/stream/direct_stream.zig").directFilter;
    const directTake = @import("../lib/stream/direct_stream.zig").directTake;
    
    // Warm up
    for (0..10) |_| {
        const stream = directFromSlice(i32, data);
        
        // Apply filter (only even numbers)
        const filtered = try directFilter(i32, stream, struct {
            fn isEven(x: i32) bool {
                return @mod(x, 2) == 0;
            }
        }.isEven);
        
        // Apply take (first 100)
        var limited = try directTake(i32, filtered, 100);
        
        while (try limited.next()) |_| {}
    }
    
    // Actual benchmark
    const start_time = std.time.nanoTimestamp();
    
    for (0..iterations) |_| {
        const stream = directFromSlice(i32, data);
        
        const start_cycles = rdtsc();
        
        // Chain operators
        const filtered = try directFilter(i32, stream, struct {
            fn isEven(x: i32) bool {
                return @mod(x, 2) == 0;
            }
        }.isEven);
        var limited = try directTake(i32, filtered, 100);
        
        var count: usize = 0;
        while (try limited.next()) |_| {
            count += 1;
        }
        
        const end_cycles = rdtsc();
        total_cycles += end_cycles - start_cycles;
    }
    
    const end_time = std.time.nanoTimestamp();
    total_time = @intCast(end_time - start_time);
    
    const avg_cycles_per_op = @as(f64, @floatFromInt(total_cycles)) / 
                              @as(f64, @floatFromInt(iterations * 100)); // Only 100 items after take
    const total_time_us = @as(f64, @floatFromInt(total_time)) / 1000.0;
    const throughput = @as(f64, @floatFromInt(iterations * 100)) / 
                       (@as(f64, @floatFromInt(total_time)) / 1e9) / 1e6;
    
    return BenchmarkResult{
        .avg_cycles = avg_cycles_per_op,
        .total_time_us = total_time_us,
        .throughput_mops = throughput,
    };
}

/// Benchmark JSON tokenization performance
pub fn benchmarkJsonTokenization(json_input: []const u8) !BenchmarkResult {
    const JsonStreamLexer = @import("../lib/languages/json/stream_lexer.zig").JsonStreamLexer;
    
    const iterations = 100;
    var total_cycles: u64 = 0;
    var total_time: u64 = 0;
    var token_count: usize = 0;
    
    // Warm up
    for (0..10) |_| {
        var lexer = JsonStreamLexer.init(json_input);
        while (lexer.next()) |token| {
            if (token.json.kind == .eof) break;
        }
    }
    
    // Actual benchmark
    const start_time = std.time.nanoTimestamp();
    
    for (0..iterations) |_| {
        var lexer = JsonStreamLexer.init(json_input);
        
        const start_cycles = rdtsc();
        token_count = 0;
        while (lexer.next()) |token| {
            if (token.json.kind == .eof) break;
            token_count += 1;
        }
        const end_cycles = rdtsc();
        
        total_cycles += end_cycles - start_cycles;
    }
    
    const end_time = std.time.nanoTimestamp();
    total_time = @intCast(end_time - start_time);
    
    const avg_cycles_per_token = @as(f64, @floatFromInt(total_cycles)) / 
                                 @as(f64, @floatFromInt(iterations * token_count));
    const total_time_us = @as(f64, @floatFromInt(total_time)) / 1000.0;
    const throughput_mb = @as(f64, @floatFromInt(iterations * json_input.len)) / 
                          (@as(f64, @floatFromInt(total_time)) / 1e9) / 1e6;
    
    return BenchmarkResult{
        .avg_cycles = avg_cycles_per_token,
        .total_time_us = total_time_us,
        .throughput_mops = throughput_mb, // MB/sec for tokenization
    };
}

/// Benchmark ZON tokenization performance
pub fn benchmarkZonTokenization(zon_input: []const u8) !BenchmarkResult {
    const ZonStreamLexer = @import("../lib/languages/zon/stream_lexer.zig").ZonStreamLexer;
    
    const iterations = 100;
    var total_cycles: u64 = 0;
    var total_time: u64 = 0;
    var token_count: usize = 0;
    
    // Warm up
    for (0..10) |_| {
        var lexer = ZonStreamLexer.init(zon_input);
        while (lexer.next()) |token| {
            if (token.zon.kind == .eof) break;
        }
    }
    
    // Actual benchmark
    const start_time = std.time.nanoTimestamp();
    
    for (0..iterations) |_| {
        var lexer = ZonStreamLexer.init(zon_input);
        
        const start_cycles = rdtsc();
        token_count = 0;
        while (lexer.next()) |token| {
            if (token.zon.kind == .eof) break;
            token_count += 1;
        }
        const end_cycles = rdtsc();
        
        total_cycles += end_cycles - start_cycles;
    }
    
    const end_time = std.time.nanoTimestamp();
    total_time = @intCast(end_time - start_time);
    
    const avg_cycles_per_token = @as(f64, @floatFromInt(total_cycles)) / 
                                 @as(f64, @floatFromInt(iterations * token_count));
    const total_time_us = @as(f64, @floatFromInt(total_time)) / 1000.0;
    const throughput_mb = @as(f64, @floatFromInt(iterations * zon_input.len)) / 
                          (@as(f64, @floatFromInt(total_time)) / 1e9) / 1e6;
    
    return BenchmarkResult{
        .avg_cycles = avg_cycles_per_token,
        .total_time_us = total_time_us,
        .throughput_mops = throughput_mb, // MB/sec for tokenization
    };
}