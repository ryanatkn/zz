/// Standard test corpus for all language implementations
///
/// Provides common test cases that every language lexer/parser should handle
/// to ensure consistent behavior and quality across all language modules.
const std = @import("std");
const testing = std.testing;
// Using generic foundation types (no ast_old dependency)
const Token = @import("../token/token.zig").Token;
const TokenKind = @import("../token/mod.zig").TokenKind;
const Span = @import("../span/mod.zig").Span;

/// Standard test cases that all languages should pass
pub const StandardTestCases = struct {
    /// Empty input test - should produce only EOF token
    pub const empty_input = "";

    /// Whitespace-only input - should produce whitespace tokens (optional) + EOF
    pub const whitespace_only = "   \t\n  ";

    /// Single token tests - each language should define these
    pub const SingleTokenTests = struct {
        // Languages should override these with valid examples
        pub var string_literal: []const u8 = "\"hello\"";
        pub var number_literal: []const u8 = "123";
        pub var boolean_literal: []const u8 = "true";
        pub var null_literal: []const u8 = "null";
        pub var identifier: []const u8 = "name";
    };
};

/// Test runner for standard lexer tests
pub fn runStandardLexerTests(
    comptime LexerType: type,
    comptime createLexer: fn (std.mem.Allocator, []const u8) LexerType,
    language_tests: anytype,
) !void {
    // Test 1: Empty input
    try testEmptyInput(LexerType, createLexer);

    // Test 2: EOF token standard
    try testEOFTokenStandard(LexerType, createLexer, language_tests.simple_input);

    // Test 3: Round-trip consistency
    try testRoundTripConsistency(LexerType, createLexer, language_tests.complex_input);

    // Test 4: Performance (10KB under 10ms)
    try testPerformance(LexerType, createLexer, language_tests.large_input);
}

/// Test that empty input produces only EOF token
fn testEmptyInput(
    comptime LexerType: type,
    comptime createLexer: fn (std.mem.Allocator, []const u8) LexerType,
) !void {
    var lexer = createLexer(testing.allocator, StandardTestCases.empty_input);
    defer lexer.deinit();

    const tokens = try lexer.tokenize();
    defer testing.allocator.free(tokens);

    try testing.expect(tokens.len == 1);
    try testing.expect(tokens[0].kind == .eof);
    try testing.expect(tokens[0].text.len == 0);
    try testing.expect(tokens[0].span.start == 0);
    try testing.expect(tokens[0].span.end == 0);
}

/// Test that EOF token follows standard format
fn testEOFTokenStandard(
    comptime LexerType: type,
    comptime createLexer: fn (std.mem.Allocator, []const u8) LexerType,
    input: []const u8,
) !void {
    var lexer = createLexer(testing.allocator, input);
    defer lexer.deinit();

    const tokens = try lexer.tokenize();
    defer testing.allocator.free(tokens);

    try testing.expect(tokens.len > 0);

    const eof_token = tokens[tokens.len - 1];
    try testing.expect(eof_token.kind == .eof);
    try testing.expect(eof_token.text.len == 0);
    try testing.expect(eof_token.span.start == input.len);
    try testing.expect(eof_token.span.end == input.len);
}

/// Test that token text concatenation equals original input
fn testRoundTripConsistency(
    comptime LexerType: type,
    comptime createLexer: fn (std.mem.Allocator, []const u8) LexerType,
    input: []const u8,
) !void {
    var lexer = createLexer(testing.allocator, input);
    defer lexer.deinit();

    const tokens = try lexer.tokenize();
    defer testing.allocator.free(tokens);

    var reconstructed = std.ArrayList(u8).init(testing.allocator);
    defer reconstructed.deinit();

    // Concatenate all tokens except EOF
    for (tokens[0 .. tokens.len - 1]) |token| {
        try reconstructed.appendSlice(token.text);
    }

    try testing.expectEqualStrings(input, reconstructed.items);
}

/// Test that lexer completes 10KB input in under 10ms
fn testPerformance(
    comptime LexerType: type,
    comptime createLexer: fn (std.mem.Allocator, []const u8) LexerType,
    large_input: []const u8,
) !void {
    try testing.expect(large_input.len >= 10 * 1024); // At least 10KB

    var timer = try std.time.Timer.start();

    var lexer = createLexer(testing.allocator, large_input);
    defer lexer.deinit();

    const tokens = try lexer.tokenize();
    defer testing.allocator.free(tokens);

    const elapsed_ns = timer.read();
    const elapsed_ms = elapsed_ns / 1_000_000;

    // Should complete in under 10ms
    try testing.expect(elapsed_ms < 10);

    // Verify we got some tokens
    try testing.expect(tokens.len > 10);

    // Verify EOF is present
    try testing.expect(tokens[tokens.len - 1].kind == .eof);
}

/// Language-specific test data structure
pub fn LanguageTestData(comptime T: type) type {
    return struct {
        simple_input: []const u8,
        complex_input: []const u8,
        large_input: []const u8,

        // Token-specific tests
        string_literals: []const []const u8,
        number_literals: []const []const u8,
        boolean_literals: []const []const u8,
        null_literals: []const []const u8,
        identifiers: []const []const u8,

        // Expected token counts for validation
        simple_token_count: usize,
        complex_token_count: usize,
    };
}

