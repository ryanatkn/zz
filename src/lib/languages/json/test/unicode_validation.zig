/// Unicode Validation Tests - RFC 9839 Compliance
///
/// Tests the Unicode validation modes for detecting problematic code points
/// according to RFC 9839 Unicode Character Repertoire Subsets
const std = @import("std");
const testing = std.testing;
const json = @import("../mod.zig");
const UnicodeMode = json.UnicodeMode;
const test_utils = @import("test_utils.zig");

const allocator = testing.allocator;

test "Unicode validation - strict mode control characters" {
    // Note: Using printf-style format for actual control characters, not escaped sequences
    const test_cases = [_]struct {
        name: []const u8,
        byte: u8,
        description: []const u8,
    }{
        .{ .name = "null_byte", .byte = 0x00, .description = "NULL byte (U+0000) should be rejected" },
        .{ .name = "backspace", .byte = 0x08, .description = "Backspace (U+0008) should be rejected" },
        .{ .name = "vertical_tab", .byte = 0x0B, .description = "Vertical tab (U+000B) should be rejected" },
        .{ .name = "form_feed", .byte = 0x0C, .description = "Form feed (U+000C) should be rejected" },
        .{ .name = "del_character", .byte = 0x7F, .description = "DEL character (U+007F) should be rejected" },
        .{ .name = "carriage_return", .byte = 0x0D, .description = "Carriage return (U+000D) should be rejected (Unix line endings only)" },
    };

    // Test with strict mode (default)
    for (test_cases) |case| {
        // Create JSON string with actual control character embedded
        var json_buffer = std.ArrayList(u8).init(allocator);
        defer json_buffer.deinit();

        try json_buffer.appendSlice("{\"test\": \"hello");
        try json_buffer.append(case.byte); // Insert the actual control character
        try json_buffer.appendSlice("world\"}");

        const json_input = try json_buffer.toOwnedSlice();
        defer allocator.free(json_input);

        var parser = try json.Parser.init(allocator, json_input, .{ .unicode_mode = .strict });
        defer parser.deinit();

        const result = parser.parse();

        // Should fail with control character error
        if (result) |ast| {
            var ast_mut = ast;
            ast_mut.deinit();
            std.debug.print("Test '{s}' failed: Expected ParseError for control character 0x{X:0>2}, but parsing succeeded\n", .{ case.name, case.byte });
            try testing.expect(false);
        } else |err| {
            // Verify it's the right kind of error
            try testing.expect(err == error.ParseError);

            const errors = parser.getErrors();
            var found_control_error = false;
            for (errors) |parse_err| {
                if (std.mem.indexOf(u8, parse_err.message, "control character") != null) {
                    found_control_error = true;
                    break;
                }
            }

            if (!found_control_error) {
                std.debug.print("Test '{s}' failed: Expected control character error, but got:\n", .{case.name});
                for (errors) |parse_err| {
                    std.debug.print("  - '{s}'\n", .{parse_err.message});
                }
                try testing.expect(false);
            }
        }
    }
}

test "Unicode validation - strict mode allows useful controls" {
    const valid_cases = [_][]const u8{
        "\"hello\\tworld\"", // Tab (U+0009) - allowed
        "\"hello\\nworld\"", // Newline (U+000A) - allowed
        "\"hello world\"", // Regular ASCII - allowed
        "\"héllo wörld\"", // Unicode letters - allowed
    };

    for (valid_cases) |case| {
        const json_input = try std.fmt.allocPrint(allocator, "{{\"test\": {s}}}", .{case});
        defer allocator.free(json_input);

        var parser = try json.Parser.init(allocator, json_input, .{ .unicode_mode = .strict });
        defer parser.deinit();

        const result = parser.parse();
        if (result) |ast| {
            var ast_mut = ast;
            ast_mut.deinit();
        } else |err| {
            std.debug.print("Strict mode should allow valid input '{s}', but got error: {}\n", .{ case, err });
            try testing.expect(false);
        }
    }
}

test "Unicode validation - permissive mode allows everything" {
    const test_cases = [_][]const u8{
        "\"hello\\u0000world\"", // NULL byte - should be allowed in permissive mode
        "\"hello\\u0008world\"", // Backspace - should be allowed
        "\"hello\\u007Fworld\"", // DEL - should be allowed
        "\"hello\\u000Dworld\"", // Carriage return - should be allowed in permissive mode
        "\"hello\\tworld\"", // Tab - should be allowed
        "\"regular text\"", // Regular text - should be allowed
    };

    for (test_cases) |case| {
        const json_input = try std.fmt.allocPrint(allocator, "{{\"test\": {s}}}", .{case});
        defer allocator.free(json_input);

        var parser = try json.Parser.init(allocator, json_input, .{ .unicode_mode = .permissive });
        defer parser.deinit();

        const result = parser.parse();
        if (result) |ast| {
            var ast_mut = ast;
            ast_mut.deinit();
        } else |err| {
            std.debug.print("Permissive mode should allow all input '{s}', but got error: {}\n", .{ case, err });
            try testing.expect(false);
        }
    }
}

test "Unicode validation - sanitize mode (basic test)" {
    // Note: Full sanitize mode implementation with U+FFFD replacement is TODO
    // For now, test that sanitize mode at least doesn't crash
    const json_input = "{\"test\": \"hello world\"}";

    var parser = try json.Parser.init(allocator, json_input, .{ .unicode_mode = .sanitize });
    defer parser.deinit();

    const result = parser.parse();
    if (result) |ast| {
        var ast_mut = ast;
        ast_mut.deinit();
    } else |err| {
        std.debug.print("Sanitize mode failed on valid input: {}\n", .{err});
        try testing.expect(false);
    }
}

test "Unicode validation - mode comparison" {
    // Test the same problematic input with different modes
    // Use actual control character, not escaped sequence
    var json_buffer = std.ArrayList(u8).init(allocator);
    defer json_buffer.deinit();

    try json_buffer.appendSlice("{\"test\": \"hello");
    try json_buffer.append(0x00); // Insert actual NULL byte
    try json_buffer.appendSlice("world\"}");

    const problematic_json = try json_buffer.toOwnedSlice();
    defer allocator.free(problematic_json);

    // Strict mode should reject
    {
        var parser = try json.Parser.init(allocator, problematic_json, .{ .unicode_mode = .strict });
        defer parser.deinit();

        const result = parser.parse();
        if (result) |ast| {
            var ast_mut = ast;
            ast_mut.deinit();
            try testing.expect(false); // Should have failed
        } else |err| {
            try testing.expect(err == error.ParseError);
        }
    }

    // Permissive mode should allow
    {
        var parser = try json.Parser.init(allocator, problematic_json, .{ .unicode_mode = .permissive });
        defer parser.deinit();

        const result = parser.parse();
        if (result) |ast| {
            var ast_mut = ast;
            ast_mut.deinit();
        } else |err| {
            std.debug.print("Permissive mode should allow problematic input, but got error: {}\n", .{err});
            try testing.expect(false);
        }
    }
}
