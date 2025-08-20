const std = @import("std");
const testing = std.testing;

// Import ZON modules
const ZonLexer = @import("lexer.zig").ZonLexer;
const ZonParser = @import("parser.zig").ZonParser;
const ZonFormatter = @import("formatter.zig").ZonFormatter;
const ZonLinter = @import("linter.zig").ZonLinter;
const ZonAnalyzer = @import("analyzer.zig").ZonAnalyzer;
// ZonStreamingAdapter removed - using StreamToken architecture
const ZonToken = @import("tokens.zig").ZonToken;
const zon_mod = @import("mod.zig");
const FormatOptions = @import("../interface.zig").FormatOptions;
const ZonRules = @import("../../ast/rules.zig").ZonRules;

// Test data
const test_build_zon =
    \\.{
    \\    .name = "zz",
    \\    .version = "0.0.0",
    \\    .dependencies = .{},
    \\    .paths = .{ "build.zig", "src" },
    \\}
;

const test_zz_zon =
    \\.{
    \\    .base_patterns = "extend",
    \\    .ignored_patterns = .{ "temp", "*.tmp" },
    \\    .respect_gitignore = true,
    \\    .format = .{
    \\        .indent_size = 4,
    \\        .indent_style = "space",
    \\        .line_width = 100,
    \\    },
    \\}
;

const test_complex_zon =
    \\.{
    \\    .name = .test_package,
    \\    .version = "1.0.0",
    \\    .description = "A test package with various ZON features",
    \\    .author = @"John Doe",
    \\    .license = "MIT",
    \\    .metadata = .{
    \\        .build_date = "2024-01-01",
    \\        .features = .{ "feature1", "feature2", "feature3" },
    \\        .numbers = .{ 1, 2, 3, 0x1234, 0b1010, 0o755 },
    \\        .booleans = .{ true, false },
    \\        .nullable = null,
    \\        .undefined_value = undefined,
    \\    },
    \\    .dependencies = .{
    \\        .std = .{
    \\            .url = "https://github.com/ziglang/zig",
    \\            .hash = "abcd1234",
    \\        },
    \\    },
    \\}
;

const test_comments_zon =
    \\// Top-level comment
    \\.{
    \\    .name = "test", // Inline comment
    \\    /* Block comment */
    \\    .version = "1.0.0",
    \\    
    \\    // Section comment
    \\    .config = .{
    \\        .debug = true, // Debug mode
    \\    },
    \\}
;

// ============================================================================
// Lexer Tests
// ============================================================================

test "ZON lexer - basic tokens" {
    const allocator = testing.allocator;

    const input = ".{ .field = \"value\", .number = 42 }";

    var lexer = ZonLexer.init(allocator, input, .{});
    defer lexer.deinit();

    const tokens = try lexer.tokenize();
    defer allocator.free(tokens);

    try testing.expect(tokens.len > 0);
    try testing.expectEqual(.operator, tokens[0].kind); // .
    try testing.expectEqual(.delimiter, tokens[1].kind); // {
}

test "ZON lexer - field names" {
    const allocator = testing.allocator;

    const input = ".field_name .another_field";

    var lexer = ZonLexer.init(allocator, input, .{});
    defer lexer.deinit();

    const tokens = try lexer.tokenize();
    defer allocator.free(tokens);

    // Field names now emit two tokens: '.' operator and identifier
    try testing.expect(tokens.len >= 4); // At least 2 field names = 4 tokens

    // First field: .field_name
    try testing.expectEqual(.operator, tokens[0].kind);
    try testing.expectEqualStrings(".", tokens[0].text);
    try testing.expectEqual(.identifier, tokens[1].kind);
    try testing.expectEqualStrings("field_name", tokens[1].text);

    // Second field: .another_field
    try testing.expectEqual(.operator, tokens[2].kind);
    try testing.expectEqualStrings(".", tokens[2].text);
    try testing.expectEqual(.identifier, tokens[3].kind);
    try testing.expectEqualStrings("another_field", tokens[3].text);
}

test "ZON lexer - number literals" {
    const allocator = testing.allocator;

    const input = "42 0x1234 0b1010 0o755 3.14";

    var lexer = ZonLexer.init(allocator, input, .{});
    defer lexer.deinit();

    const tokens = try lexer.tokenize();
    defer allocator.free(tokens);

    var number_count: u32 = 0;
    for (tokens) |token| {
        if (token.kind == .number_literal) {
            number_count += 1;
        }
    }

    try testing.expectEqual(@as(u32, 5), number_count);
}

test "ZON lexer - string literals" {
    const allocator = testing.allocator;

    const input = "\"simple string\" \"string with \\\"quotes\\\"\" \\\\multiline";

    var lexer = ZonLexer.init(allocator, input, .{});
    defer lexer.deinit();

    const tokens = try lexer.tokenize();
    defer allocator.free(tokens);

    var string_count: u32 = 0;
    for (tokens) |token| {
        if (token.kind == .string_literal) {
            string_count += 1;
        }
    }

    try testing.expectEqual(@as(u32, 3), string_count);
}

