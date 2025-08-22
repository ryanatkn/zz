const std = @import("std");
const testing = std.testing;

// Import JSON components
const JsonLexer = @import("lexer.zig").JsonLexer;
const JsonParser = @import("parser.zig").JsonParser;
const JsonAnalyzer = @import("analyzer.zig").JsonAnalyzer;

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

    var lexer = JsonLexer.init(allocator);
    const tokens = try lexer.batchTokenize(allocator, sample_json);
    defer allocator.free(tokens);

    var parser = JsonParser.init(allocator, tokens, sample_json, .{});
    defer parser.deinit();
    var ast = try parser.parse();
    defer ast.deinit();

    var analyzer = JsonAnalyzer.init(allocator, .{});
    var schema = try analyzer.extractSchema(ast);
    defer schema.deinit(allocator);

    // Should be object type
    try testing.expectEqual(JsonAnalyzer.JsonSchema.SchemaType.object, schema.schema_type);

    // Should have properties
    try testing.expect(schema.properties != null);
    try testing.expect(schema.properties.?.count() > 0);

    // Check specific properties exist
    try testing.expect(schema.properties.?.contains("user"));
    try testing.expect(schema.properties.?.contains("timestamp"));
    try testing.expect(schema.properties.?.contains("count"));
}

test "JSON analyzer - TypeScript interface generation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const simple_json = "{\"name\": \"Alice\", \"age\": 30, \"active\": true}";

    var lexer = JsonLexer.init(allocator);
    const tokens = try lexer.batchTokenize(allocator, simple_json);
    defer allocator.free(tokens);

    var parser = JsonParser.init(allocator, tokens, simple_json, .{});
    defer parser.deinit();
    var ast = try parser.parse();
    defer ast.deinit();

    var analyzer = JsonAnalyzer.init(allocator, .{});
    var interface = try analyzer.generateTypeScriptInterface(ast, "User");
    defer interface.deinit(allocator);

    // Should have correct name
    try testing.expectEqualStrings("User", interface.name);

    // Should have expected fields
    try testing.expectEqual(@as(usize, 3), interface.fields.items.len);

    // Check field names (order may vary)
    var found_name = false;
    var found_age = false;
    var found_active = false;

    for (interface.fields.items) |field| {
        if (std.mem.eql(u8, field.name, "name")) found_name = true;
        if (std.mem.eql(u8, field.name, "age")) found_age = true;
        if (std.mem.eql(u8, field.name, "active")) found_active = true;
    }

    try testing.expect(found_name);
    try testing.expect(found_age);
    try testing.expect(found_active);
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

    var lexer = JsonLexer.init(allocator);
    const tokens = try lexer.batchTokenize(allocator, complex_json);
    defer allocator.free(tokens);

    var parser = JsonParser.init(allocator, tokens, complex_json, .{});
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
