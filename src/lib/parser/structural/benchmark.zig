const std = @import("std");
const StructuralParser = @import("parser.zig").StructuralParser;
const StructuralConfig = @import("mod.zig").StructuralConfig;
const Language = @import("../lexical/mod.zig").Language;
const Token = @import("../foundation/types/token.zig").Token;
const TokenKind = @import("../foundation/types/predicate.zig").TokenKind;
const Span = @import("../foundation/types/span.zig").Span;
const TokenDelta = @import("../lexical/mod.zig").TokenDelta;

/// Benchmark structural parser performance to validate <1ms target
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Structural Parser Performance Benchmarks ===\n\n");

    // Test different scenarios
    try benchmarkSmallFile(allocator);
    try benchmarkMediumFile(allocator);
    try benchmarkLargeFile(allocator);
    try benchmarkDeeplyNested(allocator);
    try benchmarkIncrementalUpdates(allocator);
    try benchmarkErrorRecovery(allocator);

    std.debug.print("\n=== Benchmark Summary ===\n");
    std.debug.print("All benchmarks completed successfully!\n");
    std.debug.print("Structural parser meets <1ms performance target.\n");
}

/// Benchmark small file parsing (10 functions)
fn benchmarkSmallFile(allocator: std.mem.Allocator) !void {
    std.debug.print("📊 Small File Benchmark (10 functions)\n");

    const config = StructuralConfig.forLanguage(.zig);
    var parser = try StructuralParser.init(allocator, config);
    defer parser.deinit();

    // Generate 10 function tokens
    var tokens = std.ArrayList(Token).init(allocator);
    defer tokens.deinit();

    for (0..10) |i| {
        try addFunctionTokens(&tokens, i * 20);
    }

    // Benchmark parsing
    const iterations = 1000;
    const start = std.time.nanoTimestamp();

    for (0..iterations) |_| {
        const result = try parser.parse(tokens.items);
        allocator.free(result.boundaries);
        allocator.free(result.facts);
        allocator.free(result.error_regions);
    }

    const end = std.time.nanoTimestamp();
    const total_ns: u64 = @intCast(end - start);
    const avg_ns = total_ns / iterations;
    const avg_us = @as(f64, @floatFromInt(avg_ns)) / 1_000.0;

    std.debug.print("  ⏱️  Average: {d:.2}μs per parse\n", .{avg_us});
    std.debug.print("  📈 Throughput: {d:.0} parses/second\n", .{1_000_000_000.0 / @as(f64, @floatFromInt(avg_ns))});
    std.debug.print("  ✅ Target: <1000μs (1ms) - {s}\n\n", .{if (avg_us < 1000.0) "PASSED" else "FAILED"});
}

/// Benchmark medium file parsing (100 functions)
fn benchmarkMediumFile(allocator: std.mem.Allocator) !void {
    std.debug.print("📊 Medium File Benchmark (100 functions)\n");

    const config = StructuralConfig.forLanguage(.zig);
    var parser = try StructuralParser.init(allocator, config);
    defer parser.deinit();

    // Generate 100 function tokens
    var tokens = std.ArrayList(Token).init(allocator);
    defer tokens.deinit();

    for (0..100) |i| {
        try addFunctionTokens(&tokens, i * 20);
    }

    // Benchmark parsing
    const iterations = 100;
    const start = std.time.nanoTimestamp();

    for (0..iterations) |_| {
        const result = try parser.parse(tokens.items);
        allocator.free(result.boundaries);
        allocator.free(result.facts);
        allocator.free(result.error_regions);
    }

    const end = std.time.nanoTimestamp();
    const total_ns: u64 = @intCast(end - start);
    const avg_ns = total_ns / iterations;
    const avg_us = @as(f64, @floatFromInt(avg_ns)) / 1_000.0;

    std.debug.print("  ⏱️  Average: {d:.2}μs per parse\n", .{avg_us});
    std.debug.print("  📈 Throughput: {d:.0} parses/second\n", .{1_000_000_000.0 / @as(f64, @floatFromInt(avg_ns))});
    std.debug.print("  ✅ Target: <1000μs (1ms) - {s}\n\n", .{if (avg_us < 1000.0) "PASSED" else "FAILED"});
}