/// JSON test data
pub const json_test_data = LanguageTestData(void){
    .simple_input = "{\"name\": \"Alice\"}",
    .complex_input =
    \\{
    \\  "name": "Alice",
    \\  "age": 30,
    \\  "active": true,
    \\  "scores": [85, 90, 78],
    \\  "address": {
    \\    "street": "123 Main St",
    \\    "city": "Springfield"
    \\  },
    \\  "metadata": null
    \\}
    ,
    .large_input = generateLargeJsonInput(),

    .string_literals = &[_][]const u8{ "\"hello\"", "\"world\"", "\"test string\"" },
    .number_literals = &[_][]const u8{ "42", "3.14", "0", "-17", "1e10" },
    .boolean_literals = &[_][]const u8{ "true", "false" },
    .null_literals = &[_][]const u8{"null"},
    .identifiers = &[_][]const u8{}, // JSON has no bare identifiers

    .simple_token_count = 7, // Approximate count for simple_input
    .complex_token_count = 35, // Approximate count for complex_input
};

/// ZON test data
pub const zon_test_data = LanguageTestData(void){
    .simple_input = ".{ .name = \"Alice\" }",
    .complex_input =
    \\.{
    \\    .name = "Alice",
    \\    .age = 30,
    \\    .active = true,
    \\    .scores = .{85, 90, 78},
    \\    .address = .{
    \\        .street = "123 Main St",
    \\        .city = "Springfield",
    \\    },
    \\    .metadata = null,
    \\}
    ,
    .large_input = generateLargeZonInput(),

    .string_literals = &[_][]const u8{ "\"hello\"", "\"world\"", "'c'" },
    .number_literals = &[_][]const u8{ "42", "3.14", "0xFF", "-17" },
    .boolean_literals = &[_][]const u8{ "true", "false" },
    .null_literals = &[_][]const u8{"null"},
    .identifiers = &[_][]const u8{ "name", "age", "address" },

    .simple_token_count = 9, // Approximate count for simple_input
    .complex_token_count = 45, // Approximate count for complex_input
};

/// Generate large JSON input (>10KB) for performance testing
fn generateLargeJsonInput() []const u8 {
    // This would ideally be generated at comptime or runtime
    // For now, return a reasonable large JSON structure
    return 
    \\{
    \\  "data": [
++ "    {\"id\": 1, \"name\": \"Item 1\", \"value\": 100}," ** 200 ++
    \\    {"id": 1000, "name": "Final Item", "value": 999}
    \\  ],
    \\  "metadata": {
    \\    "total": 1000,
    \\    "timestamp": "2025-08-19T12:00:00Z",
    \\    "version": "1.0.0"
    \\  }
    \\}
    ;
}

/// Generate large ZON input (>10KB) for performance testing
fn generateLargeZonInput() []const u8 {
    return 
    \\.{
    \\    .data = .{
++ "        .{ .id = 1, .name = \"Item 1\", .value = 100 }," ** 200 ++
    \\        .{ .id = 1000, .name = "Final Item", .value = 999 },
    \\    },
    \\    .metadata = .{
    \\        .total = 1000,
    \\        .timestamp = "2025-08-19T12:00:00Z",
    \\        .version = "1.0.0",
    \\    },
    \\}
    ;
}

/// Standard parser tests that all languages should pass
pub fn runStandardParserTests(
    comptime ParserType: type,
    comptime createParser: fn (std.mem.Allocator, []const Token) ParserType,
    tokens: []const Token,
) !void {
    // Test 1: Empty token list (only EOF)
    const eof_tokens = &[_]Token{Token.simple(Span.init(0, 0), .eof, "", 0)};
    try testEmptyParse(ParserType, createParser, eof_tokens);

    // Test 2: Basic parsing
    try testBasicParse(ParserType, createParser, tokens);
}

fn testEmptyParse(
    comptime ParserType: type,
    comptime createParser: fn (std.mem.Allocator, []const Token) ParserType,
    eof_tokens: []const Token,
) !void {
    var parser = createParser(testing.allocator, eof_tokens);
    defer parser.deinit();

    const ast = try parser.parse();
    defer ast.deinit();

    try testing.expect(ast.root != null);
}

fn testBasicParse(
    comptime ParserType: type,
    comptime createParser: fn (std.mem.Allocator, []const Token) ParserType,
    tokens: []const Token,
) !void {
    var parser = createParser(testing.allocator, tokens);
    defer parser.deinit();

    const ast = try parser.parse();
    defer ast.deinit();

    try testing.expect(ast.root != null);
    // Language-specific validation would go here
}

/// Utility function to run all standard tests for a language
pub fn runAllStandardTests(
    comptime LexerType: type,
    comptime ParserType: type,
    comptime createLexer: fn (std.mem.Allocator, []const u8) LexerType,
    comptime createParser: fn (std.mem.Allocator, []const Token) ParserType,
    test_data: anytype,
) !void {
    // Run lexer tests
    try runStandardLexerTests(LexerType, createLexer, test_data);

    // Generate tokens for parser tests
    var lexer = createLexer(testing.allocator, test_data.simple_input);
    defer lexer.deinit();

    const tokens = try lexer.tokenize();
    defer testing.allocator.free(tokens);

    // Run parser tests
    try runStandardParserTests(ParserType, createParser, tokens);
}
