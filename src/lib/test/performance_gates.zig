/// Performance regression gates for language implementations
/// 
/// These tests ensure that performance improvements are maintained and
/// regressions are caught early in the development process.

const std = @import("std");
const testing = std.testing;
const TokenIterator = @import("../transform/streaming/token_iterator.zig").TokenIterator;
const Context = @import("../transform/transform.zig").Context;

/// Performance thresholds - these should not regress
pub const PerformanceThresholds = struct {
    /// TokenIterator tokenizeSimple() must complete 10KB in under 10ms
    pub const tokenize_simple_10kb_ms: u64 = 10;
    
    /// Real lexers must complete 10KB in under 10ms  
    pub const lexer_10kb_ms: u64 = 10;
    
    /// Parsers must complete 10KB worth of tokens in under 50ms
    pub const parser_10kb_ms: u64 = 50;
    
    /// TokenIterator streaming must use less than 100KB memory for 1MB input
    pub const streaming_memory_1mb_kb: u64 = 100;
};

// Test TokenIterator performance with fallback tokenization
test "TokenIterator tokenizeSimple performance gate" {
    const input = generateTestInput(10 * 1024); // 10KB
    defer testing.allocator.free(input);
    
    var context = Context.init(testing.allocator);
    defer context.deinit();
    
    var timer = try std.time.Timer.start();
    
    var iterator = TokenIterator.init(testing.allocator, input, &context, null);
    defer iterator.deinit();
    
    // Force tokenizeSimple by using null lexer
    var token_count: usize = 0;
    while (try iterator.next()) |_| {
        token_count += 1;
    }
    
    const elapsed_ns = timer.read();
    const elapsed_ms = elapsed_ns / 1_000_000;
    
    std.debug.print("TokenIterator tokenizeSimple: {}ms for 10KB ({} tokens)\n", .{ elapsed_ms, token_count });
    
    try testing.expect(elapsed_ms <= PerformanceThresholds.tokenize_simple_10kb_ms);
    try testing.expect(token_count > 0);
}

/// Test JSON lexer performance
test "JSON lexer performance gate" {
    const JsonLexer = @import("../languages/json/lexer.zig").JsonLexer;
    
    const input = generateJsonInput(10 * 1024); // 10KB JSON
    defer testing.allocator.free(input);
    
    var timer = try std.time.Timer.start();
    
    var lexer = JsonLexer.init(testing.allocator, input, .{});
    defer lexer.deinit();
    
    const tokens = try lexer.tokenize();
    defer testing.allocator.free(tokens);
    
    const elapsed_ns = timer.read();
    const elapsed_ms = elapsed_ns / 1_000_000;
    
    std.debug.print("JSON lexer: {}ms for 10KB ({} tokens)\n", .{ elapsed_ms, tokens.len });
    
    try testing.expect(elapsed_ms <= PerformanceThresholds.lexer_10kb_ms);
    try testing.expect(tokens.len > 10);
    try testing.expect(tokens[tokens.len - 1].kind == .eof);
}

/// Test ZON lexer performance
test "ZON lexer performance gate" {
    const ZonLexer = @import("../languages/zon/lexer.zig").ZonLexer;
    
    const input = generateZonInput(10 * 1024); // 10KB ZON
    defer testing.allocator.free(input);
    
    var timer = try std.time.Timer.start();
    
    var lexer = ZonLexer.init(testing.allocator, input, .{});
    defer lexer.deinit();
    
    const tokens = try lexer.tokenize();
    defer testing.allocator.free(tokens);
    
    const elapsed_ns = timer.read();
    const elapsed_ms = elapsed_ns / 1_000_000;
    
    std.debug.print("ZON lexer: {}ms for 10KB ({} tokens)\n", .{ elapsed_ms, tokens.len });
    
    try testing.expect(elapsed_ms <= PerformanceThresholds.lexer_10kb_ms);
    try testing.expect(tokens.len > 10);
    try testing.expect(tokens[tokens.len - 1].kind == .eof);
}