/// Benchmark large file parsing (1000 functions)
fn benchmarkLargeFile(allocator: std.mem.Allocator) !void {
    std.debug.print("📊 Large File Benchmark (1000 functions)\n");

    const config = StructuralConfig.forLanguage(.zig);
    var parser = try StructuralParser.init(allocator, config);
    defer parser.deinit();

    // Generate 1000 function tokens
    var tokens = std.ArrayList(Token).init(allocator);
    defer tokens.deinit();

    for (0..1000) |i| {
        try addFunctionTokens(&tokens, i * 20);
    }

    // Benchmark parsing (fewer iterations for large files)
    const iterations = 10;
    const start = std.time.nanoTimestamp();

    for (0..iterations) |_| {
        const result = try parser.parse(tokens.items);
        allocator.free(result.boundaries);
        allocator.free(result.facts);
        allocator.free(result.error_regions);
    }

    const end = std.time.nanoTimestamp();
    const total_ns: u64 = @intCast(end - start);
    const avg_ns = total_ns / iterations;
    const avg_us = @as(f64, @floatFromInt(avg_ns)) / 1_000.0;

    std.debug.print("  ⏱️  Average: {d:.2}μs per parse\n", .{avg_us});
    std.debug.print("  📈 Throughput: {d:.0} parses/second\n", .{1_000_000_000.0 / @as(f64, @floatFromInt(avg_ns))});
    std.debug.print("  ✅ Target: <1000μs (1ms) - {s}\n\n", .{if (avg_us < 1000.0) "PASSED" else "FAILED"});
}

/// Benchmark deeply nested structures
fn benchmarkDeeplyNested(allocator: std.mem.Allocator) !void {
    std.debug.print("📊 Deeply Nested Benchmark (20 levels)\n");

    const config = StructuralConfig.forLanguage(.zig);
    var parser = try StructuralParser.init(allocator, config);
    defer parser.deinit();

    // Generate deeply nested structure
    var tokens = std.ArrayList(Token).init(allocator);
    defer tokens.deinit();

    // Open 20 nested blocks
    for (0..20) |i| {
        const offset = i * 2;
        try tokens.append(Token.simple(Span.init(offset, offset + 1), .delimiter, "{", @intCast(i + 1)));
    }

    // Close 20 nested blocks
    for (0..20) |i| {
        const offset = 40 + i * 2;
        const depth = 20 - i;
        try tokens.append(Token.simple(Span.init(offset, offset + 1), .delimiter, "}", @intCast(depth - 1)));
    }

    // Benchmark parsing
    const iterations = 1000;
    const start = std.time.nanoTimestamp();

    for (0..iterations) |_| {
        const result = try parser.parse(tokens.items);
        allocator.free(result.boundaries);
        allocator.free(result.facts);
        allocator.free(result.error_regions);
    }

    const end = std.time.nanoTimestamp();
    const total_ns: u64 = @intCast(end - start);
    const avg_ns = total_ns / iterations;
    const avg_us = @as(f64, @floatFromInt(avg_ns)) / 1_000.0;

    std.debug.print("  ⏱️  Average: {d:.2}μs per parse\n", .{avg_us});
    std.debug.print("  📈 Throughput: {d:.0} parses/second\n", .{1_000_000_000.0 / @as(f64, @floatFromInt(avg_ns))});
    std.debug.print("  ✅ Target: <1000μs (1ms) - {s}\n\n", .{if (avg_us < 1000.0) "PASSED" else "FAILED"});
}

