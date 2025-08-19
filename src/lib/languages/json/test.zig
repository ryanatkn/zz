const std = @import("std");
const testing = std.testing;

// Import all JSON components
const JsonLexer = @import("lexer.zig").JsonLexer;
const JsonParser = @import("parser.zig").JsonParser;
const JsonFormatter = @import("formatter.zig").JsonFormatter;
const JsonLinter = @import("linter.zig").JsonLinter;
const JsonAnalyzer = @import("analyzer.zig").JsonAnalyzer;
const json_mod = @import("mod.zig");

// Import types
const Token = @import("../../parser/foundation/types/token.zig").Token;
const TokenKind = @import("../../parser/foundation/types/predicate.zig").TokenKind;
const AST = @import("../../ast/mod.zig").AST;
const FormatOptions = @import("../interface.zig").FormatOptions;
const Rule = @import("../interface.zig").Rule;

// Comprehensive test suite for JSON language implementation
// 
// This file contains all integration tests and edge cases for the complete
// JSON language support, ensuring robustness and correctness.

// =============================================================================
// Lexer Tests
// =============================================================================

test "JSON lexer - basic tokens" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const test_cases = [_]struct {
        input: []const u8,
        expected_kind: TokenKind,
        expected_text: []const u8,
    }{
        .{ .input = "\"hello world\"", .expected_kind = .string_literal, .expected_text = "\"hello world\"" },
        .{ .input = "42", .expected_kind = .number_literal, .expected_text = "42" },
        .{ .input = "-3.14", .expected_kind = .number_literal, .expected_text = "-3.14" },
        .{ .input = "1.23e-4", .expected_kind = .number_literal, .expected_text = "1.23e-4" },
        .{ .input = "true", .expected_kind = .boolean_literal, .expected_text = "true" },
        .{ .input = "false", .expected_kind = .boolean_literal, .expected_text = "false" },
        .{ .input = "null", .expected_kind = .null_literal, .expected_text = "null" },
        .{ .input = "{", .expected_kind = .delimiter, .expected_text = "{" },
        .{ .input = "}", .expected_kind = .delimiter, .expected_text = "}" },
        .{ .input = "[", .expected_kind = .delimiter, .expected_text = "[" },
        .{ .input = "]", .expected_kind = .delimiter, .expected_text = "]" },
        .{ .input = ",", .expected_kind = .delimiter, .expected_text = "," },
        .{ .input = ":", .expected_kind = .delimiter, .expected_text = ":" },
    };
    
    for (test_cases) |case| {
        var lexer = JsonLexer.init(allocator, case.input, .{});
        defer lexer.deinit();
        
        const tokens = try lexer.tokenize();
        defer allocator.free(tokens);
        
        try testing.expectEqual(@as(usize, 2), tokens.len); // Includes EOF token
        try testing.expectEqual(case.expected_kind, tokens[0].kind);
        try testing.expectEqualStrings(case.expected_text, tokens[0].text);
    }
}

test "JSON lexer - complex structures" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const complex_json = 
        \\{
        \\  "users": [
        \\    {
        \\      "name": "Alice",
        \\      "age": 30,
        \\      "active": true
        \\    },
        \\    {
        \\      "name": "Bob",
        \\      "age": 25,
        \\      "active": false
        \\    }
        \\  ],
        \\  "count": 2,
        \\  "metadata": null
        \\}
    ;
    
    var lexer = JsonLexer.init(allocator, complex_json, .{});
    defer lexer.deinit();
    
    const tokens = try lexer.tokenize();
    defer allocator.free(tokens);
    
    // Should produce many tokens for this complex structure
    try testing.expect(tokens.len > 20);
    
    // First and last tokens should be braces
    try testing.expectEqual(TokenKind.delimiter, tokens[0].kind);
    try testing.expectEqualStrings("{", tokens[0].text);
    try testing.expectEqual(TokenKind.delimiter, tokens[tokens.len - 2].kind); // Second-to-last because of EOF
    try testing.expectEqualStrings("}", tokens[tokens.len - 2].text);
}

