const std = @import("std");
const json = @import("../lib/languages/json/mod.zig");
const core = @import("core.zig");

pub fn runDemo(runner: core.DemoRunner) !void {
    core.printHeader("JSON Language Demo");

    try demoFormatter(runner);
    try demoRFC8259Compliance(runner);
    try demoEscapeSequences(runner);
    try demoUnicodeValidation(runner);
    try demoValidator(runner);
    try demoLinter(runner);
    try demoErrorCollection(runner);
    try demoPermissiveFeatures(runner);
}

fn demoFormatter(runner: core.DemoRunner) !void {
    core.printSection("Formatter");

    const simple_input = "{\"name\":\"test\",\"value\":123}";
    const complex_input = "{\"str\":\"hello\",\"num\":42,\"bool\":true,\"null\":null,\"arr\":[1,2,3],\"obj\":{\"nested\":\"value\"}}";

    core.printExample("Simple", simple_input, "Basic object formatting");
    const simple_result = try json.formatString(runner.allocator, simple_input);
    defer runner.allocator.free(simple_result);
    std.debug.print("Formatted:\n{s}\n", .{simple_result});

    runner.printSeparator();

    core.printExample("Complex", complex_input, "All JSON primitives: string, number, boolean, null, array, object");
    const complex_result = try json.formatString(runner.allocator, complex_input);
    defer runner.allocator.free(complex_result);
    std.debug.print("Formatted:\n{s}\n", .{complex_result});
}

fn demoRFC8259Compliance(runner: core.DemoRunner) !void {
    core.printSection("RFC 8259 Compliance");

    const NumberTest = struct {
        name: []const u8,
        input: []const u8,
        should_pass: bool,
        description: []const u8,
    };

    const number_tests = [_]NumberTest{
        // Valid numbers per RFC 8259
        .{ .name = "Zero", .input = "0", .should_pass = true, .description = "Single zero is valid" },
        .{ .name = "Negative Zero", .input = "-0", .should_pass = true, .description = "Negative zero is valid" },
        .{ .name = "Simple Integer", .input = "123", .should_pass = true, .description = "Multi-digit integers are valid" },
        .{ .name = "Decimal", .input = "1.5", .should_pass = true, .description = "Decimal numbers are valid" },
        .{ .name = "Scientific (e0)", .input = "1e0", .should_pass = true, .description = "Single digit exponent is valid" },
        .{ .name = "Scientific (e10)", .input = "1e10", .should_pass = true, .description = "Multi-digit exponent is valid" },

        // Invalid numbers per RFC 8259 (our compliance fixes)
        .{ .name = "Leading Zero", .input = "01", .should_pass = false, .description = "Leading zeros are invalid per RFC 8259" },
        .{ .name = "Multiple Leading Zeros", .input = "001", .should_pass = false, .description = "Multiple leading zeros are invalid" },
        .{ .name = "Exponent Leading Zero", .input = "1e01", .should_pass = false, .description = "Exponent leading zeros are invalid (recent fix)" },
        .{ .name = "Trailing Decimal", .input = "1.", .should_pass = false, .description = "Trailing decimal point is invalid" },
        .{ .name = "Leading Decimal", .input = ".5", .should_pass = false, .description = "Leading decimal point is invalid" },
        .{ .name = "Plus Sign", .input = "+1", .should_pass = false, .description = "Leading plus sign is invalid" },
        .{ .name = "Infinity", .input = "Infinity", .should_pass = false, .description = "Infinity literal is invalid in JSON" },
    };

    for (number_tests) |test_case| {
        core.printExample(test_case.name, test_case.input, test_case.description);

        // Test with a complete JSON structure
        const test_json = try std.fmt.allocPrint(runner.allocator, "{{\"value\": {s}}}", .{test_case.input});
        defer runner.allocator.free(test_json);

        // Make silent assertion and display simple result
        if (json.parse(runner.allocator, test_json)) |ast| {
            var ast_mut = ast;
            ast_mut.deinit();

            // Assert this should have succeeded
            if (!test_case.should_pass) {
                std.debug.panic("Demo assertion failed: {s} should be invalid but was accepted\n", .{test_case.input});
            }

            std.debug.print("✅ Valid\n", .{});
        } else |err| {
            // Assert this should have failed
            if (test_case.should_pass) {
                std.debug.panic("Demo assertion failed: {s} should be valid but got error: {}\n", .{ test_case.input, err });
            }

            std.debug.print("❌ {s}\n", .{@errorName(err)});
        }

        runner.printSeparator();
    }
}

