const std = @import("std");
const testing = std.testing;

// Import ZON modules
const ZonLexer = @import("lexer.zig").ZonLexer;
const ZonParser = @import("parser.zig").ZonParser;
const ZonFormatter = @import("formatter.zig").ZonFormatter;
const FormatOptions = @import("../interface.zig").FormatOptions;

// =============================================================================
// Formatter Tests
// =============================================================================

test "ZON formatter - basic formatting" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = ".{.name=\"test\",.version=\"1.0.0\"}";

    var lexer = ZonLexer.init(allocator);
    defer lexer.deinit();

    const tokens = try lexer.tokenize(input);
    defer allocator.free(tokens);

    var parser = ZonParser.init(allocator, tokens, input, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    var formatter = ZonFormatter.init(allocator, .{});
    defer formatter.deinit();

    const formatted = try formatter.format(ast);
    defer allocator.free(formatted);

    try testing.expect(formatted.len > input.len); // Should have whitespace
}

test "ZON formatter - preserve structure" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input =
        \\.{
        \\    .name = "test",
        \\    .dependencies = .{
        \\        .package = .{
        \\            .url = "https://example.com",
        \\        },
        \\    },
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

    var formatter = ZonFormatter.init(allocator, .{});
    defer formatter.deinit();

    const formatted = try formatter.format(ast);
    defer allocator.free(formatted);

    try testing.expect(formatted.len > 0);
}

test "ZON formatter - compact vs multiline" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = ".{ .name = \"test\", .version = \"1.0.0\" }";

    var lexer = ZonLexer.init(allocator);
    defer lexer.deinit();

    const tokens = try lexer.tokenize(input);
    defer allocator.free(tokens);

    var parser = ZonParser.init(allocator, tokens, input, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    // Test compact formatting
    var compact_formatter = ZonFormatter.init(allocator, .{ .compact_small_objects = true, .compact_small_arrays = true });
    defer compact_formatter.deinit();

    const compact = try compact_formatter.format(ast);
    defer allocator.free(compact);

    // Test multiline formatting
    var multiline_formatter = ZonFormatter.init(allocator, .{ .compact_small_objects = false, .compact_small_arrays = false });
    defer multiline_formatter.deinit();

    const multiline = try multiline_formatter.format(ast);
    defer allocator.free(multiline);

    try testing.expect(compact.len < multiline.len);
}

test "ZON formatter - round trip" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const inputs = [_][]const u8{
        ".{ .name = \"test\" }",
        ".{ .number = 42 }",
        ".{ .boolean = true }",
        ".{ .null_val = null }",
        ".{ .nested = .{ .field = \"value\" } }",
    };

    for (inputs) |input| {
        // Parse original
        var lexer1 = ZonLexer.init(allocator);
        defer lexer1.deinit();

        const tokens1 = try lexer1.tokenize(input);
        defer allocator.free(tokens1);

        var parser1 = ZonParser.init(allocator, tokens1, input, .{});
        defer parser1.deinit();

        var ast1 = try parser1.parse();
        defer ast1.deinit();

        // Format it
        var formatter = ZonFormatter.init(allocator, .{});
        defer formatter.deinit();

        const formatted = try formatter.format(ast1);
        defer allocator.free(formatted);

        // Parse formatted version
        var lexer2 = ZonLexer.init(allocator);
        defer lexer2.deinit();

        const tokens2 = try lexer2.tokenize(formatted);
        defer allocator.free(tokens2);

        var parser2 = ZonParser.init(allocator, tokens2, formatted, .{});
        defer parser2.deinit();

        var ast2 = try parser2.parse();
        defer ast2.deinit();

        // Both should be valid
        try testing.expect(ast1.root != null);
        try testing.expect(ast2.root != null);
    }
}
