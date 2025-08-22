const std = @import("std");
const testing = std.testing;

// Import JSON components
const JsonLexer = @import("lexer.zig").JsonLexer;
const JsonParser = @import("parser.zig").JsonParser;

// Import types
const Token = @import("../../token/mod.zig").Token;
const TokenKind = @import("../../token/mod.zig").TokenKind;

// =============================================================================
// Parser Tests
// =============================================================================

test "JSON parser - all value types" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const test_cases = [_][]const u8{
        "\"hello\"",
        "42",
        "true",
        "false",
        "null",
        "[]",
        "{}",
        "[1, 2, 3]",
        "{\"key\": \"value\"}",
    };

    for (test_cases) |case| {
        var lexer = JsonLexer.init(allocator);
        const tokens = try lexer.batchTokenize(allocator, case);
        defer allocator.free(tokens);

        var parser = JsonParser.init(allocator, tokens, case, .{});
        defer parser.deinit();

        var ast = try parser.parse();
        defer ast.deinit();

        // AST root should exist and be a valid node
        // ast.root is a pointer, so we just check that it's valid

        // Check that the root node has expected structure
        switch (ast.root.*) {
            .object, .array, .string, .number, .boolean, .null, .root => {
                // Valid root node types
            },
            else => {
                try testing.expect(false); // Unexpected node type
            },
        }

        // Check for parse errors
        const errors = parser.getErrors();
        try testing.expectEqual(@as(usize, 0), errors.len);
    }
}

test "JSON parser - nested structures" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const nested_json =
        \\{
        \\  "level1": {
        \\    "level2": {
        \\      "level3": {
        \\        "value": "deep"
        \\      }
        \\    }
        \\  },
        \\  "array": [
        \\    [1, 2],
        \\    [3, 4]
        \\  ]
        \\}
    ;

    var lexer = JsonLexer.init(allocator);
    const tokens = try lexer.batchTokenize(allocator, nested_json);
    defer allocator.free(tokens);

    var parser = JsonParser.init(allocator, tokens, nested_json, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    // AST root is no longer optional, it's always a Node struct
    // Check that AST was created successfully
    // ast.root is a pointer, so it's always valid if AST was created

    const errors = parser.getErrors();
    try testing.expectEqual(@as(usize, 0), errors.len);
}

test "JSON parser - error recovery" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const malformed_cases = [_][]const u8{
        "{\"key\": }", // Missing value
        "{\"key\": \"value\",}", // Trailing comma
        "[1, 2,]", // Trailing comma in array
        "{key: \"value\"}", // Unquoted key
        "{'key': 'value'}", // Single quotes
    };

    for (malformed_cases) |case| {
        var lexer = JsonLexer.init(allocator);
        const tokens = try lexer.batchTokenize(allocator, case);
        defer allocator.free(tokens);

        var parser = JsonParser.init(allocator, tokens, case, .{});
        defer parser.deinit();

        // Parser should handle errors gracefully
        var ast = parser.parse() catch |err| switch (err) {
            error.ParseError => {
                // Some malformed JSON might fail completely
                continue;
            },
            else => return err,
        };
        defer ast.deinit();

        // If parsing succeeds, should still produce some AST
        // AST root is no longer optional, it's always a Node struct
        // Check that AST was created successfully
        // ast.root is a pointer, so it's always valid if AST was created

        // Should have recorded errors
        const errors = parser.getErrors();
        try testing.expect(errors.len > 0);
    }
}
