/// JSON Analyzer - Combined Core and Schema Functionality
///
/// This module provides a unified interface to the split analyzer components
const std = @import("std");

// Re-export core analyzer
pub const JsonAnalyzer = @import("core.zig").JsonAnalyzer;
pub const Symbol = @import("core.zig").Symbol;

// Re-export schema functionality (accessible as analyzer.schema.*)
pub const schema = @import("schema.zig");
pub const JsonSchema = schema.JsonSchema;

// Re-export commonly used types
pub const JsonStatistics = JsonAnalyzer.JsonStatistics;
pub const AnalyzerOptions = JsonAnalyzer.AnalyzerOptions;

// ============================================================================
// Tests for Complete Analyzer Functionality
// ============================================================================

test "JSON analyzer - extract schema from simple object" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const JsonParser = @import("../parser/mod.zig").JsonParser;

    const input = "{\"name\": \"test\", \"value\": 42, \"active\": true}";

    var parser = try JsonParser.init(allocator, input, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    var analyzer = JsonAnalyzer.init(allocator, .{});
    var extracted_schema = try analyzer.extractSchema(ast);
    defer extracted_schema.deinit(allocator);

    try testing.expectEqual(JsonSchema.SchemaType.object, extracted_schema.schema_type);
    try testing.expect(extracted_schema.properties != null);
    try testing.expectEqual(@as(u32, 3), extracted_schema.properties.?.count());
}

test "JSON analyzer - generate statistics" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const JsonParser = @import("../parser/mod.zig").JsonParser;

    const input = "{\"items\": [1, 2, 3], \"count\": 3}";

    var parser = try JsonParser.init(allocator, input, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    var analyzer = JsonAnalyzer.init(allocator, .{});
    const stats = try analyzer.generateStatistics(ast);

    try testing.expect(stats.max_depth >= 2); // object -> array -> number
    try testing.expect(stats.total_keys >= 2); // "items", "count"
    try testing.expect(stats.type_counts.objects >= 1);
    try testing.expect(stats.type_counts.arrays >= 1);
    try testing.expect(stats.type_counts.numbers >= 4); // 1, 2, 3, 3
}

test "JSON analyzer - extract symbols" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const JsonParser = @import("../parser/mod.zig").JsonParser;

    const input = "{\"user\": {\"name\": \"Alice\", \"age\": 30}}";

    var parser = try JsonParser.init(allocator, input, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    var analyzer = JsonAnalyzer.init(allocator, .{});
    const symbols = try analyzer.extractSymbols(ast);
    defer {
        for (symbols) |symbol| {
            allocator.free(symbol.name);
            if (symbol.signature) |sig| allocator.free(sig);
        }
        allocator.free(symbols);
    }

    try testing.expect(symbols.len > 0);
}

// Include schema analysis tests
test {
    _ = schema;
}
