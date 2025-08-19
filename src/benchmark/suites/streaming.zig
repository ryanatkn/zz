const std = @import("std");
const benchmark_lib = @import("../../lib/benchmark/mod.zig");
const BenchmarkResult = benchmark_lib.BenchmarkResult;
const BenchmarkOptions = benchmark_lib.BenchmarkOptions;
const BenchmarkError = benchmark_lib.BenchmarkError;

// Import streaming infrastructure
const TokenIterator = @import("../../lib/transform/streaming/token_iterator.zig").TokenIterator;
const IncrementalParser = @import("../../lib/transform/streaming/incremental_parser.zig").IncrementalParser;
const Context = @import("../../lib/transform/transform.zig").Context;

pub fn runStreamingBenchmarks(allocator: std.mem.Allocator, options: BenchmarkOptions) BenchmarkError![]BenchmarkResult {
    var results = std.ArrayList(BenchmarkResult).init(allocator);
    errdefer {
        for (results.items) |result| {
            result.deinit(allocator);
        }
        results.deinit();
    }
    
    const effective_duration = @as(u64, @intFromFloat(@as(f64, @floatFromInt(options.duration_ns)) * 2.0 * options.duration_multiplier));
    
    // NOTE: Warmup is disabled for streaming benchmarks (false instead of options.warmup)
    // Reason: These benchmarks process files and allocate memory extensively
    // Streaming operations are memory/IO bound, not CPU cache sensitive, so warmup provides no benefit
    
    // Load small test files for fast benchmark execution (10KB)
    const small_json = loadTestFile(allocator, "src/benchmark/fixtures/small_10kb.json") catch 
        try generateLargeJson(allocator, 10 * 1024);
    defer allocator.free(small_json);
    
    const small_zon = loadTestFile(allocator, "src/benchmark/fixtures/small_10kb.zon") catch 
        try generateLargeZon(allocator, 10 * 1024);
    defer allocator.free(small_zon);
    
    // 1. Traditional full-memory approach benchmark
    {
        const context = struct {
            allocator: std.mem.Allocator,
            text: []const u8,
            
            pub fn run(ctx: @This()) anyerror!void {
                // Simulate traditional approach: load all tokens into memory
                var token_list = std.ArrayList(MockToken).init(ctx.allocator);
                defer {
                    for (token_list.items) |token| {
                        ctx.allocator.free(token.text);
                    }
                    token_list.deinit();
                }
                
                // Tokenize entire text (memory-intensive)
                var i: usize = 0;
                var start: usize = 0;
                
                while (i <= ctx.text.len) {
                    const is_delimiter = (i == ctx.text.len) or 
                                        (ctx.text[i] == ' ' or ctx.text[i] == '\t' or 
                                         ctx.text[i] == '\n' or ctx.text[i] == '\r' or
                                         ctx.text[i] == '{' or ctx.text[i] == '}' or
                                         ctx.text[i] == '[' or ctx.text[i] == ']' or
                                         ctx.text[i] == ',' or ctx.text[i] == ':');
                    
                    if (is_delimiter) {
                        if (i > start) {
                            const text = try ctx.allocator.dupe(u8, ctx.text[start..i]);
                            const token = MockToken{
                                .text = text,
                                .start = start,
                                .end = i,
                            };
                            try token_list.append(token);
                        }
                        start = i + 1;
                    }
                    i += 1;
                }
                
                // Simulate processing all tokens
                for (token_list.items) |token| {
                    std.mem.doNotOptimizeAway(token.text.len);
                }
            }
        }{ .allocator = allocator, .text = small_json };
        
        const result = try benchmark_lib.measureOperationNamedWithSuite(allocator, "streaming", "Traditional Full-Memory JSON (10KB)", effective_duration, false, context, @TypeOf(context).run);
        try results.append(result);
    }
    
    // 2. Streaming approach benchmark  
    {
        const context = struct {
            allocator: std.mem.Allocator,
            text: []const u8,
            
            pub fn run(ctx: @This()) anyerror!void {
                var transform_context = Context.init(ctx.allocator);
                defer transform_context.deinit();
                
                // Use streaming iterator with small chunks
                var iterator = TokenIterator.init(ctx.allocator, ctx.text, &transform_context, null);
                defer iterator.deinit();
                
                iterator.setChunkSize(4096); // 4KB chunks for streaming
                
                // Process tokens one by one (memory-efficient)
                var token_count: usize = 0;
                while (try iterator.next()) |token| {
                    std.mem.doNotOptimizeAway(token.text.len);
                    token_count += 1;
                    
                    // Free token text immediately after processing
                    if (token.text.len > 0) {
                        ctx.allocator.free(token.text);
                    }
                }
                
                std.mem.doNotOptimizeAway(token_count);
            }
        }{ .allocator = allocator, .text = small_json };
        
        const result = try benchmark_lib.measureOperationNamedWithSuite(allocator, "streaming", "Streaming TokenIterator JSON (10KB)", effective_duration, false, context, @TypeOf(context).run);
        try results.append(result);
    }
    
    // 3. Memory usage comparison benchmark
    {
        const context = struct {
            allocator: std.mem.Allocator,
            text: []const u8,
            
            pub fn run(ctx: @This()) anyerror!void {
                // Measure memory usage of both approaches
                var arena = std.heap.ArenaAllocator.init(ctx.allocator);
                defer arena.deinit();
                const arena_allocator = arena.allocator();
                
                const initial_capacity = arena.queryCapacity();
                
                // Traditional approach
                {
                    var token_list = std.ArrayList(MockToken).init(arena_allocator);
                    defer token_list.deinit();
                    
                    // Quick tokenization for memory measurement
                    var i: usize = 0;
                    while (i < @min(ctx.text.len, 10000)) { // Sample first 10KB
                        if (ctx.text[i] == ' ' or ctx.text[i] == '\n' or ctx.text[i] == '{') {
                            const text = try arena_allocator.dupe(u8, "token");
                            try token_list.append(MockToken{
                                .text = text,
                                .start = i,
                                .end = i + 5,
                            });
                        }
                        i += 10; // Skip ahead for sampling
                    }
                }
                
                const traditional_capacity = arena.queryCapacity();
                const traditional_memory = traditional_capacity - initial_capacity;
                
                // Reset arena
                _ = arena.reset(.retain_capacity);
                
                // Streaming approach
                {
                    var transform_context = Context.init(arena_allocator);
                    defer transform_context.deinit();
                    
                    var iterator = TokenIterator.init(arena_allocator, ctx.text[0..@min(ctx.text.len, 10000)], &transform_context, null);
                    defer iterator.deinit();
                    
                    iterator.setChunkSize(1024); // Small chunks
                    
                    // Process a few tokens
                    var count: usize = 0;
                    while (count < 100 and (try iterator.next()) != null) {
                        count += 1;
                    }
                }
                
                const streaming_capacity = arena.queryCapacity();
                const streaming_memory = streaming_capacity - initial_capacity;
                
                // Calculate memory reduction
                const reduction_percent = if (traditional_memory > 0) 
                    (100.0 * @as(f64, @floatFromInt(traditional_memory - streaming_memory))) / @as(f64, @floatFromInt(traditional_memory))
                else 0.0;
                
                std.mem.doNotOptimizeAway(reduction_percent);
                std.mem.doNotOptimizeAway(traditional_memory);
                std.mem.doNotOptimizeAway(streaming_memory);
            }
        }{ .allocator = allocator, .text = small_json };
        
        const result = try benchmark_lib.measureOperationNamedWithSuite(allocator, "streaming", "Memory Usage Comparison (10KB)", effective_duration, false, context, @TypeOf(context).run);
        try results.append(result);
    }
    
    // 4. Incremental parser benchmark
    {
        const context = struct {
            allocator: std.mem.Allocator,
            text: []const u8,
            
            pub fn run(ctx: @This()) anyerror!void {
                var transform_context = Context.init(ctx.allocator);
                defer transform_context.deinit();
                
                var iterator = TokenIterator.init(ctx.allocator, ctx.text, &transform_context, null);
                defer iterator.deinit();
                
                var parser = IncrementalParser.init(ctx.allocator, &transform_context, &iterator, null);
                defer parser.deinit();
                
                parser.setMaxMemory(5); // 5MB limit
                
                const result = try parser.parseTokenStream(1000); // Parse up to 1000 tokens
                std.mem.doNotOptimizeAway(result.total_nodes);
                std.mem.doNotOptimizeAway(result.memory_used_bytes);
            }
        }{ .allocator = allocator, .text = small_zon };
        
        const result = try benchmark_lib.measureOperationNamedWithSuite(allocator, "streaming", "Incremental Parser ZON (10KB)", effective_duration, false, context, @TypeOf(context).run);
        try results.append(result);
    }
    
    // 5. Transform pipeline overhead benchmark - Direct vs Pipeline
    {
        const simple_json = "{\"name\":\"test\",\"value\":42}";
        
        const context = struct {
            allocator: std.mem.Allocator,
            text: []const u8,
            
            pub fn run(ctx: @This()) anyerror!void {
                // Baseline: Direct function calls (no transform pipeline)
                var direct_tokens = std.ArrayList(MockToken).init(ctx.allocator);
                defer {
                    for (direct_tokens.items) |token| {
                        ctx.allocator.free(token.text);
                    }
                    direct_tokens.deinit();
                }
                
                // Simple direct tokenization
                var i: usize = 0;
                var start: usize = 0;
                
                while (i <= ctx.text.len) {
                    const is_delimiter = (i == ctx.text.len) or 
                                        (ctx.text[i] == '{' or ctx.text[i] == '}' or
                                         ctx.text[i] == ':' or ctx.text[i] == ',' or
                                         ctx.text[i] == '"');
                    
                    if (is_delimiter) {
                        if (i > start) {
                            const text = try ctx.allocator.dupe(u8, ctx.text[start..i]);
                            try direct_tokens.append(MockToken{
                                .text = text,
                                .start = start,
                                .end = i,
                            });
                        }
                        start = i + 1;
                    }
                    i += 1;
                }
                
                std.mem.doNotOptimizeAway(direct_tokens.items.len);
            }
        }{ .allocator = allocator, .text = simple_json };
        
        const result = try benchmark_lib.measureOperationNamedWithSuite(allocator, "streaming", "Direct Function Calls (Baseline)", effective_duration, false, context, @TypeOf(context).run);
        try results.append(result);
    }
    
    // 6. Transform pipeline with small chunks (worst case overhead)
    {
        const simple_json = "{\"users\":[{\"id\":1,\"name\":\"Alice\"}]}";
        
        const context = struct {
            allocator: std.mem.Allocator,
            text: []const u8,
            
            pub fn run(ctx: @This()) anyerror!void {
                var transform_context = Context.init(ctx.allocator);
                defer transform_context.deinit();
                
                var iterator = TokenIterator.init(ctx.allocator, ctx.text, &transform_context, null);
                defer iterator.deinit();
                
                iterator.setChunkSize(64); // Small chunks to maximize overhead
                
                var token_count: usize = 0;
                while (try iterator.next()) |token| {
                    token_count += 1;
                    if (token.text.len > 0) {
                        ctx.allocator.free(token.text);
                    }
                }
                
                std.mem.doNotOptimizeAway(token_count);
            }
        }{ .allocator = allocator, .text = simple_json };
        
        const result = try benchmark_lib.measureOperationNamedWithSuite(allocator, "streaming", "Transform Pipeline (Small Chunks)", effective_duration, false, context, @TypeOf(context).run);
        try results.append(result);
    }
    
    // 7. Transform pipeline with optimal chunk size
    {
        const medium_json = try generateLargeJson(allocator, 50 * 1024); // 50KB
        defer allocator.free(medium_json);
        
        const context = struct {
            allocator: std.mem.Allocator,
            text: []const u8,
            
            pub fn run(ctx: @This()) anyerror!void {
                var transform_context = Context.init(ctx.allocator);
                defer transform_context.deinit();
                
                var iterator = TokenIterator.init(ctx.allocator, ctx.text, &transform_context, null);
                defer iterator.deinit();
                
                iterator.setChunkSize(4096); // Optimal chunk size
                
                var token_count: usize = 0;
                while (try iterator.next()) |token| {
                    token_count += 1;
                    if (token.text.len > 0) {
                        ctx.allocator.free(token.text);
                    }
                }
                
                std.mem.doNotOptimizeAway(token_count);
            }
        }{ .allocator = allocator, .text = medium_json };
        
        const result = try benchmark_lib.measureOperationNamedWithSuite(allocator, "streaming", "Transform Pipeline (Optimal Chunks)", effective_duration, false, context, @TypeOf(context).run);
        try results.append(result);
        
        // Pipeline overhead target: <5% vs direct calls
        if (result.ns_per_op > 10_000) { // Log significant overhead
            std.log.info("Transform pipeline overhead: {}ns per operation", .{result.ns_per_op});
        }
    }
    
    return results.toOwnedSlice();
}