/// Test JSON parser performance
test "JSON parser performance gate" {
    const JsonLexer = @import("../languages/json/lexer.zig").JsonLexer;
    const JsonParser = @import("../languages/json/parser.zig").JsonParser;
    
    const input = generateJsonInput(10 * 1024); // 10KB JSON
    defer testing.allocator.free(input);
    
    // First tokenize
    var lexer = JsonLexer.init(testing.allocator, input, .{});
    defer lexer.deinit();
    
    const tokens = try lexer.tokenize();
    defer testing.allocator.free(tokens);
    
    // Then parse
    var timer = try std.time.Timer.start();
    
    var parser = JsonParser.init(testing.allocator, tokens);
    defer parser.deinit();
    
    const ast = try parser.parse();
    defer ast.deinit();
    
    const elapsed_ns = timer.read();
    const elapsed_ms = elapsed_ns / 1_000_000;
    
    std.debug.print("JSON parser: {}ms for 10KB worth of tokens\n", .{elapsed_ms});
    
    try testing.expect(elapsed_ms <= PerformanceThresholds.parser_10kb_ms);
    try testing.expect(ast.root != null);
}

/// Test ZON parser performance
test "ZON parser performance gate" {
    const ZonLexer = @import("../languages/zon/lexer.zig").ZonLexer;
    const ZonParser = @import("../languages/zon/parser.zig").ZonParser;
    
    const input = generateZonInput(10 * 1024); // 10KB ZON
    defer testing.allocator.free(input);
    
    // First tokenize
    var lexer = ZonLexer.init(testing.allocator, input, .{});
    defer lexer.deinit();
    
    const tokens = try lexer.tokenize();
    defer testing.allocator.free(tokens);
    
    // Then parse
    var timer = try std.time.Timer.start();
    
    var parser = ZonParser.init(testing.allocator, tokens);
    defer parser.deinit();
    
    const ast = try parser.parse();
    defer ast.deinit();
    
    const elapsed_ns = timer.read();
    const elapsed_ms = elapsed_ns / 1_000_000;
    
    std.debug.print("ZON parser: {}ms for 10KB worth of tokens\n", .{elapsed_ms});
    
    try testing.expect(elapsed_ms <= PerformanceThresholds.parser_10kb_ms);
    try testing.expect(ast.root != null);
}

/// Test TokenIterator streaming memory usage
test "TokenIterator streaming memory gate" {
    const large_input = generateTestInput(1024 * 1024); // 1MB
    defer testing.allocator.free(large_input);
    
    var context = Context.init(testing.allocator);
    defer context.deinit();
    
    var iterator = TokenIterator.init(testing.allocator, large_input, &context, null);
    defer iterator.deinit();
    
    // Set small chunk size to maximize streaming benefit
    iterator.setChunkSize(4096); // 4KB chunks
    
    var token_count: usize = 0;
    var max_memory_usage: usize = 0;
    
    while (try iterator.next()) |_| {
        token_count += 1;
        
        const stats = iterator.getMemoryStats();
        const current_usage = stats.token_memory_bytes + stats.buffer_capacity_bytes;
        max_memory_usage = @max(max_memory_usage, current_usage);
        
        // Break if memory usage is too high (early failure detection)
        if (max_memory_usage > PerformanceThresholds.streaming_memory_1mb_kb * 1024) {
            try testing.expect(false); // Fail immediately if threshold exceeded
        }
    }
    
    const max_usage_kb = max_memory_usage / 1024;
    
    std.debug.print("TokenIterator streaming: {}KB max memory for 1MB input ({} tokens)\n", .{ max_usage_kb, token_count });
    
    try testing.expect(max_usage_kb <= PerformanceThresholds.streaming_memory_1mb_kb);
    try testing.expect(token_count > 1000); // Should have processed significant tokens
}

/// Test JSON streaming lexer performance with TokenIterator adapters
test "JSON streaming adapter performance gate" {
    const JsonLexerAdapter = @import("../transform/streaming/token_iterator.zig").JsonLexerAdapter;
    
    const input = generateJsonInput(10 * 1024); // 10KB
    defer testing.allocator.free(input);
    
    var context = Context.init(testing.allocator);
    defer context.deinit();
    
    var adapter = JsonLexerAdapter.init(.{});
    defer adapter.deinit();
    
    const lexer_interface = TokenIterator.LexerInterface.init(&adapter);
    var iterator = TokenIterator.init(testing.allocator, input, &context, lexer_interface);
    defer iterator.deinit();
    
    var timer = try std.time.Timer.start();
    
    var token_count: usize = 0;
    while (try iterator.next()) |_| {
        token_count += 1;
    }
    
    const elapsed_ns = timer.read();
    const elapsed_ms = elapsed_ns / 1_000_000;
    
    std.debug.print("JSON streaming adapter: {}ms for 10KB ({} tokens)\n", .{ elapsed_ms, token_count });
    
    try testing.expect(elapsed_ms <= PerformanceThresholds.lexer_10kb_ms);
    try testing.expect(token_count > 10);
}