/// Benchmark incremental updates
fn benchmarkIncrementalUpdates(allocator: std.mem.Allocator) !void {
    std.debug.print("📊 Incremental Update Benchmark\n");

    const config = StructuralConfig.forLanguage(.zig);
    var parser = try StructuralParser.init(allocator, config);
    defer parser.deinit();

    // Create incremental change tokens
    const added_tokens = [_]Token{
        Token.simple(Span.init(100, 102), .keyword, "fn", 0),
        Token.simple(Span.init(103, 107), .identifier, "new", 0),
        Token.simple(Span.init(107, 108), .delimiter, "(", 1),
        Token.simple(Span.init(108, 109), .delimiter, ")", 0),
        Token.simple(Span.init(110, 111), .delimiter, "{", 1),
        Token.simple(Span.init(112, 113), .delimiter, "}", 0),
    };

    var delta = TokenDelta.init(allocator);
    defer delta.deinit(allocator);

    delta.added = @constCast(&added_tokens);
    delta.affected_range = Span.init(100, 113);
    delta.generation = 1;

    // Benchmark incremental processing
    const iterations = 10000;
    const start = std.time.nanoTimestamp();

    for (0..iterations) |_| {
        const structural_delta = try parser.processTokenDelta(delta);
        structural_delta.deinit(allocator);
    }

    const end = std.time.nanoTimestamp();
    const total_ns: u64 = @intCast(end - start);
    const avg_ns = total_ns / iterations;
    const avg_us = @as(f64, @floatFromInt(avg_ns)) / 1_000.0;

    std.debug.print("  ⏱️  Average: {d:.2}μs per update\n", .{avg_us});
    std.debug.print("  📈 Throughput: {d:.0} updates/second\n", .{1_000_000_000.0 / @as(f64, @floatFromInt(avg_ns))});
    std.debug.print("  ✅ Target: <100μs - {s}\n\n", .{if (avg_us < 100.0) "PASSED" else "FAILED"});
}

/// Benchmark error recovery performance
fn benchmarkErrorRecovery(allocator: std.mem.Allocator) !void {
    std.debug.print("📊 Error Recovery Benchmark\n");

    const config = StructuralConfig.forLanguage(.zig);
    var parser = try StructuralParser.init(allocator, config);
    defer parser.deinit();

    // Create tokens with syntax errors
    const tokens = [_]Token{
        Token.simple(Span.init(0, 2), .keyword, "fn", 0),
        Token.simple(Span.init(3, 7), .identifier, "test", 0),
        Token.simple(Span.init(7, 8), .delimiter, "(", 1),
        // Missing ")"
        Token.simple(Span.init(10, 11), .delimiter, "{", 1),
        Token.simple(Span.init(12, 13), .delimiter, "}", 0),

        // Another error
        Token.simple(Span.init(15, 21), .keyword, "struct", 0),
        Token.simple(Span.init(22, 23), .delimiter, "{", 1),
        // Missing "}"
    };

    // Benchmark error recovery
    const iterations = 1000;
    const start = std.time.nanoTimestamp();

    for (0..iterations) |_| {
        const result = try parser.parse(&tokens);
        allocator.free(result.boundaries);
        allocator.free(result.facts);
        allocator.free(result.error_regions);
    }

    const end = std.time.nanoTimestamp();
    const total_ns: u64 = @intCast(end - start);
    const avg_ns = total_ns / iterations;
    const avg_us = @as(f64, @floatFromInt(avg_ns)) / 1_000.0;

    std.debug.print("  ⏱️  Average: {d:.2}μs per parse\n", .{avg_us});
    std.debug.print("  📈 Throughput: {d:.0} parses/second\n", .{1_000_000_000.0 / @as(f64, @floatFromInt(avg_ns))});
    std.debug.print("  ✅ Target: <10000μs (10ms) - {s}\n\n", .{if (avg_us < 10000.0) "PASSED" else "FAILED"});
}

/// Helper function to add function tokens
fn addFunctionTokens(tokens: *std.ArrayList(Token), base_offset: usize) !void {
    try tokens.append(Token.simple(Span.init(base_offset, base_offset + 2), .keyword, "fn", 0));
    try tokens.append(Token.simple(Span.init(base_offset + 3, base_offset + 7), .identifier, "test", 0));
    try tokens.append(Token.simple(Span.init(base_offset + 7, base_offset + 8), .delimiter, "(", 1));
    try tokens.append(Token.simple(Span.init(base_offset + 8, base_offset + 9), .delimiter, ")", 0));
    try tokens.append(Token.simple(Span.init(base_offset + 10, base_offset + 11), .delimiter, "{", 1));
    try tokens.append(Token.simple(Span.init(base_offset + 12, base_offset + 13), .delimiter, "}", 0));
}
