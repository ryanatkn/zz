/// Shared test utilities for JSON test suite
/// Provides common structures and helpers to eliminate code duplication
const std = @import("std");
const testing = std.testing;
const json = @import("../mod.zig");

/// Test case for invalid JSON validation
pub const InvalidCase = struct {
    name: []const u8,
    input: []const u8,
    expected_errors: []const ExpectedError,
    min_error_count: usize = 1,
    description: []const u8,
};

/// Test case for valid JSON validation
pub const ValidCase = struct {
    name: []const u8,
    input: []const u8,
    description: []const u8,
    // Optional expected values for verification
    expected_type: ?enum { object, array, string, number, boolean, null } = null,
    expected_string_value: ?[]const u8 = null,
};

/// Expected error for validation
pub const ExpectedError = struct {
    contains: []const u8,
    at_position: ?usize = null,
};

/// Check if diagnostics contain expected error message
pub fn expectErrorContains(diagnostics: []const json.Diagnostic, text: []const u8) !void {
    for (diagnostics) |diag| {
        if (std.mem.indexOf(u8, diag.message, text) != null) {
            return; // Found it
        }
    }
    std.debug.print("Expected error containing '{s}' not found in diagnostics:\n", .{text});
    for (diagnostics) |diag| {
        std.debug.print("  - {s}\n", .{diag.message});
    }
    try testing.expect(false);
}

/// Run a suite of invalid JSON test cases
pub fn runInvalidCases(allocator: std.mem.Allocator, cases: []const InvalidCase, test_name: []const u8) !void {
    for (cases) |case| {
        const diagnostics = json.validate(allocator, case.input) catch |err| {
            std.debug.print("{s}: Failed to validate '{s}': {}\n", .{ test_name, case.input, err });
            return err;
        };
        defer {
            for (diagnostics) |diag| allocator.free(diag.message);
            allocator.free(diagnostics);
        }

        if (diagnostics.len < case.min_error_count) {
            std.debug.print("{s}: Expected at least {} errors for '{s}' ({s}), got {}\n", .{ test_name, case.min_error_count, case.input, case.description, diagnostics.len });
        }
        try testing.expect(diagnostics.len >= case.min_error_count);

        for (case.expected_errors) |expected| {
            try expectErrorContains(diagnostics, expected.contains);
        }
    }
}

/// Run a suite of valid JSON test cases
pub fn runValidCases(allocator: std.mem.Allocator, cases: []const ValidCase, test_name: []const u8) !void {
    for (cases) |case| {
        var ast = json.parse(allocator, case.input) catch |err| {
            std.debug.print("{s}: Failed to parse valid JSON '{s}' ({s}): {}\n", .{ test_name, case.input, case.description, err });
            return err;
        };
        defer ast.deinit();

        // Optional type verification
        if (case.expected_type) |expected_type| {
            const actual_type = switch (ast.root.*) {
                .object => @as(@TypeOf(expected_type), .object),
                .array => .array,
                .string => .string,
                .number => .number,
                .boolean => .boolean,
                .null => .null,
                .property, .root, .err => unreachable, // These shouldn't be root nodes in valid JSON
            };
            try testing.expectEqual(expected_type, actual_type);
        }

        // Optional string value verification
        if (case.expected_string_value) |expected_value| {
            try testing.expect(ast.root.* == .string);
            try testing.expectEqualStrings(expected_value, ast.root.string.value);
        }
    }
}

