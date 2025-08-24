const std = @import("std");
const testing = std.testing;

// Import JSON module and components
const json_mod = @import("../mod.zig");
const JsonAnalyzer = @import("../analyzer/mod.zig").JsonAnalyzer;
const EnabledRules = @import("../linter/mod.zig").EnabledRules;

// Import types
const interface_types = @import("../../interface.zig");
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

    // Test schema extraction
    var schema = try json_mod.extractJsonSchema(allocator, original_json);
    defer schema.deinit(allocator);

    const analyzer_module = @import("../analyzer/mod.zig");
    try testing.expectEqual(analyzer_module.JsonSchema.SchemaType.object, schema.schema_type);

    // Test statistics generation
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
    const json_lang_mod = @import("../mod.zig");
    const Language = @import("../../../core/language.zig").Language;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const json_text = "{\"test\": \"value\", \"number\": 42}";

    const json_lang = try json_lang_mod.getSupport(allocator);

    // Test interface properties
    try testing.expectEqual(Language.json, json_lang.language);

    // Parse JSON for AST-based operations
    var ast = try json_lang_mod.parse(allocator, json_text);
    defer ast.deinit();

    // Test formatting through interface (requires AST)
    const format_options = @import("../../interface.zig").FormatOptions{
        .indent_size = 2,
        .indent_style = .space,
        .line_width = 80,
        .preserve_newlines = false,
        .trailing_comma = false,
    };

    const formatted = try json_lang.formatter.formatFn(allocator, ast, format_options);
    defer allocator.free(formatted);

    try testing.expect(formatted.len > 0);

    // Test linting through interface (uses AST)
    if (json_lang.linter) |linter| {
        const default_rules = linter.getDefaultRulesFn();
        const diagnostics = try linter.lintFn(allocator, ast, default_rules);
        defer {
            for (diagnostics) |diag| {
                allocator.free(diag.rule);
                allocator.free(diag.message);
            }
            allocator.free(diagnostics);
        }

        // Should pass linting for valid JSON
        for (diagnostics) |diagnostic| {
            if (diagnostic.severity == .err) {
                return error.UnexpectedLintError;
            }
        }
    }

    // Test analysis through interface
    if (json_lang.analyzer) |analyzer| {
        const symbols = try analyzer.extractSymbolsFn(allocator, ast);
        defer {
            for (symbols) |symbol| {
                allocator.free(symbol.name);
                if (symbol.signature) |sig| {
                    allocator.free(sig);
                }
                if (symbol.documentation) |doc| {
                    allocator.free(doc);
                }
            }
            allocator.free(symbols);
        }

        try testing.expect(symbols.len > 0);
    }
}
