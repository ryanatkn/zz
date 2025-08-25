/// Comprehensive Valid JSON Test Suite
/// Tests all valid JSON constructs according to RFC 8259 using declarative test data
const std = @import("std");
const testing = std.testing;
const json = @import("../mod.zig");
const test_utils = @import("test_utils.zig");

const ValidCase = test_utils.ValidCase;

test "Valid JSON - Basic Value Types" {
    const allocator = testing.allocator;

    const cases = [_]ValidCase{
        // Null
        .{ .name = "null", .input = "null", .description = "Null value", .expected_type = .null },

        // Booleans
        .{ .name = "true", .input = "true", .description = "Boolean true", .expected_type = .boolean },
        .{ .name = "false", .input = "false", .description = "Boolean false", .expected_type = .boolean },

        // Numbers
        .{ .name = "zero", .input = "0", .description = "Zero", .expected_type = .number },
        .{ .name = "negative_zero", .input = "-0", .description = "Negative zero", .expected_type = .number },
        .{ .name = "integer", .input = "123", .description = "Positive integer", .expected_type = .number },
        .{ .name = "negative_integer", .input = "-123", .description = "Negative integer", .expected_type = .number },
        .{ .name = "float", .input = "123.456", .description = "Floating point", .expected_type = .number },
        .{ .name = "negative_float", .input = "-123.456", .description = "Negative float", .expected_type = .number },
        .{ .name = "exponent", .input = "1e10", .description = "Scientific notation", .expected_type = .number },
        .{ .name = "exponent_positive", .input = "1E+10", .description = "Positive exponent", .expected_type = .number },
        .{ .name = "exponent_negative", .input = "1e-10", .description = "Negative exponent", .expected_type = .number },
        .{ .name = "float_exponent", .input = "123.456e-10", .description = "Float with exponent", .expected_type = .number },

        // Strings
        .{ .name = "empty_string", .input = "\"\"", .description = "Empty string", .expected_type = .string, .expected_string_value = "" },
        .{ .name = "simple_string", .input = "\"hello\"", .description = "Simple string", .expected_type = .string, .expected_string_value = "hello" },
        .{ .name = "string_with_spaces", .input = "\"hello world\"", .description = "String with spaces", .expected_type = .string, .expected_string_value = "hello world" },
    };

    try test_utils.runValidCases(allocator, &cases, "Valid JSON Basic Types");
}

test "Valid JSON - String Escapes" {
    const allocator = testing.allocator;

    const cases = [_]ValidCase{
        // Basic escape sequences
        .{ .name = "escape_quote", .input = "\"\\\"\"", .description = "Escaped quote", .expected_type = .string, .expected_string_value = "\"" },
        .{ .name = "escape_backslash", .input = "\"\\\\\"", .description = "Escaped backslash", .expected_type = .string, .expected_string_value = "\\" },
        .{ .name = "escape_slash", .input = "\"\\/\"", .description = "Escaped forward slash", .expected_type = .string, .expected_string_value = "/" },
        .{ .name = "escape_backspace", .input = "\"\\b\"", .description = "Escaped backspace", .expected_type = .string, .expected_string_value = "\x08" },
        .{ .name = "escape_formfeed", .input = "\"\\f\"", .description = "Escaped form feed", .expected_type = .string, .expected_string_value = "\x0C" },
        .{ .name = "escape_newline", .input = "\"\\n\"", .description = "Escaped newline", .expected_type = .string, .expected_string_value = "\n" },
        .{ .name = "escape_carriage", .input = "\"\\r\"", .description = "Escaped carriage return", .expected_type = .string, .expected_string_value = "\r" },
        .{ .name = "escape_tab", .input = "\"\\t\"", .description = "Escaped tab", .expected_type = .string, .expected_string_value = "\t" },

        // Unicode escapes
        .{ .name = "unicode_a", .input = "\"\\u0041\"", .description = "Unicode A", .expected_type = .string, .expected_string_value = "A" },
        .{ .name = "unicode_copyright", .input = "\"\\u00A9\"", .description = "Unicode copyright", .expected_type = .string, .expected_string_value = "©" },
        .{ .name = "unicode_omega", .input = "\"\\u03A9\"", .description = "Unicode Greek Omega", .expected_type = .string, .expected_string_value = "Ω" },

        // Mixed content
        .{ .name = "mixed_escapes", .input = "\"Hello\\nWorld\"", .description = "String with newline", .expected_type = .string, .expected_string_value = "Hello\nWorld" },
        .{ .name = "path_string", .input = "\"C:\\\\Users\\\\test\"", .description = "Windows path", .expected_type = .string, .expected_string_value = "C:\\Users\\test" },
    };

    try test_utils.runValidCases(allocator, &cases, "Valid JSON String Escapes");
}

