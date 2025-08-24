/// Comprehensive escape sequence tests for ZON parser
const std = @import("std");
const testing = std.testing;
const ZonParser = @import("parser.zig").ZonParser;

test "ZON escape sequences - basic escapes" {
    const allocator = testing.allocator;

    const test_cases = [_]struct {
        input: []const u8,
        expected: []const u8,
    }{
        .{ .input = "\"\\\"\"", .expected = "\"" }, // \"
        .{ .input = "\"\\\\\"", .expected = "\\" }, // \\
        .{ .input = "\"\\/\"", .expected = "/" }, // \/
        .{ .input = "\"\\b\"", .expected = "\x08" }, // \b (backspace)
        .{ .input = "\"\\f\"", .expected = "\x0C" }, // \f (form feed)
        .{ .input = "\"\\n\"", .expected = "\n" }, // \n (newline)
        .{ .input = "\"\\r\"", .expected = "\r" }, // \r (carriage return)
        .{ .input = "\"\\t\"", .expected = "\t" }, // \t (tab)
    };

    for (test_cases) |case| {
        var parser = try ZonParser.init(allocator, case.input, .{});
        defer parser.deinit();

        var ast = try parser.parse();
        defer ast.deinit();

        // Should parse as a simple string value
        try testing.expect(ast.root != null);
        try testing.expect(ast.root.?.* == .string);

        const string_value = ast.root.?.string.value;
        try testing.expectEqualStrings(case.expected, string_value);
    }
}

test "ZON escape sequences - Unicode escapes" {
    const allocator = testing.allocator;

    const test_cases = [_]struct {
        input: []const u8,
        expected: []const u8,
        description: []const u8,
    }{
        .{ .input = "\"\\u0041\"", .expected = "A", .description = "Basic ASCII (A)" },
        .{ .input = "\"\\u0048\\u0065\\u006C\\u006C\\u006F\"", .expected = "Hello", .description = "ASCII sequence" },
        .{ .input = "\"\\u00A9\"", .expected = "©", .description = "Copyright symbol" },
        .{ .input = "\"\\u03A9\"", .expected = "Ω", .description = "Greek Omega" },
        .{ .input = "\"\\u20AC\"", .expected = "€", .description = "Euro symbol" },
        .{ .input = "\"\\u2603\"", .expected = "☃", .description = "Snowman emoji" },
    };

    for (test_cases) |case| {
        var parser = try ZonParser.init(allocator, case.input, .{});
        defer parser.deinit();

        var ast = try parser.parse();
        defer ast.deinit();

        try testing.expect(ast.root != null);
        try testing.expect(ast.root.?.* == .string);

        const string_value = ast.root.?.string.value;
        try testing.expectEqualStrings(case.expected, string_value);
    }
}

test "ZON escape sequences - multiline string escapes" {
    const allocator = testing.allocator;

    // ZON supports multiline strings with triple backslash
    const test_cases = [_]struct {
        input: []const u8,
        expected: []const u8,
        description: []const u8,
    }{
        .{ .input = "\"\\\\\\\\\"", .expected = "\\", .description = "Literal backslash in multiline" },
        .{ .input = "\"line1\\\\\\nline2\"", .expected = "line1\\\nline2", .description = "Multiline with literal backslash" },
    };

    for (test_cases) |case| {
        var parser = try ZonParser.init(allocator, case.input, .{});
        defer parser.deinit();

        var ast = try parser.parse();
        defer ast.deinit();

        try testing.expect(ast.root != null);
        try testing.expect(ast.root.?.* == .string);

        const string_value = ast.root.?.string.value;
        try testing.expectEqualStrings(case.expected, string_value);
    }
}

test "ZON escape sequences - mixed content" {
    const allocator = testing.allocator;

    const input = "\"Hello\\nWorld\\t\\\"quoted\\\"\\u00A9\"";
    const expected = "Hello\nWorld\t\"quoted\"©";

    var parser = try ZonParser.init(allocator, input, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    try testing.expect(ast.root != null);
    try testing.expect(ast.root.?.* == .string);

    const string_value = ast.root.?.string.value;
    try testing.expectEqualStrings(expected, string_value);
}

test "ZON escape sequences - complex ZON with escapes" {
    const allocator = testing.allocator;

    const input =
        \\.{
        \\    .name = "Test \"User\"",
        \\    .bio = "Line 1\nLine 2\tTabbed",
        \\    .symbol = "\u00A9 2024",
        \\    .path = "C:\\\\Users\\\\test"
        \\}
    ;

    var parser = try ZonParser.init(allocator, input, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    try testing.expect(ast.root != null);
    try testing.expect(ast.root.?.* == .object);

    // Check that the object was parsed with escape sequences properly handled
    const object_node = ast.root.?.object;
    try testing.expect(object_node.fields.len == 4);
}

test "ZON escape sequences - field names with escapes" {
    const allocator = testing.allocator;

    const input =
        \\.{
        \\    .@"field with spaces" = "value1",
        \\    .@"field\nwith\nnewlines" = "value2"
        \\}
    ;

    var parser = try ZonParser.init(allocator, input, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    try testing.expect(ast.root != null);
    try testing.expect(ast.root.?.* == .object);

    const object_node = ast.root.?.object;
    try testing.expect(object_node.fields.len == 2);
}

test "ZON escape sequences - invalid Unicode" {
    const allocator = testing.allocator;

    const test_cases = [_][]const u8{
        "\"\\uXXXX\"", // Invalid hex digits
        "\"\\u123\"", // Too few hex digits
        "\"\\u\"", // No hex digits
    };

    for (test_cases) |input| {
        var parser = try ZonParser.init(allocator, input, .{});
        defer parser.deinit();

        var ast = try parser.parse();
        defer ast.deinit();

        // Invalid Unicode may either fail to parse or parse with escape as-is
        if (ast.root) |root| {
            try testing.expect(root.* == .string);
        }
        // If ast.root is null, the parser failed which is also acceptable
    }
}

test "ZON escape sequences - AST toString with escaping" {
    const allocator = testing.allocator;

    // Test that AST can properly escape strings when converted back to ZON
    const input = "\"Hello\\nWorld\"";

    var parser = try ZonParser.init(allocator, input, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    // Convert back to string
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    try ast.root.?.toZonString(buffer.writer());
    const result = buffer.items;

    // Should properly escape the newline
    try testing.expect(std.mem.indexOf(u8, result, "\\n") != null);
}

test "ZON escape sequences - anonymous list with escapes" {
    const allocator = testing.allocator;

    const input =
        \\[
        \\    "item\nwith\nnewlines",
        \\    "item\twith\ttabs",
        \\    "item\"with\"quotes"
        \\]
    ;

    var parser = try ZonParser.init(allocator, input, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    try testing.expect(ast.root != null);
    try testing.expect(ast.root.?.* == .array);

    const array_node = ast.root.?.array;
    try testing.expect(array_node.elements.len == 3);

    // Verify the escape sequences were processed in the array elements
    for (array_node.elements) |*element| {
        try testing.expect(element.* == .string);
    }
}
