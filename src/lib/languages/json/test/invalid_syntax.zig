/// JSON Syntax Error Tests
/// Tests syntax violations like missing commas, colons, values, and improper keywords
const std = @import("std");
const testing = std.testing;
const json = @import("../mod.zig");
const test_utils = @import("test_utils.zig");

const InvalidCase = test_utils.InvalidCase;
const ExpectedError = test_utils.ExpectedError;

test "Invalid JSON Syntax - Missing punctuation and malformed constructs" {
    const allocator = testing.allocator;

    const cases = [_]InvalidCase{
        .{
            .name = "missing_comma_in_object",
            .input = "{\"a\":1 \"b\":2}",
            .expected_errors = &.{
                .{ .contains = "Expected ',' or '}'" },
            },
            .description = "Missing comma between object properties",
        },
        .{
            .name = "missing_comma_in_array",
            .input = "[1 2]",
            .expected_errors = &.{
                .{ .contains = "Expected ',' or ']'" },
            },
            .description = "Missing comma between array elements",
        },
        .{
            .name = "missing_colon",
            .input = "{\"a\" 1}",
            .expected_errors = &.{
                .{ .contains = "Expected colon" },
            },
            .description = "Missing colon after object key",
        },
        .{
            .name = "unquoted_key",
            .input = "{a:1}",
            .expected_errors = &.{
                .{ .contains = "Invalid character" },
            },
            .description = "Object key must be quoted (RFC 8259)",
        },
        .{
            .name = "missing_value",
            .input = "{\"a\":}",
            .expected_errors = &.{
                .{ .contains = "Unexpected token: object_end" },
            },
            .description = "Missing value after colon",
        },
        .{
            .name = "double_comma",
            .input = "[1,,2]",
            .expected_errors = &.{
                .{ .contains = "Unexpected token: comma" },
            },
            .description = "Double comma creates empty element",
        },
        .{
            .name = "leading_comma",
            .input = "[,1]",
            .expected_errors = &.{
                .{ .contains = "Unexpected token: comma" },
            },
            .description = "Leading comma in array",
        },
        .{
            .name = "multiple_roots",
            .input = "{\"a\":1}{\"b\":2}",
            .expected_errors = &.{
                .{ .contains = "Unexpected token after JSON value" },
            },
            .description = "Multiple root objects",
        },
        .{
            .name = "case_sensitive_true",
            .input = "True",
            .expected_errors = &.{
                .{ .contains = "Invalid character" },
            },
            .description = "Boolean values are case sensitive (RFC 8259)",
        },
        .{
            .name = "case_sensitive_false",
            .input = "FALSE",
            .expected_errors = &.{
                .{ .contains = "Invalid character" },
            },
            .description = "Boolean values are case sensitive (RFC 8259)",
        },
        .{
            .name = "case_sensitive_null",
            .input = "Null",
            .expected_errors = &.{
                .{ .contains = "Invalid character" },
            },
            .description = "Null value is case sensitive (RFC 8259)",
        },
        .{
            .name = "undefined_value",
            .input = "undefined",
            .expected_errors = &.{
                .{ .contains = "Invalid character" },
            },
            .description = "undefined is not a JSON value (RFC 8259)",
        },
        .{
            .name = "empty_document",
            .input = "",
            .expected_errors = &.{
                .{ .contains = "Unexpected token: eof" },
            },
            .description = "Document cannot be empty",
        },
        .{
            .name = "whitespace_only",
            .input = "   \n\t  ",
            .expected_errors = &.{
                .{ .contains = "Unexpected token: eof" },
            },
            .description = "Whitespace-only document invalid",
        },
        .{
            .name = "lone_comma",
            .input = ",",
            .expected_errors = &.{
                .{ .contains = "Unexpected token: comma" },
            },
            .description = "Document cannot start with comma",
        },
        .{
            .name = "lone_colon",
            .input = ":",
            .expected_errors = &.{
                .{ .contains = "Unexpected token: colon" },
            },
            .description = "Document cannot start with colon",
        },
    };

    try test_utils.runInvalidCases(allocator, &cases, "Invalid JSON Syntax");
}

test "Invalid JSON Syntax - Complex error combinations" {
    const allocator = testing.allocator;

    const cases = [_]InvalidCase{
        .{
            .name = "multiple_syntax_errors",
            .input = "{\"a\":1 \"b\":2 \"c\":3}",
            .expected_errors = &.{
                .{ .contains = "Expected ',' or '}'" },
                .{ .contains = "Expected ',' or '}'" },
            },
            .min_error_count = 2,
            .description = "Multiple missing commas",
        },
        .{
            .name = "mixed_structural_and_syntax",
            .input = "{\"a\":[1,2 \"b\":}",
            .expected_errors = &.{
                .{ .contains = "Expected ',' or ']'" },
                .{ .contains = "Expected array_end" },
            },
            .min_error_count = 2,
            .description = "Missing comma, missing value, unclosed array",
        },
        .{
            .name = "cascading_errors",
            .input = "{\"broken\" 123 \"another\": \"unclosed}",
            .expected_errors = &.{
                .{ .contains = "Expected colon, got number_value" },
                .{ .contains = "Expected object_end, got string_value" },
            },
            .min_error_count = 2,
            .description = "Missing colon and structural errors",
        },
    };

    try test_utils.runInvalidCases(allocator, &cases, "Invalid JSON Syntax");
}
