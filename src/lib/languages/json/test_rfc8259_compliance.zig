const std = @import("std");
const testing = std.testing;
const JsonLexer = @import("lexer.zig").JsonLexer;
const JsonParser = @import("parser.zig").JsonParser;

/// Comprehensive RFC 8259 compliance tests for JSON number handling
/// 
/// RFC 8259, Section 6: "Leading zeros are not allowed."
/// Grammar: int = zero / ( digit1-9 *DIGIT )

test "RFC 8259 compliance - invalid leading zeros should be rejected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Test cases that MUST be rejected per RFC 8259
    const invalid_cases = [_]struct {
        input: []const u8,
        description: []const u8,
    }{
        // Basic leading zeros
        .{ .input = "01", .description = "single leading zero" },
        .{ .input = "00", .description = "double zero" },
        .{ .input = "001", .description = "multiple leading zeros" },
        .{ .input = "0123", .description = "leading zero with multiple digits" },
        .{ .input = "000123", .description = "multiple leading zeros with digits" },
        
        // Negative numbers with leading zeros
        .{ .input = "-01", .description = "negative with single leading zero" },
        .{ .input = "-00", .description = "negative with double zero" },
        .{ .input = "-001", .description = "negative with multiple leading zeros" },
        .{ .input = "-0123", .description = "negative leading zero with digits" },
        
        // Leading zeros with decimals and exponents (still invalid)
        .{ .input = "01.5", .description = "leading zero with decimal" },
        .{ .input = "01e10", .description = "leading zero with exponent" },
        .{ .input = "01E10", .description = "leading zero with uppercase exponent" },
        .{ .input = "-01.5", .description = "negative leading zero with decimal" },
        .{ .input = "-01e10", .description = "negative leading zero with exponent" },
        
        // In JSON structures
        .{ .input = "[01]", .description = "leading zero in array" },
        .{ .input = "[01, 02, 03]", .description = "multiple leading zeros in array" },
        .{ .input = "{\"a\": 01}", .description = "leading zero as object value" },
        .{ .input = "{\"a\": 01, \"b\": 02}", .description = "multiple leading zeros in object" },
        .{ .input = "[0, 01, 1]", .description = "mixed valid/invalid in array" },
    };

    for (invalid_cases) |case| {
        var lexer = JsonLexer.init(allocator, case.input, .{});
        defer lexer.deinit();
        
        // Should fail during tokenization (lexer rejects leading zeros)
        const tokens = lexer.tokenize() catch |err| {
            try testing.expect(err == error.InvalidNumber);
            continue; // Expected failure
        };
        defer allocator.free(tokens);

        // If tokenization unexpectedly succeeds, parsing should catch it
        var parser = JsonParser.init(allocator, tokens, .{});
        defer parser.deinit();
        var ast = parser.parse() catch |err| {
            try testing.expect(err == error.ParseError);
            continue; // Expected failure
        };
        defer ast.deinit();

        // If parsing also succeeds, check for parser errors
        const errors = parser.getErrors();
        if (errors.len == 0) {
            std.debug.print("UNEXPECTED SUCCESS: '{s}' ({s}) should have been rejected\n", .{ case.input, case.description });
        }
        try testing.expect(errors.len > 0);
    }
}

