const std = @import("std");
const testing = std.testing;

// Import ZON modules
const ZonParser = @import("../parser/mod.zig").Parser;
const ZonFormatter = @import("../format/mod.zig").Formatter;
const zon_mod = @import("../mod.zig");

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

    const num_items = 100; // Reduced for faster test
    for (0..num_items) |i| {
        if (i > 0) try large_zon.appendSlice(", ");
        try large_zon.writer().print(" .item{} = .{{ .id = {}, .name = \"item{}\", .value = {} }}", .{ i, i, i, i * 2 });
    }

    try large_zon.appendSlice(" } }");

    const zon_text = large_zon.items;

    // Time the parsing operation (streaming)
    const start_time = std.time.nanoTimestamp();

    var ast = try zon_mod.parse(allocator, zon_text);
    defer ast.deinit();

    const parse_time = std.time.nanoTimestamp() - start_time;

    // Should complete in reasonable time (less than 10ms for 100 items)
    try testing.expect(parse_time < 10_000_000); // 10ms in nanoseconds

    // Should produce valid AST
    try testing.expect(ast.root != null);
}

test "ZON performance - parsing speed" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Generate large ZON structure
    var large_zon = std.ArrayList(u8).init(allocator);
    defer large_zon.deinit();

    try large_zon.appendSlice(".{ .data = .{");

    const num_items = 500; // Smaller for parsing test
    for (0..num_items) |i| {
        if (i > 0) try large_zon.appendSlice(", ");
        try large_zon.writer().print(" .item{} = .{{ .id = {}, .name = \"item{}\" }}", .{ i, i, i });
    }

    try large_zon.appendSlice(" } }");

    const zon_text = large_zon.items;

    // Time the parsing operation
    const start_time = std.time.nanoTimestamp();

    var ast = try zon_mod.parse(allocator, zon_text);
    defer ast.deinit();

    const parse_time = std.time.nanoTimestamp() - start_time;

    // Should complete in reasonable time (less than 200ms for 500 items)
    try testing.expect(parse_time < 200_000_000); // 200ms in nanoseconds

    // Should produce valid AST
    try testing.expect(ast.root != null);
}

test "ZON performance - formatting speed" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Generate ZON structure
    const zon_text =
        \\.{
        \\    .name = "performance-test",
        \\    .version = "1.0.0",
        \\    .items = .{
        \\        .first = .{ .id = 1, .name = "first" },
        \\        .second = .{ .id = 2, .name = "second" },
        \\        .third = .{ .id = 3, .name = "third" },
        \\    },
        \\}
    ;

    // Parse first to get AST
    var ast = try zon_mod.parse(allocator, zon_text);
    defer ast.deinit();

    // Time the formatting operation
    const start_time = std.time.nanoTimestamp();

    var formatter = ZonFormatter.init(allocator, .{});
    defer formatter.deinit();

    const formatted = try formatter.format(ast);
    defer allocator.free(formatted);

    const format_time = std.time.nanoTimestamp() - start_time;

    // Should complete in reasonable time (less than 50ms)
    try testing.expect(format_time < 50_000_000); // 50ms in nanoseconds

    // Should produce valid output
    try testing.expect(formatted.len > 0);
}