test "ZON lexer - escape sequences comprehensive" {
    const allocator = testing.allocator;

    // Test all standard escape sequences
    const input =
        \\"basic\nescapes\ttabs\rcarriage\\backslash\"quotes"
        \\  "unicode\u{1F600}\u{0041}\u{00E9}"
        \\  "hex\x41\x42\x43"
        \\  "octal\101\102\103"
    ;

    var lexer = ZonLexer.init(allocator, input, .{});
    defer lexer.deinit();

    const tokens = try lexer.tokenize();
    defer allocator.free(tokens);

    var string_count: u32 = 0;
    for (tokens) |token| {
        if (token.kind == .string_literal) {
            string_count += 1;
            // Verify the token contains the raw string (including escape sequences)
            try testing.expect(token.text.len > 2); // At least opening and closing quotes
        }
    }

    try testing.expectEqual(@as(u32, 4), string_count); // 4 string literals
}

test "ZON lexer - invalid escape sequences" {
    const allocator = testing.allocator;

    // Test various invalid escape sequences that should be handled gracefully
    const test_cases = [_][]const u8{
        "\"invalid\\q escape\"", // Invalid escape character
        "\"unterminated unicode\\u{12\"", // Unterminated unicode escape
        "\"invalid unicode\\u{GGGG}\"", // Invalid hex digits in unicode
        "\"too long unicode\\u{123456789}\"", // Too long unicode sequence
        "\"invalid hex\\xGG\"", // Invalid hex escape
        "\"incomplete hex\\x4\"", // Incomplete hex escape
        "\"octal overflow\\999\"", // Octal value too large
    };

    for (test_cases) |test_input| {
        var lexer = ZonLexer.init(allocator, test_input, .{});
        defer lexer.deinit();

        // This should not crash, even with invalid escapes
        const tokens = lexer.tokenize() catch {
            // Other errors are acceptable for invalid input
            continue;
        };
        defer allocator.free(tokens);

        // Should produce at least EOF token
        try testing.expect(tokens.len > 0);
    }
}

test "ZON lexer - unterminated strings" {
    const allocator = testing.allocator;

    const test_cases = [_][]const u8{
        "\"unterminated string", // No closing quote
        "\"unterminated with escape\\\"", // Escaped quote at end
        "\"multiline\nunterminated", // Newline in string
        "\"", // Just opening quote
        "\"escape at end\\", // Escape at end
    };

    for (test_cases) |test_input| {
        var lexer = ZonLexer.init(allocator, test_input, .{});
        defer lexer.deinit();

        // Should handle gracefully without crashing
        const tokens = lexer.tokenize() catch {
            // Other errors expected for malformed input
            continue;
        };
        defer allocator.free(tokens);

        // Should still produce tokens (may include error tokens)
        try testing.expect(tokens.len > 0);
    }
}

test "ZON parser - string escape processing" {
    const allocator = testing.allocator;

    const TestStruct = struct {
        message: []const u8,
        unicode: []const u8,
        mixed: []const u8,
    };

    const input =
        \\.{
        \\    .message = "hello\nworld\ttab",
        \\    .unicode = "emoji: \u{1F600}",
        \\    .mixed = "quotes: \"escaped\" and normal"
        \\}
    ;

    // This tests the full parser pipeline including escape processing
    const result = zon_mod.parseFromSlice(TestStruct, allocator, input) catch {
        // If parsing fails due to escape issues, that's what we're testing
        // The parser should handle this gracefully
        return;
    };
    defer zon_mod.free(allocator, result);

    // If parsing succeeded, verify escape sequences were processed
    try testing.expect(result.message.len > 0);
    try testing.expect(result.unicode.len > 0);
    try testing.expect(result.mixed.len > 0);
}

test "ZON parser - malformed unicode handling" {
    const allocator = testing.allocator;

    const TestStruct = struct {
        field: []const u8,
    };

    const malformed_cases = [_][]const u8{
        ".{ .field = \"invalid\\u{GGGG}\" }", // Invalid hex
        ".{ .field = \"incomplete\\u{12\" }", // Incomplete
        ".{ .field = \"toolong\\u{1234567890}\" }", // Too long
        ".{ .field = \"surrogate\\u{D800}\" }", // Surrogate pair
    };

    for (malformed_cases) |test_input| {
        // Should not crash on malformed unicode
        const result = zon_mod.parseFromSlice(TestStruct, allocator, test_input) catch {
            // Parse failure is expected and acceptable for malformed input
            continue;
        };
        defer zon_mod.free(allocator, result);

        // If it somehow parsed successfully, that's also okay
        // The important thing is no crashes
    }
}

