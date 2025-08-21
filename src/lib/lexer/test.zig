/// Tests for lexer module
///
/// TODO: Add performance regression tests
/// TODO: Add memory leak detection tests  
/// TODO: Add fuzzing tests for robustness
/// TODO: Add concurrent access tests
const std = @import("std");
const testing = std.testing;

// Import modules to test
const LexerBridge = @import("lexer_bridge.zig").LexerBridge;
const StreamAdapter = @import("stream_adapter.zig").StreamAdapter;
const LexerRegistry = @import("registry.zig").LexerRegistry;
const LexerState = @import("state.zig").LexerState;
const AtomTable = @import("../memory/atom_table.zig").AtomTable;
const Language = @import("../core/language.zig").Language;

test "Lexer module integration" {
    // TODO: Phase 4 - This test will pass when native stream lexers are implemented
    // Currently fails due to bridge limitations
    const allocator = testing.allocator;
    
    // Create shared atom table
    var atom_table = AtomTable.init(allocator);
    defer atom_table.deinit();
    
    // Create registry
    var registry = LexerRegistry.init(allocator, &atom_table);
    defer registry.deinit();
    
    // Register languages
    try registry.registerDefaults();
    
    // Get JSON lexer
    const json_lexer = registry.getLexer(.json).?;
    
    // Tokenize some JSON
    const source = "{\"test\": [1, 2, 3]}";
    const tokens = try json_lexer.tokenize(source);
    defer allocator.free(tokens);
    
    // Create stream adapter
    var adapter = StreamAdapter.init(tokens);
    var stream = adapter.toStream();
    
    // Consume tokens
    var count: usize = 0;
    while (try stream.next()) |_| {
        count += 1;
    }
    
    try testing.expect(count > 0);
}

test "LexerBridge JSON conversion" {
    // TODO: Phase 4 - Bridge will be deleted, test will be removed
    const allocator = testing.allocator;
    
    var atom_table = AtomTable.init(allocator);
    defer atom_table.deinit();
    
    var bridge = try LexerBridge.init(allocator, .json, &atom_table);
    defer bridge.deinit();
    
    // Test various JSON constructs
    const test_cases = [_][]const u8{
        "{}",
        "[]",
        "\"string\"",
        "123",
        "true",
        "false",
        "null",
        "[1, 2, 3]",
        "{\"key\": \"value\"}",
        "{\"nested\": {\"array\": [1, 2, 3]}}",
    };
    
    for (test_cases) |source| {
        const tokens = try bridge.tokenize(source);
        defer allocator.free(tokens);
        
        try testing.expect(tokens.len > 0);
        
        // TODO: Verify specific token properties
        // TODO: Check atom table usage
    }
    
    // Check statistics
    try testing.expect(bridge.stats.tokens_converted > 0);
    try testing.expect(bridge.stats.atoms_interned > 0);
}

test "LexerBridge ZON conversion" {
    // TODO: Phase 4 - Bridge will be deleted, test will be removed  
    const allocator = testing.allocator;
    
    var atom_table = AtomTable.init(allocator);
    defer atom_table.deinit();
    
    var bridge = try LexerBridge.init(allocator, .zon, &atom_table);
    defer bridge.deinit();
    
    const source = ".{ .field = 123, .array = .{ 1, 2, 3 } }";
    const tokens = try bridge.tokenize(source);
    defer allocator.free(tokens);
    
    try testing.expect(tokens.len > 0);
}

