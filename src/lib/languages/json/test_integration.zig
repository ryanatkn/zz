const std = @import("std");
const testing = std.testing;

// Import JSON module and components
const json_mod = @import("mod.zig");
const JsonAnalyzer = @import("analyzer.zig").JsonAnalyzer;
const EnabledRules = @import("linter.zig").EnabledRules;

// Import types
const interface_types = @import("../interface.zig");
const FormatOptions = interface_types.FormatOptions;

// =============================================================================
// Integration Tests
// =============================================================================

test "JSON integration - complete pipeline" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const original_json =
        \\{
        \\  "users": [
        \\    {"name": "Alice", "age": 30},
        \\    {"name": "Bob", "age": 25}
        \\  ],
        \\  "metadata": {
        \\    "version": "1.0",
        \\    "created": "2023-01-01"
        \\  }
        \\}
    ;

    // Test full pipeline using module functions
    var ast = try json_mod.parseJson(allocator, original_json);
    defer ast.deinit();

    // AST root is no longer optional, it's always a Node struct
    // Check that AST was created successfully
    // ast.root is a pointer, so it's always valid if AST was created

    // Format the JSON
    const formatted = try json_mod.formatJsonString(allocator, original_json);
    defer allocator.free(formatted);

    try testing.expect(formatted.len > 0);

    // Validate the JSON
    const diagnostics = try json_mod.validateJson(allocator, original_json);
    defer {
        for (diagnostics) |diag| {
            allocator.free(diag.message);
        }
        allocator.free(diagnostics);
    }

    // Should be valid
    try testing.expectEqual(@as(usize, 0), diagnostics.len);

    // Extract schema
    var schema = try json_mod.extractJsonSchema(allocator, original_json);
    defer schema.deinit(allocator);

    try testing.expectEqual(JsonAnalyzer.JsonSchema.SchemaType.object, schema.schema_type);

    // Generate TypeScript interface
    var interface = try json_mod.generateTypeScriptInterface(allocator, original_json, "Data");
    defer interface.deinit(allocator);

    try testing.expectEqualStrings("Data", interface.name);

    // Get statistics
    const stats = try json_mod.getJsonStatistics(allocator, original_json);

    try testing.expect(stats.complexity_score > 0.0);
}

test "JSON integration - round-trip fidelity" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const test_cases = [_][]const u8{
        "\"simple string\"",
        "123.456",
        "true",
        "false",
        "null",
        "[]",
        "{}",
        "[1, 2, 3]",
        "{\"a\": 1, \"b\": 2}",
        "{\"nested\": {\"deep\": [\"array\", \"values\"]}}",
    };

    for (test_cases) |original| {
        // Parse original
        var ast1 = try json_mod.parseJson(allocator, original);
        defer ast1.deinit();

        // Format it
        const formatted = try json_mod.formatJsonString(allocator, original);
        defer allocator.free(formatted);

        // Parse formatted version
        var ast2 = try json_mod.parseJson(allocator, formatted);
        defer ast2.deinit();

        // Both should be valid
        // AST.root is non-optional now
        // AST.root is non-optional now

        // Formatted version should also be valid when re-formatted
        const formatted2 = try json_mod.formatJsonString(allocator, formatted);
        defer allocator.free(formatted2);

        // Should be stable (format(format(x)) = format(x))
        try testing.expectEqualStrings(formatted, formatted2);
    }
}

test "JSON integration - language support interface" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const support = try json_mod.getSupport(allocator);

    // Test complete workflow through interface
    const input = "{\"test\": [1, 2, 3]}";

    // Tokenize
    const tokens = try support.lexer.tokenize(allocator, input);
    defer allocator.free(tokens);

    try testing.expect(tokens.len > 0);

    // Parse
    var ast = try support.parser.parse(allocator, tokens);
    defer ast.deinit();

    // AST root is no longer optional, it's always a Node struct
    // Check that AST was created successfully
    // ast.root is a pointer, so it's always valid if AST was created

    // Format
    const options = FormatOptions{
        .indent_size = 2,
        .line_width = 80,
    };
    const formatted = try support.formatter.format(allocator, ast, options);
    defer allocator.free(formatted);

    try testing.expect(formatted.len > 0);

    // Lint
    if (support.linter) |linter| {
        var enabled_rules = EnabledRules.initEmpty();
        enabled_rules.insert(.no_duplicate_keys); // Use a real rule

        const diagnostics = try linter.lint(allocator, ast, enabled_rules);
        defer {
            for (diagnostics) |diag| {
                allocator.free(diag.message);
            }
            allocator.free(diagnostics);
        }
    }

    // Analyze
    if (support.analyzer) |analyzer| {
        const symbols = try analyzer.extractSymbols(allocator, ast);
        defer {
            for (symbols) |symbol| {
                allocator.free(symbol.name);
                if (symbol.signature) |sig| {
                    allocator.free(sig);
                }
            }
            allocator.free(symbols);
        }

        try testing.expect(symbols.len > 0);
    }
}