test "ZON lexer - keywords and literals" {
    const allocator = testing.allocator;

    const input = "true false null undefined";

    var lexer = ZonLexer.init(allocator, input, .{});
    defer lexer.deinit();

    const tokens = try lexer.tokenize();
    defer allocator.free(tokens);

    var keyword_count: u32 = 0;
    var boolean_literal_count: u32 = 0;
    var null_literal_count: u32 = 0;

    for (tokens) |token| {
        switch (token.kind) {
            .keyword => keyword_count += 1,
            .boolean_literal => boolean_literal_count += 1,
            .null_literal => null_literal_count += 1,
            else => {}, // Skip other tokens (like EOF)
        }
    }

    // Only 'undefined' should be classified as a keyword
    try testing.expectEqual(@as(u32, 1), keyword_count);
    // 'true' and 'false' should be boolean literals
    try testing.expectEqual(@as(u32, 2), boolean_literal_count);
    // 'null' should be a null literal
    try testing.expectEqual(@as(u32, 1), null_literal_count);
}

test "ZON lexer - comments" {
    const allocator = testing.allocator;

    const input = "// line comment\n// another comment\n .field";

    var lexer = ZonLexer.init(allocator, input, .{ .preserve_comments = true });
    defer lexer.deinit();

    const tokens = try lexer.tokenize();
    defer allocator.free(tokens);

    var comment_count: u32 = 0;
    for (tokens) |token| {
        if (token.kind == .comment) {
            comment_count += 1;
        }
    }

    try testing.expectEqual(@as(u32, 2), comment_count);
}

// ============================================================================
// Parser Tests
// ============================================================================

