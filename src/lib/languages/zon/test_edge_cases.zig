const std = @import("std");
const testing = std.testing;

// Import ZON modules
const ZonLexer = @import("lexer.zig").ZonLexer;
const ZonParser = @import("parser.zig").ZonParser;

// =============================================================================
// Edge Cases Tests
// =============================================================================

test "ZON edge cases - empty structures" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const test_cases = [_][]const u8{
        ".{}",
        ".{ }",
        ".{\n}",
        ".{\n    \n}",
    };

    for (test_cases) |input| {
        var lexer = ZonLexer.init(allocator);
        defer lexer.deinit();

        const tokens = try lexer.tokenize(input);
        defer allocator.free(tokens);

        var parser = ZonParser.init(allocator, tokens, input, .{});
        defer parser.deinit();

        var ast = try parser.parse();
        defer ast.deinit();

        try testing.expect(ast.root != null);
    }
}

test "ZON edge cases - special identifiers" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = ".{ .@\"special field\" = \"value\", .@\"123numeric\" = 456 }";

    var lexer = ZonLexer.init(allocator);
    defer lexer.deinit();

    const tokens = try lexer.tokenize(input);
    defer allocator.free(tokens);

    var parser = ZonParser.init(allocator, tokens, input, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    try testing.expect(ast.root != null);
}

test "ZON edge cases - trailing commas" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = ".{ .name = \"test\", .version = \"1.0.0\", }";

    var lexer = ZonLexer.init(allocator);
    defer lexer.deinit();

    const tokens = try lexer.tokenize(input);
    defer allocator.free(tokens);

    var parser = ZonParser.init(allocator, tokens, input, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    try testing.expect(ast.root != null);
}

test "ZON edge cases - nested anonymous structs" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = ".{ .config = .{ .nested = .{ .deep = .{ .value = 42 } } } }";

    var lexer = ZonLexer.init(allocator);
    defer lexer.deinit();

    const tokens = try lexer.tokenize(input);
    defer allocator.free(tokens);

    var parser = ZonParser.init(allocator, tokens, input, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    try testing.expect(ast.root != null);
}

test "ZON edge cases - all number formats" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input =
        \\.{
        \\    .decimal = 42,
        \\    .hex = 0xFF,
        \\    .octal = 0o755,
        \\    .binary = 0b1010,
        \\    .float = 3.14,
        \\    .scientific = 1.23e-4,
        \\}
    ;

    var lexer = ZonLexer.init(allocator);
    defer lexer.deinit();

    const tokens = try lexer.tokenize(input);
    defer allocator.free(tokens);

    var parser = ZonParser.init(allocator, tokens, input, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    try testing.expect(ast.root != null);
}

test {
    // Add a final empty test to handle the incomplete test at the end of the original file
    // This ensures the file compiles properly
}
