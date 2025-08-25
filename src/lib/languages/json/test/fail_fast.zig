/// Test fail-fast vs collect-all-errors behavior
const std = @import("std");
const testing = std.testing;
const json = @import("../mod.zig");
const Parser = json.Parser;
const interface = @import("../../interface.zig");

test "Collect all errors by default" {
    const allocator = testing.allocator;

    // This input has multiple errors: missing comma AND wrong closing delimiter
    const input = "{\"a\":1 \"b\":2]";

    // Default behavior: collect all errors (validate returns error but collects all issues)
    const diagnostics = json.validate(allocator, input) catch |err| blk: {
        if (err == error.ParseError) {
            // This is expected - get the collected errors from the parser
            var parser = try Parser.init(allocator, input, .{});
            defer parser.deinit();
            _ = parser.parse() catch {};

            const errors = parser.getErrors();
            const diags = try allocator.alloc(json.Diagnostic, errors.len);
            for (errors, 0..) |e, i| {
                diags[i] = .{
                    .message = try allocator.dupe(u8, e.message),
                    .range = e.span,
                    .severity = switch (e.severity) {
                        .err => interface.Severity.err,
                        .warning => interface.Severity.warning,
                    },
                    .rule = .syntax_error, // Default rule for parse errors
                };
            }
            break :blk diags;
        }
        return err;
    };
    defer {
        for (diagnostics) |diag| allocator.free(diag.message);
        allocator.free(diagnostics);
    }

    // Should detect multiple errors
    try testing.expect(diagnostics.len >= 2);

    // Verify we get both the missing comma and wrong delimiter errors
    var found_comma_error = false;
    var found_delimiter_error = false;

    for (diagnostics) |diag| {
        if (std.mem.indexOf(u8, diag.message, "Expected ',' or '}'") != null or
            std.mem.indexOf(u8, diag.message, "Expected object_end") != null)
        {
            found_comma_error = true;
        }
        if (std.mem.indexOf(u8, diag.message, "Unexpected token") != null) {
            found_delimiter_error = true;
        }
    }

    try testing.expect(found_comma_error);
    try testing.expect(found_delimiter_error);
}

test "Fail-fast mode stops on first error" {
    const allocator = testing.allocator;

    // Same input with multiple errors
    const input = "{\"a\":1 \"b\":2]";

    // Test with collect_all_errors = false (fail-fast mode)
    var parser = try Parser.init(allocator, input, .{ .collect_all_errors = false });
    defer parser.deinit();

    const result = parser.parse();
    try testing.expectError(error.ParseError, result);

    // Should have stopped after first error
    const errors = parser.getErrors();
    try testing.expectEqual(@as(usize, 1), errors.len);
}

test "Error recovery continues parsing meaningfully" {
    const allocator = testing.allocator;

    const input =
        \\{
        \\  "valid": true,
        \\  "broken" 123,
        \\  "recovered": "yes", 
        \\  "another_broken": ,
        \\  "final": "done"
        \\}
    ;

    // Default: collect all errors
    const diagnostics = try json.validate(allocator, input);
    defer {
        for (diagnostics) |diag| allocator.free(diag.message);
        allocator.free(diagnostics);
    }

    // Should identify multiple broken fields
    try testing.expect(diagnostics.len >= 2);

    // Should have specific error types
    var found_colon_error = false;
    var found_value_error = false;

    for (diagnostics) |diag| {
        if (std.mem.indexOf(u8, diag.message, "Expected ':'") != null or
            std.mem.indexOf(u8, diag.message, "colon") != null)
        {
            found_colon_error = true;
        }
        if (std.mem.indexOf(u8, diag.message, "Expected value") != null or
            std.mem.indexOf(u8, diag.message, "value") != null)
        {
            found_value_error = true;
        }
    }

    try testing.expect(found_colon_error);
    try testing.expect(found_value_error);
}

test "Permissive trailing commas generate warnings, not errors" {
    const allocator = testing.allocator;

    // Trailing comma should be allowed by default
    const input = "{\"a\":1,\"b\":2,}";

    var parser = try Parser.init(allocator, input, .{});
    defer parser.deinit();

    var result = try parser.parse();
    defer result.deinit();

    // Should parse successfully (no errors thrown)
    const errors = parser.getErrors();

    // With allow_trailing_commas = true, should have no errors
    try testing.expectEqual(@as(usize, 0), errors.len);
}

test "Strict trailing comma mode generates errors" {
    const allocator = testing.allocator;

    const input = "{\"a\":1,\"b\":2,}";

    var parser = try Parser.init(allocator, input, .{ .allow_trailing_commas = false });
    defer parser.deinit();

    const result = parser.parse();
    if (result) |ast| {
        var ast_mut = ast;
        ast_mut.deinit();
    } else |_| {
        // Parse failed, which is expected for trailing comma in strict mode
    }

    const errors = parser.getErrors();

    // Should have trailing comma error
    try testing.expect(errors.len > 0);
    try testing.expect(std.mem.indexOf(u8, errors[0].message, "Trailing comma") != null);
}