// Helper types and functions

const MockToken = struct {
    text: []const u8,
    start: usize,
    end: usize,
};

fn loadTestFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    
    const file_size = try file.getEndPos();
    const content = try allocator.alloc(u8, file_size);
    _ = try file.readAll(content);
    
    return content;
}

fn generateLargeJson(allocator: std.mem.Allocator, target_size: usize) ![]u8 {
    var content = std.ArrayList(u8).init(allocator);
    defer content.deinit();
    
    try content.appendSlice("{\"users\":[");
    
    var i: u32 = 0;
    while (content.items.len < target_size - 100) {
        if (i > 0) try content.appendSlice(",");
        
        try content.writer().print(
            "{{\"id\":{},\"name\":\"User {}\",\"active\":{}}}",
            .{ i, i, i % 2 == 0 }
        );
        i += 1;
    }
    
    try content.appendSlice("]}");
    return content.toOwnedSlice();
}

fn generateLargeZon(allocator: std.mem.Allocator, target_size: usize) ![]u8 {
    var content = std.ArrayList(u8).init(allocator);
    defer content.deinit();
    
    try content.appendSlice(".{.dependencies=.{");
    
    var i: u32 = 0;
    while (content.items.len < target_size - 100) {
        if (i > 0) try content.appendSlice(",");
        
        try content.writer().print(
            ".@\"dep_{}\"=.{{.url=\"https://example.com/dep_{}\",  .version=\"1.0.{}\"}}", 
            .{ i, i, i }
        );
        i += 1;
    }
    
    try content.appendSlice("}}");
    return content.toOwnedSlice();
}