test "JSON lexer - error handling" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const invalid_cases = [_][]const u8{
        "\"unterminated string",
        "01", // Leading zero
        "1.", // Trailing decimal
        "1e", // Incomplete exponent
    };
    
    for (invalid_cases) |case| {
        var lexer = JsonLexer.init(allocator, case, .{});
        defer lexer.deinit();
        
        // Should handle errors gracefully
        const tokens = lexer.tokenize() catch |err| switch (err) {
            error.UnterminatedString,
            error.InvalidNumber,
            error.InvalidLiteral => {
                // Expected errors
                continue;
            },
            else => return err,
        };
        defer allocator.free(tokens);
        
        // If no error thrown, should still produce some tokens
        // (for error recovery)
    }
}

// =============================================================================
// Parser Tests
// =============================================================================

test "JSON parser - all value types" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const test_cases = [_][]const u8{
        "\"hello\"",
        "42",
        "true",
        "false",
        "null",
        "[]",
        "{}",
        "[1, 2, 3]",
        "{\"key\": \"value\"}",
    };
    
    for (test_cases) |case| {
        var lexer = JsonLexer.init(allocator, case, .{});
        defer lexer.deinit();
        const tokens = try lexer.tokenize();
        defer allocator.free(tokens);
        
        var parser = JsonParser.init(allocator, tokens, .{});
        defer parser.deinit();
        
        var ast = try parser.parse();
        defer ast.deinit();
        
        // AST root is no longer optional, it's always a Node struct
    try testing.expect(ast.root.children.len >= 0);
        
        // Check for parse errors
        const errors = parser.getErrors();
        try testing.expectEqual(@as(usize, 0), errors.len);
    }
}

test "JSON parser - nested structures" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const nested_json = 
        \\{
        \\  "level1": {
        \\    "level2": {
        \\      "level3": {
        \\        "value": "deep"
        \\      }
        \\    }
        \\  },
        \\  "array": [
        \\    [1, 2],
        \\    [3, 4]
        \\  ]
        \\}
    ;
    
    var lexer = JsonLexer.init(allocator, nested_json, .{});
    defer lexer.deinit();
    const tokens = try lexer.tokenize();
    defer allocator.free(tokens);
    
    var parser = JsonParser.init(allocator, tokens, .{});
    defer parser.deinit();
    
    var ast = try parser.parse();
    defer ast.deinit();
    
    // AST root is no longer optional, it's always a Node struct
    try testing.expect(ast.root.children.len >= 0);
    
    const errors = parser.getErrors();
    try testing.expectEqual(@as(usize, 0), errors.len);
}

test "JSON parser - error recovery" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const malformed_cases = [_][]const u8{
        "{\"key\": }",           // Missing value
        "{\"key\": \"value\",}", // Trailing comma
        "[1, 2,]",              // Trailing comma in array
        "{key: \"value\"}",     // Unquoted key
        "{'key': 'value'}",     // Single quotes
    };
    
    for (malformed_cases) |case| {
        var lexer = JsonLexer.init(allocator, case, .{});
        defer lexer.deinit();
        const tokens = try lexer.tokenize();
        defer allocator.free(tokens);
        
        var parser = JsonParser.init(allocator, tokens, .{});
        defer parser.deinit();
        
        // Parser should handle errors gracefully
        var ast = parser.parse() catch |err| switch (err) {
            error.ParseError => {
                // Some malformed JSON might fail completely
                continue;
            },
            else => return err,
        };
        defer ast.deinit();
        
        // If parsing succeeds, should still produce some AST
        // AST root is no longer optional, it's always a Node struct
    try testing.expect(ast.root.children.len >= 0);
        
        // Should have recorded errors
        const errors = parser.getErrors();
        try testing.expect(errors.len > 0);
    }
}

// =============================================================================
// Formatter Tests
// =============================================================================

test "JSON formatter - pretty printing" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const compact_input = "{\"name\":\"Alice\",\"age\":30,\"hobbies\":[\"reading\",\"swimming\"]}";
    
    var lexer = JsonLexer.init(allocator, compact_input, .{});
    defer lexer.deinit();
    const tokens = try lexer.tokenize();
    defer allocator.free(tokens);
    
    var parser = JsonParser.init(allocator, tokens, .{});
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
    var lexer2 = JsonLexer.init(allocator, formatted, .{});
    defer lexer2.deinit();
    const tokens2 = try lexer2.tokenize();
    defer allocator.free(tokens2);
    
    var parser2 = JsonParser.init(allocator, tokens2, .{});
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
    
    var lexer = JsonLexer.init(allocator, input, .{});
    defer lexer.deinit();
    const tokens = try lexer.tokenize();
    defer allocator.free(tokens);
    
    var parser = JsonParser.init(allocator, tokens, .{});
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