test "Valid JSON - Objects" {
    const allocator = testing.allocator;

    const cases = [_]ValidCase{
        // Empty and simple objects
        .{ .name = "empty_object", .input = "{}", .description = "Empty object", .expected_type = .object },
        .{ .name = "single_property", .input = "{\"a\":1}", .description = "Single property", .expected_type = .object },
        .{ .name = "multiple_properties", .input = "{\"a\":1,\"b\":2}", .description = "Multiple properties", .expected_type = .object },

        // Different value types
        .{ .name = "mixed_values", .input = "{\"str\":\"hello\",\"num\":42,\"bool\":true,\"nil\":null}", .description = "Mixed value types", .expected_type = .object },

        // Nested objects
        .{ .name = "nested_object", .input = "{\"a\":{\"b\":1}}", .description = "Nested object", .expected_type = .object },
        .{ .name = "deep_nesting", .input = "{\"a\":{\"b\":{\"c\":{\"d\":1}}}}", .description = "Deeply nested object", .expected_type = .object },

        // Special keys
        .{ .name = "empty_key", .input = "{\"\":\"empty key\"}", .description = "Empty string key", .expected_type = .object },
        .{ .name = "numeric_key", .input = "{\"123\":\"numeric key\"}", .description = "Numeric string key", .expected_type = .object },
        .{ .name = "special_char_key", .input = "{\"key with spaces\":1,\"@symbol\":2}", .description = "Special character keys", .expected_type = .object },
    };

    try test_utils.runValidCases(allocator, &cases, "Valid JSON Objects");
}

test "Valid JSON - Arrays" {
    const allocator = testing.allocator;

    const cases = [_]ValidCase{
        // Empty and simple arrays
        .{ .name = "empty_array", .input = "[]", .description = "Empty array", .expected_type = .array },
        .{ .name = "single_element", .input = "[1]", .description = "Single element", .expected_type = .array },
        .{ .name = "multiple_elements", .input = "[1,2,3]", .description = "Multiple elements", .expected_type = .array },

        // Different element types
        .{ .name = "mixed_types", .input = "[\"hello\",42,true,null]", .description = "Mixed element types", .expected_type = .array },
        .{ .name = "string_array", .input = "[\"a\",\"b\",\"c\"]", .description = "String array", .expected_type = .array },
        .{ .name = "number_array", .input = "[1,2,3,4,5]", .description = "Number array", .expected_type = .array },

        // Nested arrays
        .{ .name = "nested_array", .input = "[[1,2],[3,4]]", .description = "Nested arrays", .expected_type = .array },
        .{ .name = "deep_nesting", .input = "[[[[1]]]]", .description = "Deeply nested arrays", .expected_type = .array },

        // Mixed nesting
        .{ .name = "array_of_objects", .input = "[{\"a\":1},{\"b\":2}]", .description = "Array of objects", .expected_type = .array },
        .{ .name = "object_with_arrays", .input = "{\"nums\":[1,2,3],\"strs\":[\"a\",\"b\"]}", .description = "Object containing arrays", .expected_type = .object },
    };

    try test_utils.runValidCases(allocator, &cases, "Valid JSON Arrays");
}

test "Valid JSON - Whitespace Handling" {
    const allocator = testing.allocator;

    const cases = [_]ValidCase{
        // Leading/trailing whitespace
        .{ .name = "leading_space", .input = " 123", .description = "Leading space", .expected_type = .number },
        .{ .name = "trailing_space", .input = "123 ", .description = "Trailing space", .expected_type = .number },
        .{ .name = "surrounding_spaces", .input = " 123 ", .description = "Surrounding spaces", .expected_type = .number },

        // Different whitespace characters
        .{ .name = "tabs", .input = "\t123\t", .description = "Tabs", .expected_type = .number },
        .{ .name = "newlines", .input = "\n123\n", .description = "Newlines", .expected_type = .number },
        .{ .name = "mixed_whitespace", .input = " \t\n\r 123 \r\n\t ", .description = "Mixed whitespace", .expected_type = .number },

        // Whitespace in structures
        .{ .name = "object_whitespace", .input = "{ \"a\" : 1 , \"b\" : 2 }", .description = "Object with whitespace", .expected_type = .object },
        .{ .name = "array_whitespace", .input = "[ 1 , 2 , 3 ]", .description = "Array with whitespace", .expected_type = .array },

        // Pretty-printed JSON
        .{ .name = "pretty_object", .input = "{\n  \"name\": \"value\",\n  \"number\": 123\n}", .description = "Pretty-printed object", .expected_type = .object },
        .{ .name = "pretty_array", .input = "[\n  1,\n  2,\n  3\n]", .description = "Pretty-printed array", .expected_type = .array },
    };

    try test_utils.runValidCases(allocator, &cases, "Valid JSON Whitespace");
}

test "Valid JSON - Edge Cases" {
    const allocator = testing.allocator;

    const cases = [_]ValidCase{
        // Minimal valid JSON
        .{ .name = "minimal_true", .input = "true", .description = "Minimal true", .expected_type = .boolean },
        .{ .name = "minimal_false", .input = "false", .description = "Minimal false", .expected_type = .boolean },
        .{ .name = "minimal_null", .input = "null", .description = "Minimal null", .expected_type = .null },
        .{ .name = "minimal_zero", .input = "0", .description = "Minimal zero", .expected_type = .number },
        .{ .name = "minimal_string", .input = "\"a\"", .description = "Minimal string", .expected_type = .string, .expected_string_value = "a" },

        // Large structures (reasonable size)
        .{ .name = "large_array", .input = "[" ++ ("1," ** 99) ++ "100]", .description = "Array with 100 elements", .expected_type = .array },

        // Special numbers
        .{ .name = "zero_exponent", .input = "1e0", .description = "Zero exponent", .expected_type = .number },
        .{ .name = "decimal_zero", .input = "0.0", .description = "Decimal zero", .expected_type = .number },
        .{ .name = "negative_decimal", .input = "-0.5", .description = "Negative decimal", .expected_type = .number },
    };

    try test_utils.runValidCases(allocator, &cases, "Valid JSON Edge Cases");
}
