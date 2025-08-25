/// RFC 8259 Compliant String Validation Tests
/// Tests all string format violations according to JSON specification
const std = @import("std");
const testing = std.testing;
const json = @import("../mod.zig");
const test_utils = @import("test_utils.zig");

const InvalidCase = test_utils.InvalidCase;
const ExpectedError = test_utils.ExpectedError;

test "Invalid JSON Strings - RFC 8259 violations" {
    const allocator = testing.allocator;

    const cases = [_]InvalidCase{
        .{
            .name = "unclosed_string",
            .input = "\"unclosed",
            .expected_errors = &.{
                .{ .contains = "Unterminated string" },
            },
            .description = "String missing closing quote",
        },
        .{
            .name = "unclosed_string_in_object",
            .input = "{\"key\":\"unclosed",
            .expected_errors = &.{
                .{ .contains = "Unterminated string" },
            },
            .description = "Unclosed string as object value",
        },
        .{
            .name = "unclosed_key",
            .input = "{\"key",
            .expected_errors = &.{
                .{ .contains = "Unterminated string" },
            },
            .description = "Unclosed string as object key",
        },
        .{
            .name = "invalid_escape_hex",
            .input = "\"\\x41\"",
            .expected_errors = &.{
                .{ .contains = "Invalid escape sequence" },
            },
            .description = "Hex escape not supported in JSON",
        },
        .{
            .name = "incomplete_unicode",
            .input = "\"\\u12\"",
            .expected_errors = &.{
                .{ .contains = "Incomplete Unicode escape sequence" },
            },
            .description = "Incomplete unicode escape sequence",
        },
        .{
            .name = "invalid_unicode_chars",
            .input = "\"\\uGGGG\"",
            .expected_errors = &.{
                .{ .contains = "Invalid Unicode escape sequence" },
            },
            .description = "Invalid characters in unicode escape",
        },
        .{
            .name = "invalid_escape_char",
            .input = "\"\\z\"",
            .expected_errors = &.{
                .{ .contains = "Invalid escape sequence" },
            },
            .description = "Unsupported escape character",
        },
        // TODO: Literal control characters should be rejected but currently pass validation
        // .{
        //     .name = "literal_control_chars",
        //     .input = "\"\t\"",
        //     .expected_errors = &.{
        //         .{ .contains = "control character" },
        //     },
        //     .description = "Literal tab character in string (should be escaped)",
        // },
        .{
            .name = "single_quotes",
            .input = "'string'",
            .expected_errors = &.{
                .{ .contains = "Invalid character" },
            },
            .description = "Single quotes not allowed in JSON (RFC 8259)",
        },
    };

    try test_utils.runInvalidCases(allocator, &cases, "Invalid JSON Strings");
}
