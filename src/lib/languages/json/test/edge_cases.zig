const std = @import("std");
const testing = std.testing;

// Import JSON modules
const json_mod = @import("../mod.zig");
const Parser = @import("../parser/mod.zig").Parser;

// =============================================================================
// JSON Edge Cases Tests
// =============================================================================

test "JSON edge cases - empty structures" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const test_cases = [_][]const u8{
        "{}",
        "[]",
        "{ \"items\": {} }",
        "{ \"nested\": { \"empty\": {} } }",
        "{ \"array\": [] }",
        "{ \"mixed\": { \"obj\": {}, \"arr\": [] } }",
    };

    for (test_cases) |input| {
        var parser = try Parser.init(allocator, input, .{});
        defer parser.deinit();

        var ast = try parser.parse();
        defer ast.deinit();

        try testing.expect(ast.root.* != .err);
    }
}

test "JSON edge cases - deeply nested structures" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Deep object nesting
    const deep_object = "{\"level1\":{\"level2\":{\"level3\":{\"level4\":{\"value\":42}}}}}";

    var parser1 = try Parser.init(allocator, deep_object, .{});
    defer parser1.deinit();
    var ast1 = try parser1.parse();
    defer ast1.deinit();
    try testing.expect(ast1.root.* != .err);

    // Deep array nesting
    const deep_array = "[[[[42]]]]";

    var parser2 = try Parser.init(allocator, deep_array, .{});
    defer parser2.deinit();
    var ast2 = try parser2.parse();
    defer ast2.deinit();
    try testing.expect(ast2.root.* != .err);

    // Mixed deep nesting
    const mixed_deep = "{\"array\":[{\"nested\":{\"deeper\":[1,2,3]}}]}";

    var parser3 = try Parser.init(allocator, mixed_deep, .{});
    defer parser3.deinit();
    var ast3 = try parser3.parse();
    defer ast3.deinit();
    try testing.expect(ast3.root.* != .err);
}

test "JSON edge cases - special number values" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const test_cases = [_][]const u8{
        // Zero variations
        "0",
        "0.0",
        "-0",
        "-0.0",

        // Very large numbers
        "9007199254740991", // Max safe integer in JavaScript
        "-9007199254740991",

        // Very small numbers
        "1e-10",
        "-1e-10",
        "1E-10",

        // Scientific notation variations
        "1.23e+10",
        "1.23E+10",
        "1.23e-10",
        "1.23E-10",

        // Edge case floats
        "0.123456789",
        "-0.123456789",
        "123.0",
        "-123.0",
    };

    for (test_cases) |input| {
        var parser = try Parser.init(allocator, input, .{});
        defer parser.deinit();

        var ast = try parser.parse();
        defer ast.deinit();

        try testing.expect(ast.root.* != .err);
    }
}

test "JSON edge cases - string edge cases" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const test_cases = [_][]const u8{
        // Empty string
        "\"\"",

        // Strings with only whitespace
        "\" \"",
        "\"\\t\"",
        "\"\\n\"",
        "\"\\r\"",

        // Strings with all escape sequences
        "\"\\\"\\\\\\b\\f\\n\\r\\t\"",

        // Unicode escapes
        "\"\\u0000\"",
        "\"\\u0048\\u0065\\u006C\\u006C\\u006F\"", // "Hello"
        "\"\\uD83D\\uDE00\"", // Emoji (surrogate pair)

        // Mixed content
        "\"Hello\\nWorld\\t!\"",
        "\"JSON\\u0020String\"",

        // Strings with quotes
        "\"Say \\\"Hello\\\" to JSON\"",
    };

    for (test_cases) |input| {
        var parser = try Parser.init(allocator, input, .{});
        defer parser.deinit();

        var ast = try parser.parse();
        defer ast.deinit();

        try testing.expect(ast.root.* != .err);
    }
}

test "JSON edge cases - arrays with mixed types" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const test_cases = [_][]const u8{
        // Mixed primitive types
        "[true, false, null, 42, \"string\"]",

        // Mixed structures
        "[{}, [], \"text\", 123, true]",

        // Nested mixed
        "[{\"key\": [1, 2, 3]}, [\"a\", \"b\", \"c\"], null]",

        // Single element arrays
        "[42]",
        "[\"single\"]",
        "[true]",
        "[null]",
        "[{}]",
        "[[]]",

        // Arrays with trailing elements
        "[1, 2, 3, null]",
        "[\"a\", \"b\", \"c\", null]",
    };

    for (test_cases) |input| {
        var parser = try Parser.init(allocator, input, .{});
        defer parser.deinit();

        var ast = try parser.parse();
        defer ast.deinit();

        try testing.expect(ast.root.* != .err);
    }
}