/// Test ZON streaming lexer performance with TokenIterator adapters
test "ZON streaming adapter performance gate" {
    const ZonLexerAdapter = @import("../transform/streaming/token_iterator.zig").ZonLexerAdapter;
    
    const input = generateZonInput(10 * 1024); // 10KB
    defer testing.allocator.free(input);
    
    var context = Context.init(testing.allocator);
    defer context.deinit();
    
    var adapter = ZonLexerAdapter.init(.{});
    defer adapter.deinit();
    
    const lexer_interface = TokenIterator.LexerInterface.init(&adapter);
    var iterator = TokenIterator.init(testing.allocator, input, &context, lexer_interface);
    defer iterator.deinit();
    
    var timer = try std.time.Timer.start();
    
    var token_count: usize = 0;
    while (try iterator.next()) |_| {
        token_count += 1;
    }
    
    const elapsed_ns = timer.read();
    const elapsed_ms = elapsed_ns / 1_000_000;
    
    std.debug.print("ZON streaming adapter: {}ms for 10KB ({} tokens)\n", .{ elapsed_ms, token_count });
    
    try testing.expect(elapsed_ms <= PerformanceThresholds.lexer_10kb_ms);
    try testing.expect(token_count > 10);
}

// Helper functions for generating test data

fn generateTestInput(size: usize) ![]u8 {
    const input = try testing.allocator.alloc(u8, size);
    
    // Generate realistic text with tokens separated by spaces
    var pos: usize = 0;
    var word_num: usize = 0;
    
    while (pos < size - 10) { // Leave space for final word
        const word = try std.fmt.allocPrint(testing.allocator, "word{}", .{word_num});
        defer testing.allocator.free(word);
        
        const remaining = size - pos;
        const copy_len = @min(word.len, remaining);
        
        std.mem.copyForwards(u8, input[pos..pos + copy_len], word[0..copy_len]);
        pos += copy_len;
        
        if (pos < size) {
            input[pos] = ' ';
            pos += 1;
        }
        
        word_num += 1;
    }
    
    // Ensure input is valid
    while (pos < size) {
        input[pos] = ' ';
        pos += 1;
    }
    
    return input;
}

fn generateJsonInput(size: usize) ![]u8 {
    var input = std.ArrayList(u8).init(testing.allocator);
    errdefer input.deinit();
    
    try input.appendSlice("{\n  \"data\": [\n");
    
    var item_num: usize = 0;
    while (input.items.len < size - 100) { // Leave space for closing
        const item = try std.fmt.allocPrint(
            testing.allocator,
            "    {{\"id\": {}, \"name\": \"Item {}\", \"value\": {}}},\n",
            .{ item_num, item_num, item_num * 10 }
        );
        defer testing.allocator.free(item);
        
        try input.appendSlice(item);
        item_num += 1;
    }
    
    // Remove trailing comma and close
    if (input.items[input.items.len - 2] == ',') {
        input.items[input.items.len - 2] = '\n';
    }
    
    try input.appendSlice("  ],\n  \"total\": ");
    const total = try std.fmt.allocPrint(testing.allocator, "{}", .{item_num});
    defer testing.allocator.free(total);
    try input.appendSlice(total);
    try input.appendSlice("\n}");
    
    return input.toOwnedSlice();
}

fn generateZonInput(size: usize) ![]u8 {
    var input = std.ArrayList(u8).init(testing.allocator);
    errdefer input.deinit();
    
    try input.appendSlice(".{\n    .data = .{\n");
    
    var item_num: usize = 0;
    while (input.items.len < size - 100) { // Leave space for closing
        const item = try std.fmt.allocPrint(
            testing.allocator,
            "        .{{ .id = {}, .name = \"Item {}\", .value = {} }},\n",
            .{ item_num, item_num, item_num * 10 }
        );
        defer testing.allocator.free(item);
        
        try input.appendSlice(item);
        item_num += 1;
    }
    
    // Remove trailing comma and close
    if (input.items[input.items.len - 2] == ',') {
        input.items[input.items.len - 2] = '\n';
    }
    
    try input.appendSlice("    },\n    .total = ");
    const total = try std.fmt.allocPrint(testing.allocator, "{}", .{item_num});
    defer testing.allocator.free(total);
    try input.appendSlice(total);
    try input.appendSlice(",\n}");
    
    return input.toOwnedSlice();
}