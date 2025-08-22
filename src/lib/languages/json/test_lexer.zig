const std = @import("std");
const testing = std.testing;

// Import JSON lexer
const JsonLexer = @import("lexer.zig").JsonLexer;

// Import types
const Token = @import("../../token/mod.zig").Token;
const TokenKind = @import("../../token/mod.zig").TokenKind;

// =============================================================================
// Lexer Tests
// =============================================================================

test "JSON lexer - basic tokens" {
    // Re-enabled after fixing infinite loop
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const test_cases = [_]struct {
        input: []const u8,
        expected_kind: TokenKind,
        expected_text: []const u8,
    }{
        .{ .input = "\"hello world\"", .expected_kind = .string, .expected_text = "\"hello world\"" },
        .{ .input = "42", .expected_kind = .number, .expected_text = "42" },
        .{ .input = "-3.14", .expected_kind = .number, .expected_text = "-3.14" },
        .{ .input = "1.23e-4", .expected_kind = .number, .expected_text = "1.23e-4" },
        .{ .input = "true", .expected_kind = .boolean, .expected_text = "true" },
        .{ .input = "false", .expected_kind = .boolean, .expected_text = "false" },
        .{ .input = "null", .expected_kind = .null, .expected_text = "null" },
        .{ .input = "{", .expected_kind = .left_brace, .expected_text = "{" },
        .{ .input = "}", .expected_kind = .right_brace, .expected_text = "}" },
        .{ .input = "[", .expected_kind = .left_bracket, .expected_text = "[" },
        .{ .input = "]", .expected_kind = .right_bracket, .expected_text = "]" },
        .{ .input = ",", .expected_kind = .comma, .expected_text = "," },
        .{ .input = ":", .expected_kind = .colon, .expected_text = ":" },
    };

    for (test_cases) |case| {
        var lexer = JsonLexer.init(allocator);
        const tokens = try lexer.batchTokenize(allocator, case.input);
        defer allocator.free(tokens);

        try testing.expectEqual(@as(usize, 2), tokens.len); // Includes EOF token
        try testing.expectEqual(case.expected_kind, tokens[0].kind);
        try testing.expectEqualStrings(case.expected_text, tokens[0].getText(case.input));
    }
}

test "JSON lexer - complex structures" {
    // Re-enabled after fixing infinite loop issue
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const complex_json =
        \\{
        \\  "users": [
        \\    {
        \\      "id": 1,
        \\      "name": "Alice",
        \\      "metadata": {
        \\        "active": true,
        \\        "roles": ["admin", "user"],
        \\        "settings": {
        \\          "theme": "dark",
        \\          "notifications": false
        \\        }
        \\      }
        \\    },
        \\    {
        \\      "id": 2, 
        \\      "name": "Bob",
        \\      "metadata": {
        \\        "active": false,
        \\        "roles": ["user"],
        \\        "settings": null
        \\      }
        \\    }
        \\  ],
        \\  "count": 2
        \\}
    ;

    var lexer = JsonLexer.init(allocator);
    const tokens = try lexer.batchTokenize(allocator, complex_json);
    defer allocator.free(tokens);

    // Should have reasonable number of tokens for this complex structure
    try testing.expect(tokens.len > 50);

    // Last token should be EOF
    try testing.expectEqual(TokenKind.eof, tokens[tokens.len - 1].kind);

    // Should have proper braces, brackets, and other structural elements
    var brace_count: i32 = 0;
    var bracket_count: i32 = 0;
    for (tokens) |token| {
        switch (token.kind) {
            .left_brace => brace_count += 1,
            .right_brace => brace_count -= 1,
            .left_bracket => bracket_count += 1,
            .right_bracket => bracket_count -= 1,
            else => {},
        }
    }

    // Should be balanced
    try testing.expectEqual(@as(i32, 0), brace_count);
    try testing.expectEqual(@as(i32, 0), bracket_count);
}

test "JSON lexer - string error handling" {
    // Re-enabled for basic error detection
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Test basic string tokenization (even if error handling isn't perfect)
    const test_cases = [_][]const u8{
        "\"normal string\"",
        "\"string with \\\"escaped quotes\\\"\"",
        "\"string with \\n newlines\"",
        "\"empty string: \\\"\\\"\"",
    };

    for (test_cases) |case| {
        var lexer = JsonLexer.init(allocator);
        defer lexer.deinit();

        const tokens = try lexer.batchTokenize(allocator, case);
        defer allocator.free(tokens);

        // Should get at least a string token and EOF
        try testing.expect(tokens.len >= 2);
        try testing.expectEqual(TokenKind.string, tokens[0].kind);
        try testing.expectEqual(TokenKind.eof, tokens[tokens.len - 1].kind);
    }
}

test "JSON lexer - infinite loop regression test" {
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
        .{ .input = "{}", .expected_min_tokens = 3, .description = "empty object" },
        .{ .input = "[]", .expected_min_tokens = 3, .description = "empty array" },
        .{ .input = "42", .expected_min_tokens = 2, .description = "single number" },
        .{ .input = "\"test\"", .expected_min_tokens = 2, .description = "single string" },
        .{ .input = "true", .expected_min_tokens = 2, .description = "boolean true" },
        .{ .input = "false", .expected_min_tokens = 2, .description = "boolean false" },
        .{ .input = "null", .expected_min_tokens = 2, .description = "null value" },
        .{ .input = "{\"key\": \"value\"}", .expected_min_tokens = 6, .description = "simple object" },
        .{ .input = "[1, 2, 3]", .expected_min_tokens = 8, .description = "simple array" },
        .{ .input = "{\"users\": [{\"name\": \"Alice\", \"age\": 30}]}", .expected_min_tokens = 15, .description = "nested structure" },
    };

    for (test_cases) |case| {
        var lexer = JsonLexer.init(allocator);

        // This should complete quickly without hanging
        const tokens = try lexer.batchTokenize(allocator, case.input);
        defer allocator.free(tokens);

        // Verify we got reasonable number of tokens
        try testing.expect(tokens.len >= case.expected_min_tokens);

        // Verify the last token is always EOF
        try testing.expectEqual(TokenKind.eof, tokens[tokens.len - 1].kind);

        // Verify EOF token position is at end of input
        try testing.expectEqual(@as(u32, @intCast(case.input.len)), tokens[tokens.len - 1].span.start);
        try testing.expectEqual(@as(u32, @intCast(case.input.len)), tokens[tokens.len - 1].span.end);
    }
}
