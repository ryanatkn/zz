/// JSON Structural Error Tests
/// Tests structural violations like unclosed objects/arrays, mismatched delimiters
const std = @import("std");
const testing = std.testing;
const json = @import("../mod.zig");
const test_utils = @import("test_utils.zig");

const InvalidCase = test_utils.InvalidCase;
const ExpectedError = test_utils.ExpectedError;

test "Invalid JSON Structures - Unclosed and mismatched delimiters" {
    const allocator = testing.allocator;

    const cases = [_]InvalidCase{
        .{
            .name = "unclosed_object",
            .input = "{\"a\":1",
            .expected_errors = &.{
                .{ .contains = "Expected ',' or '}'" },
            },
            .description = "Object missing closing brace",
        },
        .{
            .name = "unclosed_array",
            .input = "[1,2",
            .expected_errors = &.{
                .{ .contains = "Expected ',' or ']'" },
            },
            .description = "Array missing closing bracket",
        },
        .{
            .name = "multiple_unclosed_nested",
            .input = "{\"a\":[1,{\"b\":2}",
            .expected_errors = &.{
                .{ .contains = "Expected object_end, got eof" },
                .{ .contains = "Expected array_end, got eof" },
            },
            .min_error_count = 2,
            .description = "Multiple nested structures unclosed",
        },
        .{
            .name = "extra_closing_brace",
            .input = "{\"a\":1}}",
            .expected_errors = &.{
                .{ .contains = "Unexpected token after JSON value" },
            },
            .description = "Extra closing brace",
        },
        .{
            .name = "extra_closing_bracket",
            .input = "[1,2]]",
            .expected_errors = &.{
                .{ .contains = "Unexpected token after JSON value" },
            },
            .description = "Extra closing bracket",
        },
        .{
            .name = "mismatched_delimiters",
            .input = "{\"a\":1]",
            .expected_errors = &.{
                .{ .contains = "Expected object_end, got array_end" },
            },
            .description = "Object closed with bracket",
        },
        .{
            .name = "mismatched_delimiters_array",
            .input = "[1,2}",
            .expected_errors = &.{
                .{ .contains = "Expected array_end, got object_end" },
            },
            .description = "Array closed with brace",
        },
        .{
            .name = "lone_closing_brace",
            .input = "}",
            .expected_errors = &.{
                .{ .contains = "Unexpected token: object_end" },
            },
            .description = "Document starts with closing brace",
        },
    };

    try test_utils.runInvalidCases(allocator, &cases, "Invalid JSON Structures");
}
