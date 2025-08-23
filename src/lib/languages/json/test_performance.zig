const std = @import("std");
const testing = std.testing;

// Import JSON module
const json_mod = @import("mod.zig");

// =============================================================================
// Performance Tests
// =============================================================================

test "JSON performance - large file handling" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Generate a large JSON structure
    var large_json = std.ArrayList(u8).init(allocator);
    defer large_json.deinit();

    try large_json.appendSlice("{\"data\": [");

    const num_items = 1000;
    for (0..num_items) |i| {
        if (i > 0) try large_json.appendSlice(", ");
        try large_json.writer().print("{{\"id\": {}, \"name\": \"item{}\", \"value\": {}}}", .{ i, i, i * 2 });
    }

    try large_json.appendSlice("]}");

    const json_text = large_json.items;

    // Time the operations
    const start_time = std.time.nanoTimestamp();

    // Parse
    var ast = try json_mod.parseJson(allocator, json_text);
    defer ast.deinit();

    const parse_time = std.time.nanoTimestamp() - start_time;

    // Should complete in reasonable time (less than 100ms for 1000 items)
    try testing.expect(parse_time < 100_000_000); // 100ms in nanoseconds

    // Format
    const format_start = std.time.nanoTimestamp();
    const formatted = try json_mod.formatJsonString(allocator, json_text);
    defer allocator.free(formatted);
    const format_time = std.time.nanoTimestamp() - format_start;

    // Should also complete in reasonable time
    try testing.expect(format_time < 100_000_000); // 100ms in nanoseconds

    // Validate performance requirements are met
    // AST root is no longer optional, it's always a Node struct
    // Check that AST was created successfully and formatting works
    try testing.expect(formatted.len > 0); // Should produce some output

    // Verify the formatted result is valid JSON by parsing it
    var ast2 = try json_mod.parseJson(allocator, formatted);
    defer ast2.deinit();
}