fn demoEscapeSequences(runner: core.DemoRunner) !void {
    core.printSection("String Escape Sequences");

    const EscapeTest = struct {
        name: []const u8,
        input: []const u8,
        should_pass: bool,
        description: []const u8,
    };

    const escape_tests = [_]EscapeTest{
        // Valid escape sequences
        .{ .name = "Quote Escape", .input = "\\\"", .should_pass = true, .description = "Escaped quote character" },
        .{ .name = "Backslash Escape", .input = "\\\\", .should_pass = true, .description = "Escaped backslash character" },
        .{ .name = "Newline Escape", .input = "\\n", .should_pass = true, .description = "Escaped newline character" },
        .{ .name = "Tab Escape", .input = "\\t", .should_pass = true, .description = "Escaped tab character" },
        .{ .name = "Unicode ASCII", .input = "\\u0041", .should_pass = true, .description = "Unicode escape for 'A'" },
        .{ .name = "Unicode Symbol", .input = "\\u00A9", .should_pass = true, .description = "Unicode escape for '©'" },

        // Invalid escape sequences
        .{ .name = "Invalid Escape", .input = "\\z", .should_pass = false, .description = "Unknown escape character" },
        .{ .name = "Incomplete Unicode", .input = "\\u041", .should_pass = false, .description = "Incomplete Unicode escape (3 digits)" },
        .{ .name = "Invalid Unicode", .input = "\\uGGGG", .should_pass = false, .description = "Invalid Unicode hex digits" },
        .{ .name = "Unterminated String", .input = "\"hello", .should_pass = false, .description = "String without closing quote" },
    };

    for (escape_tests) |test_case| {
        core.printExample(test_case.name, test_case.input, test_case.description);

        // Test with a complete JSON structure - construct the string properly
        // Special case for unterminated string test
        const test_json = if (std.mem.eql(u8, test_case.name, "Unterminated String"))
            try std.fmt.allocPrint(runner.allocator, "{{\"text\": {s}}}", .{test_case.input})
        else
            try std.fmt.allocPrint(runner.allocator, "{{\"text\": \"{s}\"}}", .{test_case.input});
        defer runner.allocator.free(test_json);

        // Make silent assertion and display simple result
        if (json.parse(runner.allocator, test_json)) |ast| {
            var ast_mut = ast;
            ast_mut.deinit();

            // Assert this should have succeeded
            if (!test_case.should_pass) {
                std.debug.panic("Demo assertion failed: escape '{s}' should be invalid but was accepted\n", .{test_case.input});
            }

            std.debug.print("✅ Valid escape\n", .{});
        } else |err| {
            // Assert this should have failed
            if (test_case.should_pass) {
                std.debug.panic("Demo assertion failed: escape '{s}' should be valid but got error: {}\n", .{ test_case.input, err });
            }

            std.debug.print("❌ {s}\n", .{@errorName(err)});
        }

        runner.printSeparator();
    }
}

