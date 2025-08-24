const std = @import("std");
const testing = std.testing;

// Import JSON components
const JsonParser = @import("../parser/mod.zig").JsonParser;
const analyzer_module = @import("../analyzer/mod.zig");
const JsonAnalyzer = analyzer_module.JsonAnalyzer;
const JsonSchema = analyzer_module.JsonSchema;

// =============================================================================
// Analyzer Tests
// =============================================================================

test "JSON analyzer - schema extraction" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const sample_json =
        \\{
        \\  "user": {
        \\    "name": "Alice",
        \\    "age": 30,
        \\    "active": true,
        \\    "hobbies": ["reading", "swimming"]
        \\  },
        \\  "timestamp": "2023-01-01T00:00:00Z",
        \\  "count": 42
        \\}
    ;

    // Updated to streaming parser (3-arg pattern)
    var parser = try JsonParser.init(allocator, sample_json, .{});
    defer parser.deinit();
    var ast = try parser.parse();
    defer ast.deinit();

    var analyzer = JsonAnalyzer.init(allocator, .{});
    var schema = try analyzer.extractSchema(ast);
    defer schema.deinit(allocator);

    // Should be object type
    try testing.expectEqual(JsonSchema.SchemaType.object, schema.schema_type);

    // Should have properties
    try testing.expect(schema.properties != null);
    try testing.expect(schema.properties.?.count() > 0);

    // Check specific properties exist
    try testing.expect(schema.properties.?.contains("user"));
    try testing.expect(schema.properties.?.contains("timestamp"));
    try testing.expect(schema.properties.?.contains("count"));
}

test "JSON analyzer - statistics" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const complex_json =
        \\{
        \\  "strings": ["a", "b", "c"],
        \\  "numbers": [1, 2, 3],
        \\  "booleans": [true, false],
        \\  "null_value": null,
        \\  "nested": {
        \\    "inner": "value"
        \\  }
        \\}
    ;

    // Updated to streaming parser (3-arg pattern)
    var parser = try JsonParser.init(allocator, complex_json, .{});
    defer parser.deinit();
    var ast = try parser.parse();
    defer ast.deinit();

    var analyzer = JsonAnalyzer.init(allocator, .{});
    const stats = try analyzer.generateStatistics(ast);

    // Check type counts
    try testing.expect(stats.type_counts.strings > 0);
    try testing.expect(stats.type_counts.numbers > 0);
    try testing.expect(stats.type_counts.booleans > 0);
    try testing.expect(stats.type_counts.nulls > 0);
    try testing.expect(stats.type_counts.objects > 0);
    try testing.expect(stats.type_counts.arrays > 0);

    // Check depth
    try testing.expect(stats.max_depth > 1);

    // Check complexity score
    try testing.expect(stats.complexity_score > 0.0);
}
