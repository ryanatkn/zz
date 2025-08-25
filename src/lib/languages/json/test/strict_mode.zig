/// JSON Strict Mode Tests
/// Tests features that are invalid in strict JSON but allowed with permissive settings
const std = @import("std");
const testing = std.testing;
const json = @import("../mod.zig");
const Parser = json.Parser;

const InvalidCase = struct {
    name: []const u8,
    input: []const u8,
    expected_errors: []const ExpectedError,
    min_error_count: usize = 1,
    description: []const u8,
};

const ExpectedError = struct {
    contains: []const u8,
    at_position: ?usize = null,
};

fn expectErrorContains(diagnostics: []const json.Diagnostic, text: []const u8) !void {
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

/// Validate JSON with custom parser options
fn validateWithOptions(allocator: std.mem.Allocator, content: []const u8, options: Parser.ParserOptions) ![]json.Diagnostic {
    var diagnostics = std.ArrayList(json.Diagnostic).init(allocator);

    // Parse with custom options and collect errors
    var parser = try Parser.init(allocator, content, options);
    defer parser.deinit();

    _ = parser.parse() catch {
        // Expected for invalid JSON - we want the error details
    };

    // Convert parser errors to diagnostics
    for (parser.getErrors()) |parse_error| {
        try diagnostics.append(.{
            .rule = .syntax_error,
            .message = try allocator.dupe(u8, parse_error.message),
            .severity = switch (parse_error.severity) {
                .err => .err,
                .warning => .warning,
            },
            .range = parse_error.span,
        });
    }

    return diagnostics.toOwnedSlice();
}

test "JSON Strict Mode - Trailing commas and comments" {
    const allocator = testing.allocator;

    // Test cases that are invalid in strict mode but valid with permissive settings
    const strict_cases = [_]InvalidCase{
        .{
            .name = "trailing_comma_object",
            .input = "{\"a\":1,}",
            .expected_errors = &.{
                .{ .contains = "Trailing comma" },
            },
            .description = "Trailing comma in object (strict mode)",
        },
        .{
            .name = "trailing_comma_array",
            .input = "[1,2,]",
            .expected_errors = &.{
                .{ .contains = "Trailing comma" },
            },
            .description = "Trailing comma in array (strict mode)",
        },
        .{
            .name = "single_line_comment",
            .input = "// comment\n{\"a\":1}",
            .expected_errors = &.{
                .{ .contains = "Comments not allowed" },
            },
            .description = "Single-line comment in strict mode",
        },
        .{
            .name = "multiline_comment",
            .input = "/* comment */{\"a\":1}",
            .expected_errors = &.{
                .{ .contains = "Comments not allowed" },
            },
            .description = "Multi-line comment in strict mode",
        },
    };

    for (strict_cases) |case| {
        // Use strict mode: no trailing commas or comments allowed
        const diagnostics = validateWithOptions(allocator, case.input, .{
            .allow_trailing_commas = false,
            .allow_comments = false,
            .collect_all_errors = true,
        }) catch |err| {
            std.debug.print("Failed to validate '{s}': {}\n", .{ case.input, err });
            return err;
        };
        defer {
            for (diagnostics) |diag| allocator.free(diag.message);
            allocator.free(diagnostics);
        }

        try testing.expect(diagnostics.len >= case.min_error_count);

        for (case.expected_errors) |expected| {
            try expectErrorContains(diagnostics, expected.contains);
        }
    }
}

test "JSON Permissive Mode - Trailing commas and comments allowed" {
    const allocator = testing.allocator;

    const permissive_cases = [_][]const u8{
        "{\"a\":1,}", // Trailing comma in object
        "[1,2,]", // Trailing comma in array
        "// comment\n{\"a\":1}", // Single-line comment
        "/* comment */{\"a\":1}", // Multi-line comment
    };

    for (permissive_cases) |input| {
        // Use permissive mode (defaults)
        var parser = try Parser.init(allocator, input, .{});
        defer parser.deinit();

        var result = parser.parse() catch |err| {
            std.debug.print("Permissive mode should allow '{s}', but got error: {}\n", .{ input, err });
            return err;
        };
        defer result.deinit();

        // Should parse successfully with no errors
        const errors = parser.getErrors();
        try testing.expectEqual(@as(usize, 0), errors.len);
    }
}
