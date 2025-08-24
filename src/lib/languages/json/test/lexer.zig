const std = @import("std");
const testing = std.testing;

// Import streaming lexer for new tests
const Lexer = @import("../lexer/mod.zig").Lexer;
const TokenKind = @import("../token/mod.zig").TokenKind;

// =============================================================================
// Lexer Tests - Migrated to Streaming Architecture
// =============================================================================

test "JSON lexer - basic tokens" {
    const input = "{ \"name\": \"test\", \"value\": 42, \"flag\": true, \"empty\": null }";

    var lexer = Lexer.init(input);
    var token_count: usize = 0;
    var found_tokens = std.ArrayList(TokenKind).init(testing.allocator);
    defer found_tokens.deinit();

    while (lexer.next()) |token| {
        token_count += 1;
        switch (token) {
            .json => |t| {
                try found_tokens.append(t.kind);
            },
            else => {},
        }
    }

    // Should have tokens: { "name" : "test" , "value" : 42 , "flag" : true , "empty" : null }
    try testing.expect(token_count >= 15); // At least 15 tokens for this simple JSON

    // Check that we got expected structural tokens
    var has_object_start = false;
    var has_object_end = false;
    var has_string = false;
    var has_number = false;
    var has_true = false;
    var has_null = false;

    for (found_tokens.items) |kind| {
        switch (kind) {
            .object_start => has_object_start = true,
            .object_end => has_object_end = true,
            .string_value => has_string = true,
            .number_value => has_number = true,
            .boolean_true => has_true = true,
            .null_value => has_null = true,
            else => {},
        }
    }

    try testing.expect(has_object_start);
    try testing.expect(has_object_end);
    try testing.expect(has_string);
    try testing.expect(has_number);
    try testing.expect(has_true);
    try testing.expect(has_null);
}

test "JSON lexer - complex structures" {
    const input =
        \\{
        \\  "users": [
        \\    { "name": "Alice", "age": 30, "active": true },
        \\    { "name": "Bob", "age": 25, "active": false }
        \\  ],
        \\  "total": 2,
        \\  "metadata": null
        \\}
    ;

    var lexer = Lexer.init(input);
    var token_count: usize = 0;
    var object_depth: i32 = 0;
    var array_depth: i32 = 0;

    while (lexer.next()) |token| {
        token_count += 1;
        switch (token) {
            .json => |t| {
                switch (t.kind) {
                    .object_start => object_depth += 1,
                    .object_end => object_depth -= 1,
                    .array_start => array_depth += 1,
                    .array_end => array_depth -= 1,
                    else => {},
                }
            },
            else => {},
        }
    }

    // Should have many tokens for this complex structure
    try testing.expect(token_count >= 30);

    // Should end with balanced braces/brackets
    try testing.expectEqual(@as(i32, 0), @as(i32, @intCast(object_depth)));
    try testing.expectEqual(@as(i32, 0), @as(i32, @intCast(array_depth)));
}

test "JSON lexer - string error handling" {
    const unterminated_string = "{ \"key\": \"unterminated value";
    const invalid_escape = "{ \"key\": \"invalid\\q escape\" }";

    // Test unterminated string
    var lexer1 = Lexer.init(unterminated_string);
    var found_error = false;

    while (lexer1.next()) |token| {
        switch (token) {
            .json => |t| {
                if (t.kind == .err) {
                    found_error = true;
                }
            },
            else => {},
        }
    }

    try testing.expect(found_error);

    // Test invalid escape - lexer should handle gracefully
    var lexer2 = Lexer.init(invalid_escape);
    var token_count: usize = 0;

    while (lexer2.next()) |token| {
        token_count += 1;
        switch (token) {
            .json => |t| {
                // Should still produce tokens, even if some are invalid
                _ = t;
            },
            else => {},
        }
        if (token_count > 20) break; // Prevent infinite loop
    }

    try testing.expect(token_count > 0);
}

test "JSON lexer - infinite loop regression test" {
    // Test various edge cases that might cause infinite loops
    const edge_cases = [_][]const u8{
        "", // Empty input
        "{", // Unclosed brace
        "}", // Just closing brace
        "\"", // Just quote
        "123", // Just number
        "123.456.789", // Invalid number
        "{{{{{", // Multiple opening braces
        "}}}}", // Multiple closing braces
        "null null null", // Multiple literals
        "{ , , , }", // Just commas
        "{ : : : }", // Just colons
    };

    for (edge_cases) |input| {
        var lexer = Lexer.init(input);
        var token_count: usize = 0;

        // Set a reasonable limit to detect infinite loops
        while (lexer.next()) |token| {
            token_count += 1;
            _ = token; // Use the token
            if (token_count > 100) {
                // If we get more than 100 tokens from these simple inputs, something is wrong
                try testing.expect(false); // This should not happen
            }
        }

        // Should always produce at least EOF token
        try testing.expect(token_count >= 1);
    }
}

// Original test data preserved for reference when rewriting:
// - Basic tokens: strings, numbers, booleans, null, structural chars
// - Complex JSON with nested objects and arrays
// - Error cases: unterminated strings, invalid escapes
// - Edge cases that previously caused infinite loops

// When rewriting for streaming:
// 1. Use Lexer.init(source) instead of JsonLexer.init(allocator)
// 2. Iterate tokens with while (lexer.next()) instead of batchTokenize()
// 3. Test token properties directly from Token
// 4. No need to free token arrays (zero-allocation streaming)