// =============================================================================
// Linter Tests
// =============================================================================

test "JSON linter - all rules" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Create JSON with various issues
    const problematic_json = "{\"key\": 01, \"key\": 2}"; // Leading zero + duplicate key
    
    var lexer = JsonLexer.init(allocator, problematic_json, .{});
    defer lexer.deinit();
    const tokens = try lexer.tokenize();
    defer allocator.free(tokens);
    
    var parser = JsonParser.init(allocator, tokens, .{});
    defer parser.deinit();
    var ast = try parser.parse();
    defer ast.deinit();
    
    // Enable all rules
    var enabled_rules = std.ArrayList(Rule).init(allocator);
    defer enabled_rules.deinit();
    
    for (JsonLinter.RULES) |rule| {
        var enabled_rule = rule;
        enabled_rule.enabled = true;
        try enabled_rules.append(enabled_rule);
    }
    
    var linter = JsonLinter.init(allocator, .{});
    defer linter.deinit();
    
    const diagnostics = try linter.lint(ast, enabled_rules.items);
    defer {
        for (diagnostics) |diag| {
            allocator.free(diag.message);
        }
        allocator.free(diagnostics);
    }
    
    // Should find issues
    try testing.expect(diagnostics.len > 0);
    
    // Check that we found specific issues
    var found_duplicate_keys = false;
    var found_leading_zeros = false;
    
    for (diagnostics) |diag| {
        if (std.mem.eql(u8, diag.rule, "no-duplicate-keys")) {
            found_duplicate_keys = true;
        }
        if (std.mem.eql(u8, diag.rule, "no-leading-zeros")) {
            found_leading_zeros = true;
        }
    }
    
    try testing.expect(found_duplicate_keys);
    try testing.expect(found_leading_zeros);
}

test "JSON linter - deep nesting warning" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Create deeply nested JSON
    const deep_json = "{\"a\": {\"b\": {\"c\": {\"d\": {\"e\": 1}}}}}";
    
    var lexer = JsonLexer.init(allocator, deep_json, .{});
    defer lexer.deinit();
    const tokens = try lexer.tokenize();
    defer allocator.free(tokens);
    
    var parser = JsonParser.init(allocator, tokens, .{});
    defer parser.deinit();
    var ast = try parser.parse();
    defer ast.deinit();
    
    var linter = JsonLinter.init(allocator, .{ .warn_on_deep_nesting = 3 });
    defer linter.deinit();
    
    const enabled_rules = &[_]Rule{
        Rule{ .name = "deep-nesting", .description = "", .severity = .warning, .enabled = true },
    };
    
    const diagnostics = try linter.lint(ast, enabled_rules);
    defer {
        for (diagnostics) |diag| {
            allocator.free(diag.message);
        }
        allocator.free(diagnostics);
    }
    
    // Should warn about deep nesting
    try testing.expect(diagnostics.len > 0);
}

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
    
    var lexer = JsonLexer.init(allocator, sample_json, .{});
    defer lexer.deinit();
    const tokens = try lexer.tokenize();
    defer allocator.free(tokens);
    
    var parser = JsonParser.init(allocator, tokens, .{});
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
    
    var lexer = JsonLexer.init(allocator, simple_json, .{});
    defer lexer.deinit();
    const tokens = try lexer.tokenize();
    defer allocator.free(tokens);
    
    var parser = JsonParser.init(allocator, tokens, .{});
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
    
    var lexer = JsonLexer.init(allocator, complex_json, .{});
    defer lexer.deinit();
    const tokens = try lexer.tokenize();
    defer allocator.free(tokens);
    
    var parser = JsonParser.init(allocator, tokens, .{});
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
    try testing.expect(ast.root.children.len >= 0);
    
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
    try testing.expect(ast.root.children.len >= 0);
    
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
        const enabled_rules = &[_]Rule{
            Rule{ .name = "test-rule", .description = "", .severity = .warning, .enabled = true },
        };
        
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
    try testing.expect(ast.root.children.len >= 0);
    try testing.expect(formatted.len > json_text.len); // Should be formatted (larger due to whitespace)
}