test "JSON edge cases - objects with special keys" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const test_cases = [_][]const u8{
        // Empty key
        "{\"\": \"empty key\"}",

        // Keys with spaces and special characters
        "{\"key with spaces\": \"value\"}",
        "{\"key-with-dashes\": \"value\"}",
        "{\"key_with_underscores\": \"value\"}",
        "{\"123numeric_key\": \"value\"}",

        // Keys with escape sequences
        "{\"key\\nwith\\nnewlines\": \"value\"}",
        "{\"key\\twith\\ttabs\": \"value\"}",
        "{\"key\\\"with\\\"quotes\": \"value\"}",

        // Unicode keys
        "{\"\\u0048\\u0065\\u006C\\u006C\\u006F\": \"unicode key\"}",

        // Single character keys
        "{\"a\": 1, \"b\": 2, \"c\": 3}",

        // Very long key
        "{\"this_is_a_very_long_key_name_that_might_test_buffer_boundaries_and_memory_allocation\": \"value\"}",
    };

    for (test_cases) |input| {
        var parser = try Parser.init(allocator, input, .{});
        defer parser.deinit();

        var ast = try parser.parse();
        defer ast.deinit();

        try testing.expect(ast.root.* != .err);
    }
}

test "JSON edge cases - whitespace handling" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // All these should parse to equivalent structures
    const equivalent_cases = [_][]const u8{
        "{\"key\":\"value\"}",
        "{ \"key\" : \"value\" }",
        "{\n  \"key\": \"value\"\n}",
        "{\r\n  \"key\":\t\"value\"\r\n}",
        "{ \t\n\r \"key\" \t\n\r : \t\n\r \"value\" \t\n\r }",
    };

    // Parse all cases and verify they're valid
    for (equivalent_cases) |input| {
        var parser = try Parser.init(allocator, input, .{});
        defer parser.deinit();

        var ast = try parser.parse();
        defer ast.deinit();

        try testing.expect(ast.root.* != .err);
    }
}

test "JSON edge cases - boolean and null edge cases" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const test_cases = [_][]const u8{
        // Simple cases
        "true",
        "false",
        "null",

        // In arrays
        "[true, false, null]",
        "[true]",
        "[false]",
        "[null]",

        // In objects
        "{\"true_val\": true, \"false_val\": false, \"null_val\": null}",
        "{\"bool\": true}",
        "{\"bool\": false}",
        "{\"nullable\": null}",

        // Mixed with other types
        "{\"mixed\": [true, 42, \"string\", null, false]}",
    };

    for (test_cases) |input| {
        var parser = try Parser.init(allocator, input, .{});
        defer parser.deinit();

        var ast = try parser.parse();
        defer ast.deinit();

        try testing.expect(ast.root.* != .err);
    }
}

test "JSON edge cases - large structures" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Create a large JSON object
    var large_json = std.ArrayList(u8).init(allocator);
    defer large_json.deinit();

    try large_json.appendSlice("{\n");

    // Add many fields
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        try std.fmt.format(large_json.writer(), "  \"field_{d}\": \"value_{d}\",\n", .{ i, i });
    }

    // Add nested object
    try large_json.appendSlice("  \"nested\": {\n");
    i = 0;
    while (i < 50) : (i += 1) {
        try std.fmt.format(large_json.writer(), "    \"nested_field_{d}\": {d},\n", .{ i, i * 2 });
    }
    // Remove last comma and close nested object
    _ = large_json.pop();
    _ = large_json.pop();
    try large_json.appendSlice("\n  },\n");

    // Add large array
    try large_json.appendSlice("  \"array\": [");
    i = 0;
    while (i < 200) : (i += 1) {
        try std.fmt.format(large_json.writer(), "{d}", .{i});
        if (i < 199) try large_json.appendSlice(", ");
    }
    try large_json.appendSlice("]\n");

    try large_json.appendSlice("}");

    const large_json_str = large_json.items;

    // Parse the large structure
    var parser = try Parser.init(allocator, large_json_str, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    try testing.expect(ast.root.* != .err);
}

test "JSON edge cases - minimal valid structures" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const minimal_cases = [_][]const u8{
        // Minimal primitives (single values)
        "42",
        "\"hello\"",
        "true",
        "false",
        "null",
        "0",
        "\"\"",

        // Minimal structures
        "{}",
        "[]",
        "{\"a\":1}",
        "[1]",
    };

    for (minimal_cases) |input| {
        var parser = try Parser.init(allocator, input, .{});
        defer parser.deinit();

        var ast = try parser.parse();
        defer ast.deinit();

        try testing.expect(ast.root.* != .err);
    }
}
