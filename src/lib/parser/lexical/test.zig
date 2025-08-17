const std = @import("std");
const testing = std.testing;

// Import all lexical components
const lexical = @import("mod.zig");
const StreamingLexer = @import("tokenizer.zig").StreamingLexer;
const Scanner = @import("scanner.zig").Scanner;
const BracketTracker = @import("brackets.zig").BracketTracker;
const Buffer = @import("buffer.zig").Buffer;

// Import foundation types
const Span = @import("../foundation/types/span.zig").Span;
const Token = @import("../foundation/types/token.zig").Token;
const TokenKind = @import("../foundation/types/predicate.zig").TokenKind;

// Integration tests for the complete lexical layer
test "lexical layer integration" {
    const config = lexical.LexerConfig.forLanguage(.zig);
    var lexer = try StreamingLexer.init(testing.allocator, config);
    defer lexer.deinit();
    
    const source = 
        \\fn main() {
        \\    const x = 42;
        \\    return x;
        \\}
    ;
    
    try lexer.setSource(source);
    
    const span = Span.init(0, source.len);
    const tokens = try lexer.tokenizeRange(source, span);
    defer testing.allocator.free(tokens);
    
    try testing.expect(tokens.len > 0);
    
    // Check that we have some expected tokens
    var found_fn = false;
    var found_main = false;
    var found_const = false;
    
    for (tokens) |token| {
        if (std.mem.eql(u8, token.text, "fn")) {
            found_fn = true;
        } else if (std.mem.eql(u8, token.text, "main")) {
            found_main = true;
        } else if (std.mem.eql(u8, token.text, "const")) {
            found_const = true;
        }
    }
    
    try testing.expect(found_fn);
    try testing.expect(found_main);
    try testing.expect(found_const);
}

test "lexical bracket tracking integration" {
    const config = lexical.LexerConfig.forLanguage(.zig);
    var lexer = try StreamingLexer.init(testing.allocator, config);
    defer lexer.deinit();
    
    const source = "fn test() { if (true) { return; } }";
    try lexer.setSource(source);
    
    const span = Span.init(0, source.len);
    const tokens = try lexer.tokenizeRange(source, span);
    defer testing.allocator.free(tokens);
    
    // Check bracket tracking
    const outer_brace_pos = std.mem.indexOf(u8, source, "{").?;
    const matching_pos = lexer.findBracketPair(outer_brace_pos);
    try testing.expect(matching_pos != null);
    
    // The matching position should be the last '}'
    const expected_pos = std.mem.lastIndexOf(u8, source, "}").?;
    try testing.expectEqual(@as(?usize, expected_pos), matching_pos);
}

test "lexical incremental editing" {
    const config = lexical.LexerConfig.forLanguage(.zig);
    var lexer = try StreamingLexer.init(testing.allocator, config);
    defer lexer.deinit();
    
    const initial_source = "const x = 10;";
    try lexer.setSource(initial_source);
    
    // Initial tokenization
    const span = Span.init(0, initial_source.len);
    const tokens = try lexer.tokenizeRange(initial_source, span);
    defer testing.allocator.free(tokens);
    
    const initial_count = tokens.len;
    try testing.expect(initial_count > 0);
    
    // Apply an edit: change "10" to "20"
    const edit_range = Span.init(10, 12); // Position of "10"
    const edit = lexical.Edit.init(edit_range, "20", 1);
    
    var delta = try lexer.processEdit(edit);
    defer delta.deinit(testing.allocator);
    
    // Verify the delta has the expected structure
    try testing.expect(delta.added.len > 0 or delta.removed.len > 0);
    try testing.expectEqual(@as(u32, 1), delta.generation);
}

