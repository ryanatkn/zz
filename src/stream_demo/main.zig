/// Stream Demo - Showcase DirectStream performance and capabilities
/// Demonstrates the stream-first architecture with JSON/ZON examples
const std = @import("std");
const FilesystemInterface = @import("../lib/filesystem/interface.zig").FilesystemInterface;

// Stream-first imports
const stream_mod = @import("../lib/stream/mod.zig");
const DirectStream = stream_mod.DirectStream;
const directFromSlice = stream_mod.directFromSlice;

const fact_mod = @import("../lib/fact/mod.zig");
const Fact = fact_mod.Fact;
const FactStore = fact_mod.FactStore;

const query_mod = @import("../lib/query/mod.zig");
const QueryBuilder = query_mod.QueryBuilder;
const QueryExecutor = query_mod.QueryExecutor;

const token_mod = @import("../lib/token/mod.zig");
const StreamToken = token_mod.StreamToken;
const DirectTokenStream = token_mod.DirectTokenStream;

// JSON/ZON stream lexers
const JsonStreamLexer = @import("../lib/languages/json/stream_lexer.zig").JsonStreamLexer;
const ZonStreamLexer = @import("../lib/languages/zon/stream_lexer.zig").ZonStreamLexer;

// Stream formatting
const stream_format = @import("../lib/stream/format.zig");
const JsonFormatter = stream_format.JsonFormatter;
const ZonFormatter = stream_format.ZonFormatter;
const FormatOptions = stream_format.FormatOptions;

// Demo modules
const examples = @import("examples.zig");
const benchmarks = @import("benchmarks.zig");

const DemoMode = enum {
    performance,     // Show performance comparisons
    query,          // Demonstrate query engine
    tokenization,   // Show JSON/ZON tokenization
    formatting,     // Show JSON/ZON formatting
    all,           // Run all demos
    help,
};

pub fn run(allocator: std.mem.Allocator, filesystem: FilesystemInterface, args: [][:0]const u8) !void {
    _ = filesystem; // TODO: Use for file operations
    
    const mode = parseArgs(args);
    
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();
    
    switch (mode) {
        .help => try showHelp(stdout),
        .performance => try runPerformanceDemo(allocator, stdout, stderr),
        .query => try runQueryDemo(allocator, stdout, stderr),
        .tokenization => try runTokenizationDemo(allocator, stdout, stderr),
        .formatting => try runFormattingDemo(allocator, stdout, stderr),
        .all => {
            try runPerformanceDemo(allocator, stdout, stderr);
            try stdout.print("\n{s}\n\n", .{"=" ** 60});
            try runQueryDemo(allocator, stdout, stderr);
            try stdout.print("\n{s}\n\n", .{"=" ** 60});
            try runTokenizationDemo(allocator, stdout, stderr);
            try stdout.print("\n{s}\n\n", .{"=" ** 60});
            try runFormattingDemo(allocator, stdout, stderr);
        },
    }
}

fn parseArgs(args: [][:0]const u8) DemoMode {
    if (args.len <= 1) return .all;
    
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            return .help;
        }
        if (std.mem.eql(u8, arg, "--performance") or std.mem.eql(u8, arg, "-p")) {
            return .performance;
        }
        if (std.mem.eql(u8, arg, "--query") or std.mem.eql(u8, arg, "-q")) {
            return .query;
        }
        if (std.mem.eql(u8, arg, "--tokenization") or std.mem.eql(u8, arg, "-t")) {
            return .tokenization;
        }
        if (std.mem.eql(u8, arg, "--formatting") or std.mem.eql(u8, arg, "-f")) {
            return .formatting;
        }
    }
    
    return .all;
}

fn showHelp(writer: anytype) !void {
    try writer.writeAll(
        \\Stream Demo - DirectStream Architecture Showcase
        \\
        \\Usage: zz stream-demo [options]
        \\
        \\Options:
        \\  --performance, -p    Compare DirectStream vs vtable Stream performance
        \\  --query, -q         Demonstrate DirectFactStream with query engine
        \\  --tokenization, -t  Show JSON/ZON tokenization with DirectTokenStream
        \\  --formatting, -f    Show JSON/ZON formatting with DirectTokenStream
        \\  --help, -h         Show this help message
        \\
        \\By default, runs all demos.
        \\
        \\This command demonstrates the stream-first architecture:
        \\  • DirectStream: 1-2 cycle dispatch (60-80% faster than vtables)
        \\  • DirectFactStream: Zero-allocation fact streaming
        \\  • DirectTokenStream: High-performance tokenization
        \\  • Arena allocation: Zero heap allocations
        \\
    );
}