test "RFC 8259 compliance - valid numbers should be accepted" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Test cases that MUST be accepted per RFC 8259
    const valid_cases = [_]struct {
        input: []const u8,
        description: []const u8,
    }{
        // Valid integers
        .{ .input = "0", .description = "single zero" },
        .{ .input = "1", .description = "single digit" },
        .{ .input = "10", .description = "no leading zero" },
        .{ .input = "123", .description = "multi-digit integer" },
        .{ .input = "999", .description = "large integer" },
        
        // Valid negative integers
        .{ .input = "-0", .description = "negative zero" },
        .{ .input = "-1", .description = "negative single digit" },
        .{ .input = "-10", .description = "negative no leading zero" },
        .{ .input = "-123", .description = "negative multi-digit" },
        
        // Valid decimals
        .{ .input = "0.0", .description = "zero with decimal" },
        .{ .input = "0.1", .description = "zero with non-zero decimal" },
        .{ .input = "1.0", .description = "integer with zero decimal" },
        .{ .input = "1.23", .description = "number with decimal" },
        .{ .input = "-0.1", .description = "negative decimal" },
        .{ .input = "-1.23", .description = "negative number with decimal" },
        
        // Valid exponents
        .{ .input = "0e0", .description = "zero with exponent" },
        .{ .input = "0E0", .description = "zero with uppercase exponent" },
        .{ .input = "1e10", .description = "integer with exponent" },
        .{ .input = "1E10", .description = "integer with uppercase exponent" },
        .{ .input = "1e+10", .description = "integer with positive exponent" },
        .{ .input = "1e-10", .description = "integer with negative exponent" },
        .{ .input = "1.5e10", .description = "decimal with exponent" },
        .{ .input = "-1.5e-10", .description = "negative decimal with negative exponent" },
        
        // Valid in JSON structures
        .{ .input = "[0]", .description = "valid zero in array" },
        .{ .input = "[1, 2, 3]", .description = "valid numbers in array" },
        .{ .input = "{\"a\": 0}", .description = "valid zero as object value" },
        .{ .input = "{\"a\": 123, \"b\": -456}", .description = "valid numbers in object" },
        .{ .input = "[0, 10, 100]", .description = "valid numbers without leading zeros" },
    };

    for (valid_cases) |case| {
        var lexer = JsonLexer.init(allocator, case.input, .{});
        defer lexer.deinit();
        
        const tokens = lexer.tokenize() catch |err| {
            std.debug.print("UNEXPECTED FAILURE: '{s}' ({s}) should have been accepted during tokenization: {}\n", .{ case.input, case.description, err });
            return err;
        };
        defer allocator.free(tokens);

        var parser = JsonParser.init(allocator, tokens, .{});
        defer parser.deinit();
        var ast = parser.parse() catch |err| {
            std.debug.print("UNEXPECTED FAILURE: '{s}' ({s}) should have been accepted during parsing: {}\n", .{ case.input, case.description, err });
            return err;
        };
        defer ast.deinit();

        // Check that parsing succeeded without errors
        const errors = parser.getErrors();
        if (errors.len > 0) {
            std.debug.print("UNEXPECTED ERRORS: '{s}' ({s}) should not have parser errors\n", .{ case.input, case.description });
            for (errors) |error_item| {
                std.debug.print("  Error: {s}\n", .{error_item.message});
            }
        }
        try testing.expectEqual(@as(usize, 0), errors.len);
    }
}

test "RFC 8259 compliance - edge cases" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Edge cases that should be handled correctly
    const test_cases = [_]struct {
        input: []const u8,
        should_succeed: bool,
        description: []const u8,
    }{
        // Boundary cases
        .{ .input = "0", .should_succeed = true, .description = "exactly zero" },
        .{ .input = "00", .should_succeed = false, .description = "double zero (invalid)" },
        .{ .input = "0.0", .should_succeed = true, .description = "zero decimal (valid)" },
        .{ .input = "00.0", .should_succeed = false, .description = "double zero decimal (invalid)" },
        
        // Scientific notation edge cases  
        .{ .input = "0e1", .should_succeed = true, .description = "zero with exponent (valid)" },
        .{ .input = "00e1", .should_succeed = false, .description = "double zero with exponent (invalid)" },
        .{ .input = "1e01", .should_succeed = false, .description = "exponent with leading zero (invalid)" },
        
        // Complex structures
        .{ .input = "{\"valid\": 0, \"invalid\": 01}", .should_succeed = false, .description = "mixed valid/invalid in object" },
        .{ .input = "[0, 1, 2]", .should_succeed = true, .description = "all valid numbers" },
        .{ .input = "[0, 01, 2]", .should_succeed = false, .description = "mixed valid/invalid in array" },
    };

    for (test_cases) |case| {
        var lexer = JsonLexer.init(allocator, case.input, .{});
        defer lexer.deinit();
        
        const tokens = lexer.tokenize() catch |err| {
            if (case.should_succeed) {
                std.debug.print("UNEXPECTED LEXER FAILURE: '{s}' ({s}) should have succeeded: {}\n", .{ case.input, case.description, err });
                return err;
            } else {
                // Expected failure
                try testing.expect(err == error.InvalidNumber);
                continue;
            }
        };
        defer allocator.free(tokens);

        var parser = JsonParser.init(allocator, tokens, .{});
        defer parser.deinit();
        var ast = parser.parse() catch |err| {
            if (case.should_succeed) {
                std.debug.print("UNEXPECTED PARSER FAILURE: '{s}' ({s}) should have succeeded: {}\n", .{ case.input, case.description, err });
                return err;
            } else {
                // Expected failure
                try testing.expect(err == error.ParseError);
                continue;
            }
        };
        defer ast.deinit();

        const errors = parser.getErrors();
        if (case.should_succeed) {
            // Should have no errors
            if (errors.len > 0) {
                std.debug.print("UNEXPECTED PARSER ERRORS: '{s}' ({s}) should not have errors\n", .{ case.input, case.description });
                for (errors) |error_item| {
                    std.debug.print("  Error: {s}\n", .{error_item.message});
                }
            }
            try testing.expectEqual(@as(usize, 0), errors.len);
        } else {
            // Should have errors
            if (errors.len == 0) {
                std.debug.print("MISSING EXPECTED ERRORS: '{s}' ({s}) should have been rejected\n", .{ case.input, case.description });
            }
            try testing.expect(errors.len > 0);
        }
    }
}