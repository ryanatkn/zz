const std = @import("std");
const testing = std.testing;

// Import ZON modules
const ZonLexer = @import("lexer.zig").ZonLexer;
const ZonToken = @import("tokens.zig").ZonToken;

// =============================================================================
// Lexer Tests
// =============================================================================

test "ZON lexer - basic tokens" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = ".{ .field = 123 }";

    var lexer = ZonLexer.init(allocator);
    defer lexer.deinit();

    const tokens = try lexer.tokenize(input);
    defer allocator.free(tokens);

    try testing.expect(tokens.len > 0);
}

test "ZON lexer - field names" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input =
        \\.{
        \\    .name = "test",
        \\    .version = "1.0.0",
        \\    .dependencies = .{},
        \\}
    ;

    var lexer = ZonLexer.init(allocator);
    defer lexer.deinit();

    const tokens = try lexer.tokenize(input);
    defer allocator.free(tokens);

    try testing.expect(tokens.len > 0);
}

test "ZON lexer - number literals" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = ".{ .int = 42, .float = 3.14, .hex = 0xFF }";

    var lexer = ZonLexer.init(allocator);
    defer lexer.deinit();

    const tokens = try lexer.tokenize(input);
    defer allocator.free(tokens);

    try testing.expect(tokens.len > 0);
}

test "ZON lexer - string literals" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = ".{ .str = \"hello world\" }";

    var lexer = ZonLexer.init(allocator);
    defer lexer.deinit();

    const tokens = try lexer.tokenize(input);
    defer allocator.free(tokens);

    try testing.expect(tokens.len > 0);
}

test "ZON lexer - escape sequences comprehensive" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const inputs = [_][]const u8{
        "\"\\n\"",
        "\"\\t\"",
        "\"\\\\\"",
        "\"\\\"\"",
        "\"\\u{1F600}\"",
    };

    for (inputs) |input| {
        var lexer = ZonLexer.init(allocator);
        defer lexer.deinit();

        const tokens = try lexer.tokenize(input);
        defer allocator.free(tokens);

        try testing.expect(tokens.len > 0);
    }
}

test "ZON lexer - invalid escape sequences" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const invalid_cases = [_][]const u8{
        "\"\\x\"", // Invalid escape
        "\"\\u{GGGG}\"", // Invalid unicode
        "\"\\u{110000}\"", // Unicode out of range
    };

    for (invalid_cases) |case| {
        var lexer = ZonLexer.init(allocator);
        defer lexer.deinit();

        // Should fail during tokenization
        _ = lexer.tokenize(case) catch {
            continue; // Expected failure
        };

        // If we get here, the lexer should have caught the error
        try testing.expect(false);
    }
}

test "ZON lexer - unterminated strings" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const invalid_cases = [_][]const u8{
        "\"unterminated",
        "\"unterminated\\",
        "\"unterminated\\n",
    };

    for (invalid_cases) |case| {
        var lexer = ZonLexer.init(allocator);
        defer lexer.deinit();

        // Should fail during tokenization
        _ = lexer.tokenize(case) catch {
            continue; // Expected failure
        };

        try testing.expect(false); // Should not reach here
    }
}

test "ZON lexer - keywords and literals" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = ".{ .bool_true = true, .bool_false = false, .nullable = null }";

    var lexer = ZonLexer.init(allocator);
    defer lexer.deinit();

    const tokens = try lexer.tokenize(input);
    defer allocator.free(tokens);

    try testing.expect(tokens.len > 0);
}

test "ZON lexer - comments" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input =
        \\.{
        \\    // Line comment
        \\    .field = "value", // Trailing comment
        \\}
    ;

    var lexer = ZonLexer.init(allocator);
    defer lexer.deinit();

    const tokens = try lexer.tokenize(input);
    defer allocator.free(tokens);

    try testing.expect(tokens.len > 0);
}

test "ZON lexer - infinite loop regression test" {
    // This test ensures that the lexer doesn't get stuck in infinite loops
    // when processing various inputs that previously caused hangs
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const test_cases = [_]struct {
        input: []const u8,
        expected_min_tokens: usize, // Minimum tokens expected (including EOF)
        description: []const u8,
    }{
        .{ .input = ".{}", .expected_min_tokens = 3, .description = "empty struct literal" },
        .{ .input = ".{ .field = 123 }", .expected_min_tokens = 6, .description = "simple struct with field" },
        .{ .input = ".{ 1, 2, 3 }", .expected_min_tokens = 8, .description = "simple array" },
        .{ .input = "42", .expected_min_tokens = 2, .description = "single number" },
        .{ .input = "\"test\"", .expected_min_tokens = 2, .description = "single string" },
        .{ .input = "true", .expected_min_tokens = 2, .description = "boolean true" },
        .{ .input = "false", .expected_min_tokens = 2, .description = "boolean false" },
        .{ .input = "null", .expected_min_tokens = 2, .description = "null value" },
        .{ .input = "@import(\"std\")", .expected_min_tokens = 5, .description = "builtin function" },
        .{ .input = ".{ .name = \"zz\", .version = \"1.0.0\", .dependencies = .{} }", .expected_min_tokens = 15, .description = "nested ZON structure" },
    };

    for (test_cases) |case| {
        var lexer = ZonLexer.init(allocator);
        defer lexer.deinit();

        // This should complete quickly without hanging
        const tokens = try lexer.batchTokenize(allocator, case.input);
        defer allocator.free(tokens);

        // Verify we got reasonable number of tokens
        try testing.expect(tokens.len >= case.expected_min_tokens);

        // Verify the last token is always EOF
        const token_mod = @import("../../token/mod.zig");
        try testing.expectEqual(token_mod.TokenKind.eof, tokens[tokens.len - 1].kind);

        // Verify EOF token position is at end of input
        try testing.expectEqual(@as(u32, @intCast(case.input.len)), tokens[tokens.len - 1].span.start);
        try testing.expectEqual(@as(u32, @intCast(case.input.len)), tokens[tokens.len - 1].span.end);
    }
}