fn demoUnicodeValidation(runner: core.DemoRunner) !void {
    core.printSection("Unicode Validation (RFC 9839)");

    const UnicodeTest = struct {
        name: []const u8,
        description: []const u8,
        mode: json.UnicodeMode,
        test_cases: []const TestCase,

        const TestCase = struct {
            name: []const u8,
            input: []const u8,
            should_pass: bool,
        };
    };

    const unicode_tests = [_]UnicodeTest{
        .{
            .name = "Strict Mode (Default)",
            .description = "Rejects problematic Unicode code points per RFC 9839 + enforces Unix line endings",
            .mode = .strict,
            .test_cases = &[_]UnicodeTest.TestCase{
                .{ .name = "Normal Text", .input = "{\"text\": \"hello world\"}", .should_pass = true },
                .{ .name = "Unicode Letters", .input = "{\"text\": \"héllo wörld\"}", .should_pass = true },
                .{ .name = "Tab Character", .input = "{\"text\": \"hello\\tworld\"}", .should_pass = true },
                .{ .name = "Newline Character", .input = "{\"text\": \"hello\\nworld\"}", .should_pass = true },
            },
        },
        .{
            .name = "Permissive Mode",
            .description = "Allows all Unicode characters (escape on output)",
            .mode = .permissive,
            .test_cases = &[_]UnicodeTest.TestCase{
                .{ .name = "Normal Text", .input = "{\"text\": \"hello world\"}", .should_pass = true },
                .{ .name = "Tab Character", .input = "{\"text\": \"hello\\tworld\"}", .should_pass = true },
            },
        },
        .{
            .name = "Sanitize Mode",
            .description = "Replaces problematic characters with U+FFFD (placeholder)",
            .mode = .sanitize,
            .test_cases = &[_]UnicodeTest.TestCase{
                .{ .name = "Normal Text", .input = "{\"text\": \"hello world\"}", .should_pass = true },
            },
        },
    };

    for (unicode_tests) |test_group| {
        core.printExample(test_group.name, "", test_group.description);

        for (test_group.test_cases) |test_case| {
            std.debug.print("  Testing: {s}\n", .{test_case.name});

            var parser = json.Parser.init(runner.allocator, test_case.input, .{ .unicode_mode = test_group.mode }) catch |err| {
                std.debug.print("    ❌ Failed to create parser: {}\n", .{err});
                continue;
            };
            defer parser.deinit();

            const result = parser.parse();
            if (result) |ast| {
                var ast_mut = ast;
                ast_mut.deinit();
                if (test_case.should_pass) {
                    std.debug.print("    ✅ Passed as expected\n", .{});
                } else {
                    std.debug.print("    ❌ Should have failed but passed\n", .{});
                }
            } else |err| {
                if (test_case.should_pass) {
                    std.debug.print("    ❌ Should have passed but failed: {}\n", .{err});
                } else {
                    std.debug.print("    ✅ Failed as expected: {}\n", .{err});
                }
            }
        }

        runner.printSeparator();
    }
}

fn demoLinter(runner: core.DemoRunner) !void {
    core.printSection("Linter");

    const examples = [_]struct {
        name: []const u8,
        code: []const u8,
        description: ?[]const u8 = null,
    }{
        .{ .name = "Single Duplicate Key", .code = "{\"name\":\"first\",\"name\":\"second\"}" },
        .{ .name = "Multiple Duplicate Keys", .code = "{\"dup1\":1,\"dup1\":2,\"dup2\":\"a\",\"dup2\":\"b\",\"dup3\":true,\"dup3\":false}", .description = "Three different duplicate key pairs - shows comprehensive error collection" },
        .{ .name = "Complex Object", .code = "{\"user\":\"john\",\"user\":\"jane\",\"config\":{\"debug\":true},\"data\":[1,2,3]}", .description = "Real-world example with duplicate user field" },
    };

    for (examples) |example| {
        core.printExample(example.name, example.code, example.description);

        const issues = try json.validate(runner.allocator, example.code);
        defer {
            for (issues) |issue| runner.allocator.free(issue.message);
            runner.allocator.free(issues);
        }

        if (issues.len > 0) {
            if (issues.len == 1) {
                std.debug.print("⚠️  {s} (pos {d}-{d})\n", .{ issues[0].message, issues[0].range.start, issues[0].range.end });
            } else {
                std.debug.print("📋 Found {} issues:\n", .{issues.len});
                for (issues, 1..) |issue, i| {
                    std.debug.print("   {d}. {s} (pos {d}-{d})\n", .{ i, issue.message, issue.range.start, issue.range.end });
                }
            }
        } else {
            runner.printResult(true, "No issues found");
        }
        std.debug.print("\n", .{});
    }
}

fn demoValidator(runner: core.DemoRunner) !void {
    core.printSection("Validator");

    const examples = [_]struct { name: []const u8, code: []const u8 }{
        .{ .name = "Missing Brace", .code = "{\"a\":1" },
        .{ .name = "Invalid Token", .code = "{a:1}" },
        .{ .name = "Unclosed String", .code = "{\"a\":\"test}" },
    };

    for (examples) |example| {
        core.printExample(example.name, example.code, null);

        // These examples should all fail to parse (invalid syntax)
        if (json.parse(runner.allocator, example.code)) |ast| {
            var ast_mut = ast;
            ast_mut.deinit();
            std.debug.panic("Demo assertion failed: '{s}' should be invalid but was accepted\n", .{example.code});
        } else |err| {
            std.debug.print("❌ {s}\n", .{@errorName(err)});
        }

        std.debug.print("\n", .{});
    }
}