test "lexical viewport performance simulation" {
    const config = lexical.LexerConfig.forLanguage(.zig);
    var lexer = try StreamingLexer.init(testing.allocator, config);
    defer lexer.deinit();
    
    // Create a larger source file to test viewport performance
    var source_builder = std.ArrayList(u8).init(testing.allocator);
    defer source_builder.deinit();
    
    // Generate 100 lines of code
    for (0..100) |i| {
        try source_builder.writer().print("const var{d} = {d};\n", .{ i, i });
    }
    
    const source = source_builder.items;
    try lexer.setSource(source);
    
    // Simulate viewport tokenization (first 1000 characters)
    const viewport_size = @min(1000, source.len);
    const viewport = Span.init(0, viewport_size);
    
    const timer = std.time.nanoTimestamp();
    const tokens = try lexer.tokenizeViewport(viewport);
    const elapsed: u64 = @intCast(std.time.nanoTimestamp() - timer);
    
    defer testing.allocator.free(tokens);
    
    try testing.expect(tokens.len > 0);
    
    const elapsed_us = @as(f64, @floatFromInt(elapsed)) / 1000.0;
    std.debug.print("Viewport tokenization ({d} chars): {d:.2} μs\n", .{ viewport_size, elapsed_us });
    
    // This is aspirational - actual performance may vary
    // The goal is <100μs for a viewport
}

test "lexical language detection" {
    try testing.expectEqual(lexical.Language.zig, lexical.Language.fromExtension(".zig"));
    try testing.expectEqual(lexical.Language.typescript, lexical.Language.fromExtension(".ts"));
    try testing.expectEqual(lexical.Language.json, lexical.Language.fromExtension(".json"));
    try testing.expectEqual(lexical.Language.css, lexical.Language.fromExtension(".css"));
    try testing.expectEqual(lexical.Language.html, lexical.Language.fromExtension(".html"));
    try testing.expectEqual(lexical.Language.html, lexical.Language.fromExtension(".htm"));
    try testing.expectEqual(lexical.Language.generic, lexical.Language.fromExtension(".xyz"));
}

test "lexical configuration" {
    const zig_config = lexical.LexerConfig.forLanguage(.zig);
    try testing.expectEqual(lexical.Language.zig, zig_config.language);
    try testing.expect(!zig_config.include_trivia);
    try testing.expect(zig_config.track_brackets);
    
    const trivia_config = zig_config.withTrivia();
    try testing.expect(trivia_config.include_trivia);
}

test "lexical utility functions" {
    // Test convenience functions
    try testing.expect(lexical.isBracket('('));
    try testing.expect(lexical.isBracket(')'));
    try testing.expect(!lexical.isBracket('a'));
    
    const bracket_type = lexical.getBracketType('(');
    try testing.expect(bracket_type != null);
    try testing.expectEqual(@import("../foundation/types/token.zig").DelimiterType.open_paren, bracket_type.?);
}

test "lexical timer and stats" {
    const timer = lexical.LexerTimer.start();
    
    // Simulate some work
    var sum: u64 = 0;
    for (0..1000) |i| {
        sum += i;
    }
    
    const elapsed_ns = timer.elapsedNs();
    const elapsed_us = timer.elapsedUs();
    
    try testing.expect(elapsed_ns > 0);
    try testing.expect(elapsed_us >= 0);
    
    // Prevent optimization
    std.testing.expect(sum > 0) catch {};
    
    // Test performance targets (these are aspirational)
    // try testing.expect(timer.checkEditTarget()); // <10μs
}

test "lexical complete workflow" {
    // Test a complete workflow: create lexer, tokenize, edit, retokenize
    const config = lexical.LexerConfig.forLanguage(.zig).withTrivia();
    var lexer = try StreamingLexer.init(testing.allocator, config);
    defer lexer.deinit();
    
    // Step 1: Initial tokenization
    const source = "const x = 42;";
    try lexer.setSource(source);
    
    const span = Span.init(0, source.len);
    const tokens = try lexer.tokenizeRange(source, span);
    defer testing.allocator.free(tokens);
    
    const initial_stats = lexer.getStats();
    try testing.expect(initial_stats.tokens_processed > 0);
    
    // Step 2: Find brackets (none in this simple example)
    const bracket_pair = lexer.findBracketPair(0);
    try testing.expectEqual(@as(?usize, null), bracket_pair);
    
    // Step 3: Apply edit
    const edit_range = Span.init(10, 12); // "42"
    const edit = lexical.Edit.init(edit_range, "100", 1);
    
    var delta = try lexer.processEdit(edit);
    defer delta.deinit(testing.allocator);
    
    // Step 4: Verify final state
    const final_stats = lexer.getStats();
    try testing.expect(final_stats.edits_processed > 0);
    try testing.expectEqual(@as(u32, 1), delta.generation);
    
    std.debug.print("Lexical workflow complete: {} tokens processed\n", .{final_stats.tokens_processed});
}