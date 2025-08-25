/// RFC 8259 Compliant Number Validation Tests
/// Tests all number format violations according to JSON specification
const std = @import("std");
const testing = std.testing;
const json = @import("../mod.zig");
const test_utils = @import("test_utils.zig");

const InvalidCase = test_utils.InvalidCase;
const ExpectedError = test_utils.ExpectedError;

test "Invalid JSON Numbers - RFC 8259 violations" {
    const allocator = testing.allocator;

    const cases = [_]InvalidCase{
        .{
            .name = "trailing_decimal",
            .input = "1.",
            .expected_errors = &.{
                .{ .contains = "decimal point must be followed by digits" },
            },
            .description = "Decimal point with no digits after (RFC 8259 violation)",
        },
        .{
            .name = "leading_decimal",
            .input = ".5",
            .expected_errors = &.{
                .{ .contains = "Invalid character" },
            },
            .description = "Decimal point with no digits before",
        },
        .{
            .name = "incomplete_exponent",
            .input = "1e",
            .expected_errors = &.{
                .{ .contains = "exponent must contain digits" },
            },
            .description = "Exponent with no digits",
        },
        .{
            .name = "incomplete_signed_exponent",
            .input = "1e+",
            .expected_errors = &.{
                .{ .contains = "exponent must contain digits" },
            },
            .description = "Signed exponent with no digits",
        },
        .{
            .name = "multiple_decimals",
            .input = "1.2.3",
            .expected_errors = &.{
                .{ .contains = "Number format is invalid" },
            },
            .description = "Multiple decimal points",
        },
        .{
            .name = "leading_zero",
            .input = "01",
            .expected_errors = &.{
                .{ .contains = "leading zeros not allowed" },
            },
            .description = "Leading zero not allowed (RFC 8259)",
        },
        .{
            .name = "leading_plus",
            .input = "+1",
            .expected_errors = &.{
                .{ .contains = "Invalid character" },
            },
            .description = "Leading plus sign not allowed",
        },
        .{
            .name = "infinity_literal",
            .input = "Infinity",
            .expected_errors = &.{
                .{ .contains = "Invalid character" },
            },
            .description = "Infinity not valid in JSON (RFC 8259)",
        },
        .{
            .name = "nan_literal",
            .input = "NaN",
            .expected_errors = &.{
                .{ .contains = "Invalid character" },
            },
            .description = "NaN not valid in JSON (RFC 8259)",
        },
        .{
            .name = "hex_notation",
            .input = "0x10",
            .expected_errors = &.{
                .{ .contains = "Unexpected token after JSON value" },
            },
            .description = "Hex notation not allowed in JSON",
        },
        .{
            .name = "exponent_leading_zero",
            .input = "1e01",
            .expected_errors = &.{
                .{ .contains = "leading zeros not allowed" },
            },
            .description = "Exponent with leading zero (RFC 8259 violation)",
        },
        // TODO: Add when large number validation is implemented
        // .{
        //     .name = "very_large_number",
        //     .input = "1" ++ "0" ** 400, // 400 zeros
        //     .expected_errors = &.{
        //         .{ .contains = "Number too large" },
        //     },
        //     .description = "Extremely large number should be rejected",
        // },
    };

    try test_utils.runInvalidCases(allocator, &cases, "Invalid JSON Numbers");
}