/// Common test data for reuse across test files
pub const CommonTestCases = struct {
    /// Valid JSON numbers per RFC 8259
    pub const valid_numbers = [_][]const u8{
        "0",           "-0",     "1",       "-1",       "123",    "-123",
        "1.0",         "-1.0",   "123.456", "-123.456", "1e10",   "1E10",
        "1e+10",       "1E+10",  "1e-10",   "1E-10",    "-1e10",  "-1E10",
        "-1e+10",      "-1E+10", "-1e-10",  "-1E-10",   "1.5e10", "-1.5E+10",
        "123.456e-10",
        // Edge cases
        "1e0",    "1E0",     "0e0",      "0E0",
    };

    /// Invalid JSON numbers per RFC 8259
    pub const invalid_numbers = [_][]const u8{
        // Leading zeros
        "01",    "00",       "001",   "0123",     "000123",
        "-01",   "-00",      "-001",  "-0123",    "01.5",
        "01e10", "01E10",    "-01.5", "-01e10",
        // Trailing/leading decimals
          "1.",
        ".5",    "-.5",
        // Incomplete exponents
             "1e",    "1E",       "1e+",
        "1E-",   "1e+",      "1E+",
        // Multiple decimals
          "1.2.3",    "1..2",
        // Leading plus
        "+1",    "+123",     "+1.5",
        // Invalid literals
         "Infinity", "-Infinity",
        "NaN",   "infinity", "nan",
        // Hex notation
          "0x10",     "0X10",
        "0xff",
    };

    /// Valid JSON strings per RFC 8259
    pub const valid_strings = [_][]const u8{
        "\"\"", // Empty string
        "\"hello\"",
        "\"world\"",
        "\"hello, world!\"",
        // Basic escape sequences
        "\"\\\"\"",
        "\"\\\\\"",
        "\"\\/\"",
        "\"\\b\"",
        "\"\\f\"",
        "\"\\n\"",
        "\"\\r\"",
        "\"\\t\"",
        // Unicode escapes
        "\"\\u0041\"",
        "\"\\u0048\\u0065\\u006C\\u006C\\u006F\"",
        "\"\\u00A9\"",
        "\"\\u03A9\"",
        "\"\\u20AC\"",
        // Mixed content
        "\"Hello\\nWorld\"",
        "\"Path: C:\\\\Users\\\\test\"",
    };

    /// Invalid JSON strings per RFC 8259
    pub const invalid_strings = [_][]const u8{
        // Unclosed strings
        "\"hello",     "\"hello\\",   "\"hello\\n",
        // Invalid escape sequences
        "\"\\z\"",     "\"\\x41\"",   "\"\\123\"",
        // Incomplete Unicode escapes
        "\"\\u\"",     "\"\\u1\"",    "\"\\u12\"",
        "\"\\u123\"",
        // Invalid Unicode characters
         "\"\\uGGGG\"", "\"\\uXXXX\"",
        "\"\\u123G\"",
        // Single quotes (not valid in JSON)
        "'hello'",     "'world'",
    };

    /// Structural test cases
    pub const unclosed_structures = [_][]const u8{
        "{",      "}",   "[",        "]",
        "{\"a\"", "[1,", "{\"a\":1", "[1,2",
        "{\"a\":[1,{\"b\":2}", // Multiple unclosed nested
    };

    /// Mismatched delimiters
    pub const mismatched_delimiters = [_][]const u8{
        "{\"a\":1]", "[1,2}", "({\"a\":1})", "[{\"a\":1})",
    };
};

/// Test patterns for comprehensive coverage
pub const TestPatterns = struct {
    /// Generate test cases for whitespace handling
    pub fn generateWhitespaceTests(allocator: std.mem.Allocator, base_case: []const u8) ![][]const u8 {
        const whitespace_chars = [_][]const u8{ " ", "\t", "\n", "\r" };
        var cases = std.ArrayList([]const u8).init(allocator);

        // Add whitespace before, after, and between tokens
        for (whitespace_chars) |ws| {
            try cases.append(try std.fmt.allocPrint(allocator, "{s}{s}", .{ ws, base_case }));
            try cases.append(try std.fmt.allocPrint(allocator, "{s}{s}", .{ base_case, ws }));
            try cases.append(try std.fmt.allocPrint(allocator, "{s}{s}{s}", .{ ws, base_case, ws }));
        }

        return cases.toOwnedSlice();
    }

    /// Generate nested structure test cases
    pub fn generateNestedTests(allocator: std.mem.Allocator, depth: usize) ![][]const u8 {
        var cases = std.ArrayList([]const u8).init(allocator);

        // Nested objects
        var obj_str = std.ArrayList(u8).init(allocator);
        defer obj_str.deinit();

        for (0..depth) |_| {
            try obj_str.appendSlice("{\"a\":");
        }
        try obj_str.appendSlice("1");
        for (0..depth) |_| {
            try obj_str.append('}');
        }
        try cases.append(try obj_str.toOwnedSlice());

        // Nested arrays
        var arr_str = std.ArrayList(u8).init(allocator);
        defer arr_str.deinit();

        for (0..depth) |_| {
            try arr_str.append('[');
        }
        try arr_str.append('1');
        for (0..depth) |_| {
            try arr_str.append(']');
        }
        try cases.append(try arr_str.toOwnedSlice());

        return cases.toOwnedSlice();
    }
};
