const std = @import("std");
const testing = std.testing;

// Import JSON components
const JsonParser = @import("parser.zig").JsonParser;
const JsonFormatter = @import("formatter.zig").JsonFormatter;

// =============================================================================
// Formatter Tests
// =============================================================================

test "JSON formatter - pretty printing" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const compact_input = "{\"name\":\"Alice\",\"age\":30,\"hobbies\":[\"reading\",\"swimming\"]}";

    var parser = try JsonParser.init(allocator, compact_input, .{});
    defer parser.deinit();
    var ast = try parser.parse();
    defer ast.deinit();

    // Test pretty formatting
    var formatter = JsonFormatter.init(allocator, .{
        .indent_size = 2,
        .compact_objects = false,
        .compact_arrays = false,
    });
    defer formatter.deinit();

    const formatted = try formatter.format(ast);
    defer allocator.free(formatted);

    // Should contain newlines and proper indentation
    try testing.expect(std.mem.indexOf(u8, formatted, "\n") != null);
    try testing.expect(std.mem.indexOf(u8, formatted, "  ") != null);

    // Should be valid JSON when parsed again
    var parser2 = try JsonParser.init(allocator, formatted, .{});
    defer parser2.deinit();
    var ast2 = try parser2.parse();
    defer ast2.deinit();

    // AST.root is non-optional now
}

test "JSON formatter - options" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = "{\"zebra\": 1, \"alpha\": 2, \"beta\": 3}";

    var parser = try JsonParser.init(allocator, input, .{});
    defer parser.deinit();
    var ast = try parser.parse();
    defer ast.deinit();

    // Test key sorting
    var formatter = JsonFormatter.init(allocator, .{
        .sort_keys = true,
        .force_compact = true,
    });
    defer formatter.deinit();

    const formatted = try formatter.format(ast);
    defer allocator.free(formatted);

    // Keys should be alphabetically ordered
    const alpha_pos = std.mem.indexOf(u8, formatted, "alpha");
    const beta_pos = std.mem.indexOf(u8, formatted, "beta");
    const zebra_pos = std.mem.indexOf(u8, formatted, "zebra");

    try testing.expect(alpha_pos != null);
    try testing.expect(beta_pos != null);
    try testing.expect(zebra_pos != null);
    try testing.expect(alpha_pos.? < beta_pos.?);
    try testing.expect(beta_pos.? < zebra_pos.?);
}
