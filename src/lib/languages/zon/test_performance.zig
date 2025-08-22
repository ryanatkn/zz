const std = @import("std");
const testing = std.testing;

// Import ZON modules
const ZonLexer = @import("lexer.zig").ZonLexer;
const ZonParser = @import("parser.zig").ZonParser;
const ZonFormatter = @import("formatter.zig").ZonFormatter;

// =============================================================================
// Performance Tests
// =============================================================================

test "ZON performance - lexing speed" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Generate large ZON structure
    var large_zon = std.ArrayList(u8).init(allocator);
    defer large_zon.deinit();

    try large_zon.appendSlice(".{ .data = .{");

    const num_items = 1000;
    for (0..num_items) |i| {
        if (i > 0) try large_zon.appendSlice(", ");
        try large_zon.writer().print(" .item{} = .{{ .id = {}, .name = \"item{}\", .value = {} }}", .{ i, i, i, i * 2 });
    }

    try large_zon.appendSlice(" } }");

    const zon_text = large_zon.items;

    // Time the lexing operation
    const start_time = std.time.nanoTimestamp();

    var lexer = ZonLexer.init(allocator);
    defer lexer.deinit();

    const tokens = try lexer.tokenize(zon_text);
    defer allocator.free(tokens);

    const lex_time = std.time.nanoTimestamp() - start_time;

    // Should complete in reasonable time (less than 100ms for 1000 items)
    try testing.expect(lex_time < 100_000_000); // 100ms in nanoseconds

    // Should produce reasonable number of tokens
    try testing.expect(tokens.len > num_items);
}

test "ZON performance - parsing speed" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = ".{ .name = \"test\", .version = \"1.0.0\", .dependencies = .{} }";

    var lexer = ZonLexer.init(allocator);
    defer lexer.deinit();

    const tokens = try lexer.tokenize(input);
    defer allocator.free(tokens);

    // Time the parsing operation
    const start_time = std.time.nanoTimestamp();

    var parser = ZonParser.init(allocator, tokens, input, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    const parse_time = std.time.nanoTimestamp() - start_time;

    // Should complete quickly (less than 10ms for simple input)
    try testing.expect(parse_time < 10_000_000); // 10ms in nanoseconds

    // Should produce valid AST
    try testing.expect(ast.root != null);
}

test "ZON performance - formatting speed" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input =
        \\.{
        \\    .name = "test",
        \\    .version = "1.0.0",
        \\    .dependencies = .{
        \\        .package = .{
        \\            .url = "https://example.com",
        \\            .hash = "1234567890abcdef",
        \\        },
        \\    },
        \\    .paths = .{ "src", "test", "docs" },
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

    // Time the formatting operation
    const start_time = std.time.nanoTimestamp();

    var formatter = ZonFormatter.init(allocator, .{});
    defer formatter.deinit();

    const formatted = try formatter.format(ast);
    defer allocator.free(formatted);

    const format_time = std.time.nanoTimestamp() - start_time;

    // Should complete quickly (less than 5ms for moderate input)
    try testing.expect(format_time < 5_000_000); // 5ms in nanoseconds

    // Should produce non-empty formatted output
    try testing.expect(formatted.len > 0);
    
    // Should produce valid ZON (basic check - starts with { and ends with })
    try testing.expect(std.mem.startsWith(u8, formatted, "{"));
    try testing.expect(std.mem.endsWith(u8, formatted, "}"));
    
    // Should contain key structure elements  
    try testing.expect(std.mem.indexOf(u8, formatted, ".name") != null);
    try testing.expect(std.mem.indexOf(u8, formatted, ".version") != null);
    try testing.expect(std.mem.indexOf(u8, formatted, ".dependencies") != null);
}