test "StreamAdapter operations" {
    const allocator = testing.allocator;
    const StreamToken = @import("../token/stream_token.zig").StreamToken;
    const JsonToken = @import("../languages/json/stream_token.zig").JsonToken;
    const Span = @import("../span/mod.zig").Span;
    
    // Create some test tokens
    const tokens = try allocator.alloc(StreamToken, 5);
    defer allocator.free(tokens);
    
    const span = Span.init(0, 1);
    for (tokens, 0..) |*token, i| {
        token.* = StreamToken{ 
            .json = JsonToken.structural(
                span, 
                .comma, 
                @intCast(i)
            ) 
        };
    }
    
    // Test adapter
    var adapter = StreamAdapter.init(tokens);
    var stream = adapter.toStream();
    
    // Test peek doesn't advance
    const first_peek = try stream.peek();
    const second_peek = try stream.peek();
    try testing.expectEqual(first_peek, second_peek);
    
    // Test next advances
    const first = try stream.next();
    const second = try stream.next();
    
    // Both should be non-null and different
    try testing.expect(first != null);
    try testing.expect(second != null);
    
    if (first) |f| {
        if (second) |s| {
            // Can't directly compare StreamTokens, but we can check they exist
            _ = f;
            _ = s;
        }
    }
    
    // Test skip
    try stream.skip(2);
    const after_skip = try stream.next();
    try testing.expect(after_skip != null);
    
    // Should have no tokens left
    const last = try stream.next();
    try testing.expect(last == null);
}

test "LexerState operations" {
    var state = LexerState.init();
    
    // Test basic state tracking
    state.advance(10);
    try testing.expectEqual(@as(usize, 10), state.position);
    
    state.newline();
    try testing.expectEqual(@as(u32, 2), state.line);
    try testing.expectEqual(@as(u32, 1), state.column);
    
    // Test context management
    try state.enterString();
    try testing.expect(state.flags.in_string);
    try testing.expectEqual(LexerState.ContextType.string, state.currentContext());
    
    state.exitString();
    try testing.expect(!state.flags.in_string);
    try testing.expect(state.currentContext() == null);
    
    // Test depth tracking
    state.increaseDepth();
    state.increaseDepth();
    try testing.expectEqual(@as(u16, 2), state.depth);
    
    state.decreaseDepth();
    try testing.expectEqual(@as(u16, 1), state.depth);
    
    // Test statistics
    state.recordToken();
    state.recordToken();
    try testing.expectEqual(@as(u64, 2), state.stats.tokens_emitted);
    
    state.recordError();
    try testing.expect(state.flags.has_errors);
    try testing.expectEqual(@as(u32, 1), state.stats.errors_encountered);
}

test "LexerRegistry extension mapping" {
    const allocator = testing.allocator;
    
    var atom_table = AtomTable.init(allocator);
    defer atom_table.deinit();
    
    var registry = LexerRegistry.init(allocator, &atom_table);
    defer registry.deinit();
    
    try registry.registerDefaults();
    
    // Test various extensions
    const mappings = [_]struct { ext: []const u8, lang: ?Language }{
        .{ .ext = ".json", .lang = .json },
        .{ .ext = "json", .lang = .json },
        .{ .ext = ".zon", .lang = .zon },
        .{ .ext = "zon", .lang = .zon },
        .{ .ext = ".ts", .lang = .typescript },
        .{ .ext = ".tsx", .lang = .typescript },
        .{ .ext = ".unknown", .lang = null },
    };
    
    for (mappings) |mapping| {
        const lexer = registry.getLexerByExtension(mapping.ext);
        if (mapping.lang) |expected_lang| {
            if (expected_lang == .json or expected_lang == .zon) {
                try testing.expect(lexer != null);
            } else {
                // Not implemented yet
                try testing.expect(lexer == null);
            }
        } else {
            try testing.expect(lexer == null);
        }
    }
}

// TODO: Performance benchmark tests
test "BENCHMARK: Token conversion overhead" {
    // TODO: Measure old token -> StreamToken conversion time
    // TODO: Compare with direct StreamToken creation
    // TODO: Profile memory allocations
    // TODO: Measure atom table overhead
}

// TODO: Memory leak tests
test "Memory: No leaks in lexer lifecycle" {
    // TODO: Create and destroy lexers repeatedly
    // TODO: Verify all allocations are freed
    // TODO: Check atom table cleanup
}

// TODO: Concurrent access tests
test "Concurrency: Registry thread safety" {
    // TODO: Multiple threads accessing registry
    // TODO: Verify no data races
    // TODO: Test concurrent tokenization
}

// TODO: Fuzzing tests
test "Fuzzing: Malformed input handling" {
    // TODO: Feed random/malformed input
    // TODO: Verify no crashes
    // TODO: Check error recovery
}