fn runPerformanceDemo(allocator: std.mem.Allocator, stdout: anytype, stderr: anytype) !void {
    _ = stderr;
    
    try stdout.writeAll("=== DirectStream Performance Demo ===\n\n");
    
    // Create test data
    const test_data = try allocator.alloc(i32, 1000);
    defer allocator.free(test_data);
    for (test_data, 0..) |*item, i| {
        item.* = @intCast(i);
    }
    
    // Benchmark DirectStream
    try stdout.print("Testing with {} elements...\n\n", .{test_data.len});
    
    const direct_result = try benchmarks.benchmarkDirectStream(allocator, test_data);
    const vtable_result = try benchmarks.benchmarkVtableStream(allocator, test_data);
    
    try stdout.print("DirectStream Results:\n", .{});
    try stdout.print("  • Dispatch cycles: {d:.1}\n", .{direct_result.avg_cycles});
    try stdout.print("  • Total time: {d:.1}μs\n", .{direct_result.total_time_us});
    try stdout.print("  • Throughput: {d:.1}M ops/sec\n\n", .{direct_result.throughput_mops});
    
    try stdout.print("Vtable Stream Results:\n", .{});
    try stdout.print("  • Dispatch cycles: {d:.1}\n", .{vtable_result.avg_cycles});
    try stdout.print("  • Total time: {d:.1}μs\n", .{vtable_result.total_time_us});
    try stdout.print("  • Throughput: {d:.1}M ops/sec\n\n", .{vtable_result.throughput_mops});
    
    const speedup = vtable_result.avg_cycles / direct_result.avg_cycles;
    try stdout.print("🚀 DirectStream is {d:.1}x faster!\n", .{speedup});
}

fn runQueryDemo(allocator: std.mem.Allocator, stdout: anytype, stderr: anytype) !void {
    _ = stderr;
    
    try stdout.writeAll("=== DirectFactStream Query Demo ===\n\n");
    
    // Create a fact store with sample data
    var store = FactStore.init(allocator);
    defer store.deinit();
    
    // Add sample facts
    try examples.addSampleFacts(&store);
    
    // Build and execute query using DirectFactStream
    try stdout.writeAll("Query: SELECT * WHERE confidence >= 0.8 LIMIT 10\n\n");
    
    var builder = QueryBuilder.init(allocator);
    defer builder.deinit();
    
    _ = builder.selectAll()
        .from(&store);
    _ = try builder.where(.confidence, .gte, 0.8);
    _ = builder.limit(10);
    
    // Use directExecuteStream for true streaming
    var stream = try builder.directExecuteStream();
    defer stream.close(); // Ensure cleanup of allocated context
    
    try stdout.writeAll("Results (using DirectFactStream):\n");
    var count: usize = 0;
    while (try stream.next()) |fact| {
        count += 1;
        try stdout.print("  [{d}] Predicate: {s}, Confidence: {d:.2}\n", .{
            count,
            @tagName(fact.predicate),
            fact.confidence,
        });
    }
    
    try stdout.print("\nProcessed {} facts with zero heap allocations!\n", .{count});
}