fn demoErrorCollection(runner: core.DemoRunner) !void {
    core.printSection("Error Collection");

    // Multiple errors in one document
    const multi_error_input = "{\"a\":1 \"b\":2 \"c\":}";
    core.printExample("Multiple Errors (collect_all_errors: true)", multi_error_input, "Default: collects all errors for comprehensive diagnostics");

    // Test with collect_all_errors = true (default)
    var parser_collect = try json.Parser.init(runner.allocator, multi_error_input, .{ .collect_all_errors = true });
    defer parser_collect.deinit();

    _ = parser_collect.parse() catch |err| {
        std.debug.print("❌ {s} (as expected)\n", .{@errorName(err)});
    };

    const errors_collect = parser_collect.getErrors();
    std.debug.print("📋 Collected {} errors:\n", .{errors_collect.len});
    for (errors_collect, 1..) |error_item, i| {
        std.debug.print("   {d}. {s} (pos {d}-{d})\n", .{ i, error_item.message, error_item.span.start, error_item.span.end });
    }

    std.debug.print("\n", .{});

    // Same input with fail-fast mode
    core.printExample("Same Input (collect_all_errors: false)", multi_error_input, "Fail-fast mode: stops after first error");

    var parser_fast = try json.Parser.init(runner.allocator, multi_error_input, .{ .collect_all_errors = false });
    defer parser_fast.deinit();

    _ = parser_fast.parse() catch |err| {
        std.debug.print("❌ {s} (stops immediately)\n", .{@errorName(err)});
    };

    const errors_fast = parser_fast.getErrors();
    std.debug.print("📋 Collected {} error{s}:\n", .{ errors_fast.len, if (errors_fast.len == 1) "" else "s" });
    for (errors_fast, 1..) |error_item, i| {
        std.debug.print("   {d}. {s} (pos {d}-{d})\n", .{ i, error_item.message, error_item.span.start, error_item.span.end });
    }

    std.debug.print("\n", .{});
}

fn demoPermissiveFeatures(runner: core.DemoRunner) !void {
    core.printSection("Permissive Features");

    const examples = [_]struct {
        name: []const u8,
        code: []const u8,
        description: []const u8,
        parser_options: json.ParserOptions,
    }{
        .{
            .name = "Trailing Commas (allow_trailing_commas: true, default)",
            .code = "{\"a\":1,\"b\":2,}",
            .description = "Default: trailing commas are permitted",
            .parser_options = .{ .allow_trailing_commas = true },
        },
        .{
            .name = "Trailing Commas (allow_trailing_commas: false)",
            .code = "{\"a\":1,\"b\":2,}",
            .description = "Strict mode: trailing commas generate errors",
            .parser_options = .{ .allow_trailing_commas = false },
        },
        .{
            .name = "Array Trailing Comma (allow_trailing_commas: true, default)",
            .code = "[1,2,3,]",
            .description = "Arrays also support trailing comma permissiveness",
            .parser_options = .{ .allow_trailing_commas = true },
        },
        .{
            .name = "Comments (allow_comments: true, default)",
            .code = "{\"a\":1,/* comment */\"b\":2}",
            .description = "Default: JSON5 comments are allowed",
            .parser_options = .{ .allow_comments = true },
        },
        .{
            .name = "Comments (allow_comments: false)",
            .code = "{\"a\":1,/* comment */\"b\":2}",
            .description = "Strict JSON: comments generate errors",
            .parser_options = .{ .allow_comments = false },
        },
    };

    for (examples) |example| {
        core.printExample(example.name, example.code, example.description);

        var parser = try json.Parser.init(runner.allocator, example.code, example.parser_options);
        defer parser.deinit();

        if (parser.parse()) |ast| {
            var ast_mut = ast;
            ast_mut.deinit();
            std.debug.print("✅ Parsed successfully\n", .{});

            const errors = parser.getErrors();
            if (errors.len > 0) {
                std.debug.print("⚠️  With {} warning{s}:\n", .{ errors.len, if (errors.len == 1) "" else "s" });
                for (errors) |error_item| {
                    std.debug.print("   - {s} (severity: {s})\n", .{ error_item.message, @tagName(error_item.severity) });
                }
            }
        } else |err| {
            std.debug.print("❌ {s}\n", .{@errorName(err)});

            const errors = parser.getErrors();
            if (errors.len > 0) {
                std.debug.print("📋 Error details:\n", .{});
                for (errors) |error_item| {
                    std.debug.print("   - {s}\n", .{error_item.message});
                }
            }
        }

        std.debug.print("\n", .{});
    }
}