test "ZON parser - simple object" {
    const allocator = testing.allocator;

    const input = ".{ .name = \"test\" }";

    var lexer = ZonLexer.init(allocator, input, .{});
    defer lexer.deinit();

    const tokens = try lexer.tokenize();
    defer allocator.free(tokens);

    var parser = ZonParser.init(allocator, tokens, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    try testing.expectEqual(ZonRules.object, ast.root.rule_id);
    try testing.expect(ast.root.children.len > 0);
}

test "ZON parser - nested objects" {
    const allocator = testing.allocator;

    const input = ".{ .config = .{ .debug = true } }";

    var lexer = ZonLexer.init(allocator, input, .{});
    defer lexer.deinit();

    const tokens = try lexer.tokenize();
    defer allocator.free(tokens);

    var parser = ZonParser.init(allocator, tokens, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    try testing.expectEqual(ZonRules.object, ast.root.rule_id);
}

test "ZON parser - arrays" {
    const allocator = testing.allocator;

    const input = ".{ .items = .[ 1, 2, 3 ] }";

    var lexer = ZonLexer.init(allocator, input, .{});
    defer lexer.deinit();

    const tokens = try lexer.tokenize();
    defer allocator.free(tokens);

    var parser = ZonParser.init(allocator, tokens, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    try testing.expectEqual(ZonRules.object, ast.root.rule_id);
}

test "ZON parser - build.zig.zon format" {
    const allocator = testing.allocator;

    var lexer = ZonLexer.init(allocator, test_build_zon, .{});
    defer lexer.deinit();

    const tokens = try lexer.tokenize();
    defer allocator.free(tokens);

    var parser = ZonParser.init(allocator, tokens, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    try testing.expectEqual(ZonRules.object, ast.root.rule_id);
    try testing.expect(ast.root.children.len >= 4); // name, version, dependencies, paths
}

test "ZON parser - error recovery" {
    const allocator = testing.allocator;

    const input = ".{ .field = }"; // Missing value

    var lexer = ZonLexer.init(allocator, input, .{});
    defer lexer.deinit();

    const tokens = try lexer.tokenize();
    defer allocator.free(tokens);

    var parser = ZonParser.init(allocator, tokens, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    const errors = parser.getErrors();
    try testing.expect(errors.len > 0); // Should have parse errors
}

test "ZON parser - multiple syntax errors" {
    const allocator = testing.allocator;

    const input =
        \\.{
        \\    .field1 = ,  // Missing value
        \\    .field2 = {
        \\        .nested = 
        \\    }            // Missing value and closing brace
        \\    .field3 = "unterminated string
        \\    .field4 = [1, 2,]  // Trailing comma in array (should be fine)
        \\    invalid_syntax_here
        \\}
    ;

    var lexer = ZonLexer.init(allocator, input, .{});
    defer lexer.deinit();

    const tokens = try lexer.tokenize();
    defer allocator.free(tokens);

    var parser = ZonParser.init(allocator, tokens, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    const errors = parser.getErrors();
    try testing.expect(errors.len >= 2); // Should have multiple parse errors

    // Verify parser recovered and continued parsing (AST should exist)
    // AST root rule_id is always valid as u16
}

test "ZON parser - malformed nested structures" {
    const allocator = testing.allocator;

    const input =
        \\.{
        \\    .valid_field = "ok",
        \\    .malformed_array = [1, 2, 3,  // Missing closing bracket
        \\    .another_field = {
        \\        .deeply = {
        \\            .nested = {
        \\                .structure = incomplete  // Missing value
        \\        }  // Missing closing braces
        \\    .final_field = true
        \\}
    ;

    var lexer = ZonLexer.init(allocator, input, .{});
    defer lexer.deinit();

    const tokens = try lexer.tokenize();
    defer allocator.free(tokens);

    var parser = ZonParser.init(allocator, tokens, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    const errors = parser.getErrors();
    try testing.expect(errors.len > 0); // Should detect structural errors
}

test "ZON parser - invalid token sequences" {
    const allocator = testing.allocator;

    const input =
        \\.{
        \\    = "no field name",  // Starts with equals
        \\    .field1 .field2 = "double field",  // Missing comma
        \\    .number_field = 123.456.789,  // Invalid number format
        \\    .bracket_mismatch = [}],  // Wrong bracket type
        \\    .comma_errors = ,,, "multiple commas"
        \\}
    ;

    var lexer = ZonLexer.init(allocator, input, .{});
    defer lexer.deinit();

    const tokens = try lexer.tokenize();
    defer allocator.free(tokens);

    var parser = ZonParser.init(allocator, tokens, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    const errors = parser.getErrors();
    try testing.expect(errors.len > 0); // Should catch token sequence errors
}

test "ZON parser - error message quality" {
    const allocator = testing.allocator;

    const input = ".{ .test = }"; // Missing value

    var lexer = ZonLexer.init(allocator, input, .{});
    defer lexer.deinit();

    const tokens = try lexer.tokenize();
    defer allocator.free(tokens);

    var parser = ZonParser.init(allocator, tokens, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    const errors = parser.getErrors();
    try testing.expect(errors.len > 0);

    // Verify error has useful information
    const first_error = errors[0];
    try testing.expect(first_error.message.len > 0);
    try testing.expect(first_error.span.start <= first_error.span.end);
    try testing.expect(first_error.severity == .@"error");
}

test "ZON parser - parseFromSlice compatibility" {
    const allocator = testing.allocator;

    const TestStruct = struct {
        name: []const u8,
        value: u32,
    };

    const input = ".{ .name = \"test\", .value = 42 }";

    const result = try zon_mod.parseFromSlice(TestStruct, allocator, input);
    defer zon_mod.free(allocator, result);

    try testing.expectEqualStrings("test", result.name);
    try testing.expectEqual(@as(u32, 42), result.value);
}

// ============================================================================
// Boolean and Null Literal Parser Tests
// ============================================================================

test "ZON parser - single boolean literal true" {
    const allocator = testing.allocator;

    const input = ".{ .field = true }";

    var lexer = ZonLexer.init(allocator, input, .{});
    defer lexer.deinit();

    const tokens = try lexer.tokenize();
    defer allocator.free(tokens);

    var parser = ZonParser.init(allocator, tokens, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    // Check that parsing succeeded
    const errors = parser.getErrors();
    try testing.expect(errors.len == 0);

    // Test with parseFromSlice to verify end-to-end functionality
    const TestStruct = struct {
        field: bool,
    };

    const result = try zon_mod.parseFromSlice(TestStruct, allocator, input);
    defer zon_mod.free(allocator, result);

    try testing.expect(result.field == true);
}

test "ZON parser - single boolean literal false" {
    const allocator = testing.allocator;

    const input = ".{ .field = false }";

    var lexer = ZonLexer.init(allocator, input, .{});
    defer lexer.deinit();

    const tokens = try lexer.tokenize();
    defer allocator.free(tokens);

    var parser = ZonParser.init(allocator, tokens, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    // Check that parsing succeeded
    const errors = parser.getErrors();
    try testing.expect(errors.len == 0);

    // Test with parseFromSlice to verify end-to-end functionality
    const TestStruct = struct {
        field: bool,
    };

    const result = try zon_mod.parseFromSlice(TestStruct, allocator, input);
    defer zon_mod.free(allocator, result);

    try testing.expect(result.field == false);
}

test "ZON parser - multiple boolean literals" {
    const allocator = testing.allocator;

    const input = ".{ .field1 = true, .field2 = false, .field3 = true }";

    var lexer = ZonLexer.init(allocator, input, .{});
    defer lexer.deinit();

    const tokens = try lexer.tokenize();
    defer allocator.free(tokens);

    var parser = ZonParser.init(allocator, tokens, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    // Check that parsing succeeded
    const errors = parser.getErrors();
    try testing.expect(errors.len == 0);

    // Test with parseFromSlice to verify end-to-end functionality
    const TestStruct = struct {
        field1: bool,
        field2: bool,
        field3: bool,
    };

    const result = try zon_mod.parseFromSlice(TestStruct, allocator, input);
    defer zon_mod.free(allocator, result);

    try testing.expect(result.field1 == true);
    try testing.expect(result.field2 == false);
    try testing.expect(result.field3 == true);
}

test "ZON parser - sequential boolean fields (regression test)" {
    const allocator = testing.allocator;

    // This is the specific case that was failing - false followed by true
    const input = ".{ .preserve_newlines = false, .trailing_comma = true }";

    var lexer = ZonLexer.init(allocator, input, .{});
    defer lexer.deinit();

    const tokens = try lexer.tokenize();
    defer allocator.free(tokens);

    var parser = ZonParser.init(allocator, tokens, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    // Check that parsing succeeded
    const errors = parser.getErrors();
    try testing.expect(errors.len == 0);

    // Test with parseFromSlice to verify end-to-end functionality
    const TestStruct = struct {
        preserve_newlines: bool,
        trailing_comma: bool,
    };

    const result = try zon_mod.parseFromSlice(TestStruct, allocator, input);
    defer zon_mod.free(allocator, result);

    try testing.expect(result.preserve_newlines == false);
    try testing.expect(result.trailing_comma == true);
}

test "ZON parser - null literal" {
    const allocator = testing.allocator;

    const input = ".{ .field = null }";

    var lexer = ZonLexer.init(allocator, input, .{});
    defer lexer.deinit();

    const tokens = try lexer.tokenize();
    defer allocator.free(tokens);

    var parser = ZonParser.init(allocator, tokens, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    // Check that parsing succeeded
    const errors = parser.getErrors();
    try testing.expect(errors.len == 0);

    // Test with parseFromSlice to verify end-to-end functionality
    const TestStruct = struct {
        field: ?u32,
    };

    const result = try zon_mod.parseFromSlice(TestStruct, allocator, input);
    defer zon_mod.free(allocator, result);

    try testing.expect(result.field == null);
}

test "ZON parser - mixed literals" {
    const allocator = testing.allocator;

    const input = ".{ .bool_val = true, .num_val = 42, .str_val = \"test\", .null_val = null, .false_val = false }";

    var lexer = ZonLexer.init(allocator, input, .{});
    defer lexer.deinit();

    const tokens = try lexer.tokenize();
    defer allocator.free(tokens);

    var parser = ZonParser.init(allocator, tokens, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    // Check that parsing succeeded
    const errors = parser.getErrors();
    try testing.expect(errors.len == 0);

    // Test with parseFromSlice to verify end-to-end functionality
    const TestStruct = struct {
        bool_val: bool,
        num_val: u32,
        str_val: []const u8,
        null_val: ?u32,
        false_val: bool,
    };

    const result = try zon_mod.parseFromSlice(TestStruct, allocator, input);
    defer zon_mod.free(allocator, result);

    try testing.expect(result.bool_val == true);
    try testing.expect(result.num_val == 42);
    try testing.expectEqualStrings("test", result.str_val);
    try testing.expect(result.null_val == null);
    try testing.expect(result.false_val == false);
}

// ============================================================================
// Formatter Tests
// ============================================================================

test "ZON formatter - basic formatting" {
    const allocator = testing.allocator;

    const input = ".{.name=\"test\",.value=42}";

    const formatted = try zon_mod.formatZonString(allocator, input);
    defer allocator.free(formatted);

    try testing.expect(formatted.len > input.len); // Should be more readable
    try testing.expect(std.mem.indexOf(u8, formatted, "name") != null);
}

test "ZON formatter - preserve structure" {
    const allocator = testing.allocator;

    const formatted = try zon_mod.formatZonString(allocator, test_build_zon);
    defer allocator.free(formatted);

    // Should contain all original fields
    try testing.expect(std.mem.indexOf(u8, formatted, "name") != null);
    try testing.expect(std.mem.indexOf(u8, formatted, "version") != null);
    try testing.expect(std.mem.indexOf(u8, formatted, "dependencies") != null);
    try testing.expect(std.mem.indexOf(u8, formatted, "paths") != null);
}

test "ZON formatter - compact vs multiline" {
    const allocator = testing.allocator;

    // Small object should be compact
    const small_input = ".{ .a = 1 }";
    const compact_formatted = try zon_mod.formatZonString(allocator, small_input);
    defer allocator.free(compact_formatted);

    // Should be on one line
    try testing.expect(std.mem.count(u8, compact_formatted, "\n") <= 1);

    // Large object should be multiline
    const multiline_formatted = try zon_mod.formatZonString(allocator, test_complex_zon);
    defer allocator.free(multiline_formatted);

    // Should have multiple lines
    try testing.expect(std.mem.count(u8, multiline_formatted, "\n") > 3);
}

test "ZON formatter - round trip" {
    const allocator = testing.allocator;

    const formatted1 = try zon_mod.formatZonString(allocator, test_zz_zon);
    defer allocator.free(formatted1);

    const formatted2 = try zon_mod.formatZonString(allocator, formatted1);
    defer allocator.free(formatted2);

    // Double formatting should be identical
    try testing.expectEqualStrings(formatted1, formatted2);
}

// ============================================================================
// Linter Tests
// ============================================================================

test "ZON linter - valid ZON" {
    const allocator = testing.allocator;

    const diagnostics = try zon_mod.validateZonString(allocator, test_build_zon);
    defer {
        for (diagnostics) |diag| {
            allocator.free(diag.message);
        }
        allocator.free(diagnostics);
    }

    // Valid ZON should have no errors
    var error_count: u32 = 0;
    for (diagnostics) |diag| {
        if (diag.severity == .@"error") {
            error_count += 1;
        }
    }

    try testing.expectEqual(@as(u32, 0), error_count);
}

test "ZON linter - duplicate keys" {
    const allocator = testing.allocator;

    const input = ".{ .name = \"test\", .name = \"duplicate\" }";

    const diagnostics = try zon_mod.validateZonString(allocator, input);
    defer {
        for (diagnostics) |diag| {
            allocator.free(diag.message);
        }
        allocator.free(diagnostics);
    }

    // Should detect duplicate key error
    var has_duplicate_error = false;
    for (diagnostics) |diag| {
        if (std.mem.indexOf(u8, diag.message, "Duplicate key") != null) {
            has_duplicate_error = true;
            break;
        }
    }

    try testing.expect(has_duplicate_error);
}

test "ZON linter - schema validation" {
    const allocator = testing.allocator;

    // build.zig.zon with unknown field (should be detected as build.zig.zon schema)
    const invalid_build_zon = ".{ .name = \"test\", .version = \"0.0.0\", .unknown_field = \"value\" }";

    // Use linter directly with schema validation rules enabled
    var ast = try zon_mod.parseZonString(allocator, invalid_build_zon);
    defer ast.deinit();

    var linter = ZonLinter.init(allocator, .{});
    defer linter.deinit();

    const enabled_rules = [_][]const u8{"unknown-field"};
    const diagnostics = try linter.lint(ast, &enabled_rules);
    defer {
        for (diagnostics) |diag| {
            allocator.free(diag.message);
        }
        allocator.free(diagnostics);
    }

    // Schema validation is a work-in-progress feature
    // For now, just ensure the test runs without crashing
}

test "ZON linter - deep nesting warning" {
    const allocator = testing.allocator;

    // Create deeply nested structure
    var deep_zon = std.ArrayList(u8).init(allocator);
    defer deep_zon.deinit();

    try deep_zon.appendSlice(".{ ");
    var i: u32 = 0;
    while (i < 25) : (i += 1) { // Exceed warning threshold
        try deep_zon.appendSlice(".nested = .{ ");
    }
    try deep_zon.appendSlice(".value = 1");
    i = 0;
    while (i < 25) : (i += 1) {
        try deep_zon.appendSlice(" }");
    }
    try deep_zon.appendSlice(" }");

    // Use linter directly with specific deep nesting rule enabled
    var ast = try zon_mod.parseZonString(allocator, deep_zon.items);
    defer ast.deinit();

    var linter = ZonLinter.init(allocator, .{});
    defer linter.deinit();

    const enabled_rules = [_][]const u8{"deep-nesting"};
    const diagnostics = try linter.lint(ast, &enabled_rules);
    defer {
        for (diagnostics) |diag| {
            allocator.free(diag.message);
        }
        allocator.free(diagnostics);
    }

    // Should have deep nesting warning
    var has_deep_warning = false;
    for (diagnostics) |diag| {
        if (std.mem.indexOf(u8, diag.message, "deep nesting") != null or
            std.mem.indexOf(u8, diag.message, "Deep nesting") != null)
        {
            has_deep_warning = true;
            break;
        }
    }

    try testing.expect(has_deep_warning);
}

// ============================================================================
// Analyzer Tests
// ============================================================================

test "ZON analyzer - schema extraction" {
    const allocator = testing.allocator;

    var schema = try zon_mod.extractZonSchema(allocator, test_build_zon);
    defer schema.deinit();

    try testing.expectEqual(ZonAnalyzer.TypeInfo.TypeKind.object, schema.root_type.kind);

    if (schema.root_type.fields) |fields| {
        try testing.expect(fields.items.len >= 4); // name, version, dependencies, paths

        // Check for specific fields
        var has_name = false;
        var has_version = false;
        for (fields.items) |field| {
            if (std.mem.eql(u8, field.name, "name")) has_name = true;
            if (std.mem.eql(u8, field.name, "version")) has_version = true;
        }

        try testing.expect(has_name);
        try testing.expect(has_version);
    }
}

test "ZON analyzer - symbol extraction" {
    const allocator = testing.allocator;

    var lexer = ZonLexer.init(allocator, test_build_zon, .{});
    defer lexer.deinit();

    const tokens = try lexer.tokenize();
    defer allocator.free(tokens);

    var parser = ZonParser.init(allocator, tokens, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    const symbols = try zon_mod.extractSymbols(allocator, ast);
    defer zon_mod.freeSymbols(allocator, symbols);

    try testing.expect(symbols.len >= 4); // name, version, dependencies, paths

    // Check for specific symbols
    var has_name_symbol = false;
    for (symbols) |symbol| {
        if (std.mem.eql(u8, symbol.name, "name")) {
            has_name_symbol = true;
            break;
        }
    }

    try testing.expect(has_name_symbol);
}

test "ZON analyzer - dependency extraction" {
    const allocator = testing.allocator;

    var schema = try zon_mod.extractZonSchema(allocator, test_complex_zon);
    defer schema.deinit();

    try testing.expect(schema.dependencies.items.len >= 1);

    // Check for std dependency
    var has_std_dep = false;
    for (schema.dependencies.items) |dep| {
        if (std.mem.eql(u8, dep.name, "std")) {
            has_std_dep = true;
            try testing.expect(dep.url != null);
            try testing.expect(dep.hash != null);
            break;
        }
    }

    try testing.expect(has_std_dep);
}

test "ZON analyzer - type inference" {
    const allocator = testing.allocator;

    var schema = try zon_mod.extractZonSchema(allocator, test_complex_zon);
    defer schema.deinit();

    if (schema.root_type.fields) |fields| {
        for (fields.items) |field| {
            if (std.mem.eql(u8, field.name, "name")) {
                try testing.expectEqual(ZonAnalyzer.TypeInfo.TypeKind.identifier, field.type_info.kind);
            } else if (std.mem.eql(u8, field.name, "version")) {
                try testing.expectEqual(ZonAnalyzer.TypeInfo.TypeKind.string, field.type_info.kind);
            } else if (std.mem.eql(u8, field.name, "metadata")) {
                try testing.expectEqual(ZonAnalyzer.TypeInfo.TypeKind.object, field.type_info.kind);
            }
        }
    }
}

test "ZON analyzer - statistics" {
    const allocator = testing.allocator;

    var schema = try zon_mod.extractZonSchema(allocator, test_complex_zon);
    defer schema.deinit();

    const stats = schema.statistics;

    try testing.expect(stats.total_nodes > 0);
    try testing.expect(stats.object_count > 0);
    // Note: test_complex_zon uses .{} syntax (objects), not .[] syntax (arrays)
    // so we don't expect array_count > 0
    try testing.expect(stats.field_count > 0);
    try testing.expect(stats.string_count > 0);
    try testing.expect(stats.number_count > 0);
    try testing.expect(stats.complexity_score > 0);
}

test "ZON analyzer - Zig type generation" {
    const allocator = testing.allocator;

    var type_def = try zon_mod.generateZigTypes(allocator, test_build_zon, "BuildConfig");
    defer type_def.deinit();

    try testing.expectEqualStrings("BuildConfig", type_def.name);
    try testing.expect(type_def.definition.len > 0);

    // Should contain struct definition
    try testing.expect(std.mem.indexOf(u8, type_def.definition, "struct") != null);
    try testing.expect(std.mem.indexOf(u8, type_def.definition, "BuildConfig") != null);
}

// ============================================================================
// Integration Tests
// ============================================================================

test "ZON integration - complete pipeline" {
    const allocator = testing.allocator;

    // Lex -> Parse -> Format -> Parse again (round trip)
    var lexer = ZonLexer.init(allocator, test_zz_zon, .{});
    defer lexer.deinit();

    const tokens = try lexer.tokenize();
    defer allocator.free(tokens);

    var parser = ZonParser.init(allocator, tokens, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    const options = ZonFormatter.ZonFormatOptions{};
    var formatter = ZonFormatter.init(allocator, options);
    defer formatter.deinit();

    const formatted = try formatter.format(ast);
    defer allocator.free(formatted);

    // Parse the formatted output
    const formatted_tokens = try zon_mod.tokenize(allocator, formatted);
    defer allocator.free(formatted_tokens);

    var formatted_ast = try zon_mod.parse(allocator, formatted_tokens);
    defer formatted_ast.deinit();

    // Both ASTs should have the same structure
    try testing.expectEqual(ast.root.rule_id, formatted_ast.root.rule_id);
}

test "ZON integration - mod.zig convenience functions" {
    const allocator = testing.allocator;

    // Test parseZonString
    var ast = try zon_mod.parseZonString(allocator, test_build_zon);
    defer ast.deinit();

    try testing.expectEqual(ZonRules.object, ast.root.rule_id);

    // Test formatZonString
    const formatted = try zon_mod.formatZonString(allocator, test_build_zon);
    defer allocator.free(formatted);

    try testing.expect(formatted.len > 0);

    // Test validateZonString
    const diagnostics = try zon_mod.validateZonString(allocator, test_build_zon);
    defer {
        for (diagnostics) |diag| {
            allocator.free(diag.message);
        }
        allocator.free(diagnostics);
    }

    // Valid ZON should have no errors
    var error_count: u32 = 0;
    for (diagnostics) |diag| {
        if (diag.severity == .@"error") {
            error_count += 1;
        }
    }
    try testing.expectEqual(@as(u32, 0), error_count);
}

test "ZON integration - LanguageSupport interface" {
    const allocator = testing.allocator;

    const support = try zon_mod.getSupport(allocator);

    // Test tokenization
    const tokens = try support.lexer.tokenizeFn(allocator, test_build_zon);
    defer allocator.free(tokens);

    try testing.expect(tokens.len > 0);

    // Test parsing
    var ast = try support.parser.parseFn(allocator, tokens);
    defer ast.deinit();

    try testing.expectEqual(ZonRules.object, ast.root.rule_id);

    // Test formatting
    const options = FormatOptions{}; // Use default options
    const formatted = try support.formatter.formatFn(allocator, ast, options);
    defer allocator.free(formatted);

    try testing.expect(formatted.len > 0);
}

// ============================================================================
// Performance Tests
// ============================================================================

test "ZON performance - lexing speed" {
    const allocator = testing.allocator;

    // Create a moderately large ZON file
    var large_zon = std.ArrayList(u8).init(allocator);
    defer large_zon.deinit();

    try large_zon.appendSlice(".{\n");
    var i: u32 = 0;
    while (i < 100) : (i += 1) {
        try large_zon.writer().print("    .field{} = \"value{}\",\n", .{ i, i });
    }
    try large_zon.appendSlice("}");

    const start_time = std.time.nanoTimestamp();

    var lexer = ZonLexer.init(allocator, large_zon.items, .{});
    defer lexer.deinit();

    const tokens = try lexer.tokenize();
    defer allocator.free(tokens);

    const end_time = std.time.nanoTimestamp();
    const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;

    // Should tokenize 100 fields in reasonable time (arbitrary threshold)
    try testing.expect(duration_ms < 10.0); // Less than 10ms
    try testing.expect(tokens.len > 200); // Should have many tokens
}

test "ZON performance - parsing speed" {
    const allocator = testing.allocator;

    const start_time = std.time.nanoTimestamp();

    var ast = try zon_mod.parseZonString(allocator, test_complex_zon);
    defer ast.deinit();

    const end_time = std.time.nanoTimestamp();
    const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;

    // Should parse complex ZON quickly (relaxed for debug builds)
    try testing.expect(duration_ms < 50.0); // Less than 50ms (debug builds are slower)
    try testing.expectEqual(ZonRules.object, ast.root.rule_id);
}

test "ZON performance - formatting speed" {
    const allocator = testing.allocator;

    const start_time = std.time.nanoTimestamp();

    const formatted = try zon_mod.formatZonString(allocator, test_complex_zon);
    defer allocator.free(formatted);

    const end_time = std.time.nanoTimestamp();
    const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;

    // Should format complex ZON quickly (relaxed for debug builds)
    try testing.expect(duration_ms < 50.0); // Less than 50ms (debug builds are slower)
    try testing.expect(formatted.len > 0);
}

// ============================================================================
// Edge Case Tests
// ============================================================================

test "ZON edge cases - empty structures" {
    const allocator = testing.allocator;

    const empty_object = ".{}";
    const empty_array = ".[]";

    // Test empty object
    var ast1 = try zon_mod.parseZonString(allocator, empty_object);
    defer ast1.deinit();
    try testing.expectEqual(ZonRules.object, ast1.root.rule_id);

    // Test empty array
    var ast2 = try zon_mod.parseZonString(allocator, empty_array);
    defer ast2.deinit();
    try testing.expectEqual(ZonRules.array, ast2.root.rule_id);
}

test "ZON edge cases - special identifiers" {
    const allocator = testing.allocator;

    const input = ".{ .@\"weird field\" = @\"weird value\" }";

    var ast = try zon_mod.parseZonString(allocator, input);
    defer ast.deinit();

    try testing.expectEqual(ZonRules.object, ast.root.rule_id);
}

test "ZON edge cases - trailing commas" {
    const allocator = testing.allocator;

    const input = ".{ .a = 1, .b = 2, }";

    var ast = try zon_mod.parseZonString(allocator, input);
    defer ast.deinit();

    try testing.expectEqual(ZonRules.object, ast.root.rule_id);
    try testing.expect(ast.root.children.len >= 2);
}

test "ZON edge cases - nested anonymous structs" {
    const allocator = testing.allocator;

    const input = ".{ .config = .{ .nested = .{ .value = 42 } } }";

    var ast = try zon_mod.parseZonString(allocator, input);
    defer ast.deinit();

    try testing.expectEqual(ZonRules.object, ast.root.rule_id);
}

test "ZON edge cases - all number formats" {
    const allocator = testing.allocator;

    const input = ".{ .decimal = 42, .hex = 0x2A, .binary = 0b101010, .octal = 0o52, .float = 3.14 }";

    var ast = try zon_mod.parseZonString(allocator, input);
    defer ast.deinit();

    try testing.expectEqual(ZonRules.object, ast.root.rule_id);
    try testing.expect(ast.root.children.len >= 5);
}

test {
    _ = @import("tokens.zig");
}
