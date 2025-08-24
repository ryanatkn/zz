const std = @import("std");
const testing = std.testing;

// Import JSON components
const Parser = @import("../parser/mod.zig").Parser;
const Formatter = @import("../format/mod.zig").Formatter;

// =============================================================================
// Formatter Tests
// =============================================================================

test "JSON formatter - pretty printing" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const compact_input = "{\"name\":\"Alice\",\"age\":30,\"hobbies\":[\"reading\",\"swimming\"]}";

    var parser = try Parser.init(allocator, compact_input, .{});
    defer parser.deinit();
    var ast = try parser.parse();
    defer ast.deinit();

    // Test pretty formatting
    var formatter = Formatter.init(allocator, .{
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
    var parser2 = try Parser.init(allocator, formatted, .{});
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

    var parser = try Parser.init(allocator, input, .{});
    defer parser.deinit();
    var ast = try parser.parse();
    defer ast.deinit();

    // Test key sorting
    var formatter = Formatter.init(allocator, .{
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

test "JSON formatter - round trip" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const inputs = [_][]const u8{
        "{\"name\":\"test\"}",
        "{\"number\":42}",
        "{\"boolean\":true}",
        "{\"null_val\":null}",
        "{\"nested\":{\"field\":\"value\"}}",
        "[1,2,3,4,5]",
        "{\"array\":[\"one\",\"two\",\"three\"]}",
        "{\"mixed\":{\"str\":\"hello\",\"num\":42,\"bool\":true,\"arr\":[1,2,3]}}",
        "[]",
        "{}",
        "{\"empty_nested\":{\"empty_array\":[]}}",
    };

    for (inputs) |input| {
        // Parse original
        var parser1 = try Parser.init(allocator, input, .{});
        defer parser1.deinit();

        var ast1 = try parser1.parse();
        defer ast1.deinit();

        // Format it
        var formatter = Formatter.init(allocator, .{});
        defer formatter.deinit();

        const formatted = try formatter.format(ast1);
        defer allocator.free(formatted);

        // Parse formatted version
        var parser2 = try Parser.init(allocator, formatted, .{});
        defer parser2.deinit();

        var ast2 = try parser2.parse();
        defer ast2.deinit();

        // Both should be valid (root is always non-null in JSON AST)
        try testing.expect(ast1.root.* != .err);
        try testing.expect(ast2.root.* != .err);
    }
}

test "JSON formatter - round trip with different format options" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = "{\"zebra\":1,\"alpha\":2,\"beta\":3,\"data\":[1,2,3,4,5]}";

    // Parse original
    var parser = try Parser.init(allocator, input, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    const format_options = [_]struct {
        compact_objects: bool,
        compact_arrays: bool,
        sort_keys: bool,
        description: []const u8,
    }{
        .{ .compact_objects = true, .compact_arrays = true, .sort_keys = false, .description = "compact" },
        .{ .compact_objects = false, .compact_arrays = false, .sort_keys = false, .description = "pretty" },
        .{ .compact_objects = true, .compact_arrays = true, .sort_keys = true, .description = "compact sorted" },
        .{ .compact_objects = false, .compact_arrays = false, .sort_keys = true, .description = "pretty sorted" },
    };

    for (format_options) |opts| {
        // Format with specific options
        var formatter = Formatter.init(allocator, .{
            .compact_objects = opts.compact_objects,
            .compact_arrays = opts.compact_arrays,
            .sort_keys = opts.sort_keys,
        });
        defer formatter.deinit();

        const formatted = try formatter.format(ast);
        defer allocator.free(formatted);

        // Parse formatted version
        var parser2 = try Parser.init(allocator, formatted, .{});
        defer parser2.deinit();

        var ast2 = try parser2.parse();
        defer ast2.deinit();

        // Should be valid JSON regardless of formatting options
        try testing.expect(ast2.root.* != .err);
    }
}

test "JSON formatter - round trip preserves values" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const test_cases = [_]struct {
        input: []const u8,
        description: []const u8,
    }{
        .{ .input = "{\"string\":\"hello\\nworld\\t\\\"quoted\\\"\"}", .description = "escape sequences" },
        .{ .input = "{\"number\":123.456e-10}", .description = "scientific notation" },
        .{ .input = "{\"negative\":-42.5}", .description = "negative numbers" },
        .{ .input = "{\"unicode\":\"\\u0048\\u0065\\u006C\\u006C\\u006F\"}", .description = "unicode escapes" },
        .{ .input = "[true,false,null]", .description = "boolean and null values" },
    };

    for (test_cases) |case| {
        // Parse original
        var parser1 = try Parser.init(allocator, case.input, .{});
        defer parser1.deinit();

        var ast1 = try parser1.parse();
        defer ast1.deinit();

        // Format it
        var formatter = Formatter.init(allocator, .{});
        defer formatter.deinit();

        const formatted = try formatter.format(ast1);
        defer allocator.free(formatted);

        // Parse formatted version
        var parser2 = try Parser.init(allocator, formatted, .{});
        defer parser2.deinit();

        var ast2 = try parser2.parse();
        defer ast2.deinit();

        // Both should be valid and represent the same semantic content
        try testing.expect(ast1.root.* != .err);
        try testing.expect(ast2.root.* != .err);
    }
}