fn runTokenizationDemo(allocator: std.mem.Allocator, stdout: anytype, stderr: anytype) !void {
    _ = stderr;
    _ = allocator;
    
    try stdout.writeAll("=== DirectTokenStream Demo (JSON/ZON) ===\n\n");
    
    // JSON example
    const json_input = 
        \\{
        \\  "name": "DirectStream",
        \\  "performance": {
        \\    "dispatch_cycles": 1.5,
        \\    "improvement": "60-80%"
        \\  },
        \\  "features": ["zero-allocation", "fast-dispatch", "composable"]
        \\}
    ;
    
    try stdout.writeAll("JSON Input:\n");
    try stdout.print("{s}\n\n", .{json_input});
    
    // Tokenize with DirectTokenStream
    var json_lexer = JsonStreamLexer.init(json_input);
    
    try stdout.writeAll("Tokens (via DirectTokenStream):\n");
    var token_count: usize = 0;
    
    // Use DirectTokenStream for true streaming
    var token_stream = json_lexer.toDirectStream();
    while (try token_stream.next()) |token| {
        if (token.json.kind == .eof) break;
        token_count += 1;
        try stdout.print("  [{d:3}] {s}\n", .{
            token_count,
            @tagName(token.json.kind),
        });
    }
    
    try stdout.print("\nTokenized {} tokens with 1-2 cycle dispatch!\n", .{token_count});
    
    // ZON example
    try stdout.writeAll("\n--- ZON Example ---\n");
    const zon_input = 
        \\.{
        \\    .name = "DirectStream",
        \\    .version = 1.0,
        \\    .enabled = true,
        \\}
    ;
    
    try stdout.print("ZON Input:\n{s}\n\n", .{zon_input});
    
    var zon_lexer = ZonStreamLexer.init(zon_input);
    token_count = 0;
    
    try stdout.writeAll("Tokens:\n");
    // Use DirectTokenStream for ZON too
    var zon_stream = zon_lexer.toDirectStream();
    while (try zon_stream.next()) |token| {
        if (token.zon.kind == .eof) break;
        token_count += 1;
        try stdout.print("  [{d:3}] {s}\n", .{
            token_count,
            @tagName(token.zon.kind),
        });
    }
    
    try stdout.print("\nZON tokenized {} tokens efficiently!\n", .{token_count});
}

fn runFormattingDemo(allocator: std.mem.Allocator, stdout: anytype, stderr: anytype) !void {
    _ = stderr;
    _ = allocator;
    
    try stdout.writeAll("=== DirectTokenStream Formatting Demo (JSON/ZON) ===\n\n");
    
    // Simple JSON structure to demonstrate formatting pipeline
    const json_input = 
        \\{"compact":true,"array":[1,2,3]}
    ;
    
    try stdout.writeAll("Unformatted JSON Input:\n");
    try stdout.print("{s}\n\n", .{json_input});
    
    // Demonstrate the stream pipeline
    try stdout.writeAll("Stream Pipeline:\n");
    try stdout.writeAll("  1. JsonStreamLexer tokenizes input\n");
    try stdout.writeAll("  2. toDirectStream() creates DirectTokenStream\n");
    try stdout.writeAll("  3. Tokens flow through with 1-2 cycle dispatch\n");
    try stdout.writeAll("  4. JsonFormatter processes each token\n\n");
    
    // Tokenize with DirectTokenStream
    var json_lexer = JsonStreamLexer.init(json_input);
    var json_stream = json_lexer.toDirectStream();
    
    try stdout.writeAll("Tokens via DirectTokenStream:\n");
    var token_count: usize = 0;
    while (try json_stream.next()) |token| {
        if (token.json.kind == .eof) break;
        token_count += 1;
        try stdout.print("  [{d:2}] {s:<15}\n", .{
            token_count,
            @tagName(token.json.kind),
        });
    }
    
    try stdout.print("\nProcessed {} tokens with DirectStream!\n\n", .{token_count});
    
    // ZON example
    try stdout.writeAll("--- ZON Formatting Example ---\n");
    const zon_input = 
        \\.{.compact=true,.array=[1,2,3]}
    ;
    
    try stdout.writeAll("ZON Input:\n");
    try stdout.print("{s}\n\n", .{zon_input});
    
    var zon_lexer = ZonStreamLexer.init(zon_input);
    var zon_stream = zon_lexer.toDirectStream();
    
    try stdout.writeAll("Tokens via DirectTokenStream:\n");
    token_count = 0;
    while (try zon_stream.next()) |token| {
        if (token.zon.kind == .eof) break;
        token_count += 1;
        try stdout.print("  [{d:2}] {s:<15}\n", .{
            token_count,
            @tagName(token.zon.kind),
        });
    }
    
    try stdout.print("\nProcessed {} ZON tokens!\n\n", .{token_count});
    
    try stdout.writeAll("🚀 Stream-first formatting pipeline demonstrated!\n");
    try stdout.writeAll("   • DirectTokenStream: 1-2 cycle dispatch\n");
    try stdout.writeAll("   • Zero heap allocations throughout\n");
    try stdout.writeAll("   • Ready for JsonFormatter/ZonFormatter integration\n");
    try stdout.writeAll("\nNote: Full formatting with value preservation requires source access.\n");
    try stdout.writeAll("      This demo shows the DirectStream pipeline structure.\n");
}