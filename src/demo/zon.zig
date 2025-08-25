const std = @import("std");
const zon = @import("../lib/languages/zon/mod.zig");
const core = @import("core.zig");

pub fn runDemo(runner: core.DemoRunner) !void {
    core.printHeader("ZON Language Demo");

    try demoFormatter(runner);
    try demoLinter(runner);
    try demoValidator(runner);
}

fn demoFormatter(runner: core.DemoRunner) !void {
    core.printSection("Formatter");

    const simple_input = ".{.name=\"test\",.value=123}";
    const complex_input = ".{.str=\"hello\",.num=42,.bool=true,.enumerated=.Active,.char='k',.arr=.{1,2,3},.obj=.{.nested=\"value\"}}";

    core.printExample("Simple", simple_input, "Basic struct formatting");
    const simple_result = try zon.formatString(runner.allocator, simple_input);
    defer runner.allocator.free(simple_result);
    std.debug.print("Formatted:\n{s}\n", .{simple_result});

    runner.printSeparator();

    core.printExample("Complex", complex_input, "All ZON primitives: string, number, boolean, enum literal, char literal, array, struct");
    const complex_result = try zon.formatString(runner.allocator, complex_input);
    defer runner.allocator.free(complex_result);
    std.debug.print("Formatted:\n{s}\n", .{complex_result});
}

fn demoLinter(runner: core.DemoRunner) !void {
    core.printSection("Linter");

    const examples = [_]struct { name: []const u8, code: []const u8 }{
        .{ .name = "Duplicate Fields", .code = ".{.a=1,.a=2}" },
        .{ .name = "Missing Comma", .code = ".{.a=1 .b=2}" },
        .{ .name = "Invalid Char", .code = ".{.char='abc'}" },
    };

    for (examples) |example| {
        core.printExample(example.name, example.code, null);

        const issues = try zon.validateString(runner.allocator, example.code);
        defer {
            for (issues) |issue| runner.allocator.free(issue.message);
            runner.allocator.free(issues);
        }

        if (issues.len > 0) {
            for (issues) |issue| {
                std.debug.print("⚠️  {s} (pos {d}-{d})\n", .{ issue.message, issue.span.start, issue.span.end });
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
        .{ .name = "Missing Brace", .code = ".{.a=1" },
        .{ .name = "Invalid Syntax", .code = ".{a=1}" },
        .{ .name = "Unclosed String", .code = ".{.a=\"test}" },
    };

    for (examples) |example| {
        core.printExample(example.name, example.code, null);

        if (zon.parse(runner.allocator, example.code)) |ast_value| {
            var ast = ast_value;
            ast.deinit();
            runner.printResult(true, "Parsed successfully (unexpected)");
        } else |err| {
            const error_name = @errorName(err);
            runner.printResult(false, error_name);
        }
        std.debug.print("\n", .{});
    }
}
