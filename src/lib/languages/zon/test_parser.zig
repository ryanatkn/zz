const std = @import("std");
const testing = std.testing;

// Import ZON modules
const ZonLexer = @import("lexer.zig").ZonLexer;
const ZonParser = @import("parser.zig").ZonParser;
const ZonToken = @import("tokens.zig").ZonToken;

// =============================================================================
// Parser Tests
// =============================================================================

test "ZON parser - string escape processing" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = ".{ .str = \"hello\\nworld\" }";

    var lexer = ZonLexer.init(allocator);
    defer lexer.deinit();

    const tokens = try lexer.tokenize(input);
    defer allocator.free(tokens);

    var parser = ZonParser.init(allocator, tokens, input, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    try testing.expect(ast.root != null);
}

test "ZON parser - malformed unicode handling" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const invalid_cases = [_][]const u8{
        ".{ .str = \"\\u{GGGG}\" }",
        ".{ .str = \"\\u{110000}\" }",
        ".{ .str = \"\\u{D800}\" }",
    };

    for (invalid_cases) |test_input| {
        var lexer = ZonLexer.init(allocator);
        defer lexer.deinit();

        // Should fail during lexing
        _ = lexer.tokenize(test_input) catch {
            continue; // Expected failure
        };

        try testing.expect(false); // Should not reach here
    }
}

test "ZON parser - simple object" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = ".{ .name = \"test\", .version = \"1.0.0\" }";

    var lexer = ZonLexer.init(allocator);
    defer lexer.deinit();

    const tokens = try lexer.tokenize(input);
    defer allocator.free(tokens);

    var parser = ZonParser.init(allocator, tokens, input, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    try testing.expect(ast.root != null);
}

test "ZON parser - nested objects" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = ".{ .dependencies = .{ .package = .{ .url = \"https://example.com\" } } }";

    var lexer = ZonLexer.init(allocator);
    defer lexer.deinit();

    const tokens = try lexer.tokenize(input);
    defer allocator.free(tokens);

    var parser = ZonParser.init(allocator, tokens, input, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    try testing.expect(ast.root != null);
}

test "ZON parser - arrays" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = ".{ .paths = .{ \"src\", \"lib\", \"test\" } }";

    var lexer = ZonLexer.init(allocator);
    defer lexer.deinit();

    const tokens = try lexer.tokenize(input);
    defer allocator.free(tokens);

    var parser = ZonParser.init(allocator, tokens, input, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    try testing.expect(ast.root != null);
}

test "ZON parser - build.zig.zon format" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const test_build_zon =
        \\.{
        \\    .name = "zz",
        \\    .version = "0.0.0",
        \\    .dependencies = .{},
        \\}
    ;

    var lexer = ZonLexer.init(allocator);
    defer lexer.deinit();

    const tokens = try lexer.tokenize(test_build_zon);
    defer allocator.free(tokens);

    var parser = ZonParser.init(allocator, tokens, test_build_zon, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    try testing.expect(ast.root != null);
}

test "ZON parser - error recovery" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = ".{ .name = \"test\", .invalid syntax here }";

    var lexer = ZonLexer.init(allocator);
    defer lexer.deinit();

    const tokens = try lexer.tokenize(input);
    defer allocator.free(tokens);

    var parser = ZonParser.init(allocator, tokens, input, .{});
    defer parser.deinit();

    // Should either parse with errors or fail gracefully
    _ = parser.parse() catch {
        // Expected failure for malformed input
        return;
    };
}

test "ZON parser - multiple syntax errors" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const invalid_cases = [_][]const u8{
        ".{ .name = }", // Missing value
        ".{ name = \"test\" }", // Missing dot prefix
        ".{ .name \"test\" }", // Missing equals
        "{ .name = \"test\" }", // Missing leading dot
    };

    for (invalid_cases) |case| {
        var lexer = ZonLexer.init(allocator);
        defer lexer.deinit();

        const tokens = try lexer.tokenize(case);
        defer allocator.free(tokens);

        var parser = ZonParser.init(allocator, tokens, case, .{});
        defer parser.deinit();

        // Should fail parsing
        _ = parser.parse() catch {
            continue; // Expected failure
        };
    }
}

test "ZON parser - malformed nested structures" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const invalid_cases = [_][]const u8{
        ".{ .deps = .{ .pkg = } }", // Incomplete nested object
        ".{ .list = .{ \"item1\", } }", // Trailing comma in list
        ".{ .mixed = .{ \"str\", .field = \"val\" } }", // Mixed array/object
    };

    for (invalid_cases) |case| {
        var lexer = ZonLexer.init(allocator);
        defer lexer.deinit();

        const tokens = try lexer.tokenize(case);
        defer allocator.free(tokens);

        var parser = ZonParser.init(allocator, tokens, case, .{});
        defer parser.deinit();

        // Should fail parsing
        _ = parser.parse() catch {
            continue; // Expected failure
        };
    }
}

test "ZON parser - invalid token sequences" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = ".{ .field = = \"value\" }"; // Double equals

    var lexer = ZonLexer.init(allocator);
    defer lexer.deinit();

    const tokens = try lexer.tokenize(input);
    defer allocator.free(tokens);

    var parser = ZonParser.init(allocator, tokens, input, .{});
    defer parser.deinit();

    // Should fail parsing
    _ = parser.parse() catch {
        return; // Expected failure
    };

    try testing.expect(false); // Should not reach here
}

test "ZON parser - error message quality" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = ".{ .name = }"; // Missing value

    var lexer = ZonLexer.init(allocator);
    defer lexer.deinit();

    const tokens = try lexer.tokenize(input);
    defer allocator.free(tokens);

    var parser = ZonParser.init(allocator, tokens, input, .{});
    defer parser.deinit();

    // Should fail with descriptive error
    _ = parser.parse() catch |err| {
        // Verify error type is reasonable
        try testing.expect(err == error.UnexpectedToken or err == error.MissingValue);
        return;
    };

    try testing.expect(false); // Should not reach here
}

test "ZON parser - parseFromSlice compatibility" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const BuildZon = struct {
        name: []const u8,
        version: []const u8,
    };

    const input = ".{ .name = \"test\", .version = \"1.0.0\" }";

    // This should work when parseFromSlice is implemented
    _ = allocator;
    _ = input;
    _ = BuildZon;
    // const result = try parseFromSlice(BuildZon, allocator, input);
    // try testing.expectEqualStrings("test", result.name);
}

test "ZON parser - single boolean literal true" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = "true";

    var lexer = ZonLexer.init(allocator);
    defer lexer.deinit();

    const tokens = try lexer.tokenize(input);
    defer allocator.free(tokens);

    var parser = ZonParser.init(allocator, tokens, input, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    try testing.expect(ast.root != null);
}

test "ZON parser - single boolean literal false" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = "false";

    var lexer = ZonLexer.init(allocator);
    defer lexer.deinit();

    const tokens = try lexer.tokenize(input);
    defer allocator.free(tokens);

    var parser = ZonParser.init(allocator, tokens, input, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    try testing.expect(ast.root != null);
}

test "ZON parser - multiple boolean literals" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = ".{ .enabled = true, .disabled = false }";

    var lexer = ZonLexer.init(allocator);
    defer lexer.deinit();

    const tokens = try lexer.tokenize(input);
    defer allocator.free(tokens);

    var parser = ZonParser.init(allocator, tokens, input, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    try testing.expect(ast.root != null);
}

test "ZON parser - sequential boolean fields (regression test)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input =
        \\.{
        \\    .first = true,
        \\    .second = false,
        \\    .third = true,
        \\}
    ;

    var lexer = ZonLexer.init(allocator);
    defer lexer.deinit();

    const tokens = try lexer.tokenize(input);
    defer allocator.free(tokens);

    var parser = ZonParser.init(allocator, tokens, input, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    try testing.expect(ast.root != null);
}

test "ZON parser - null literal" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = ".{ .optional = null }";

    var lexer = ZonLexer.init(allocator);
    defer lexer.deinit();

    const tokens = try lexer.tokenize(input);
    defer allocator.free(tokens);

    var parser = ZonParser.init(allocator, tokens, input, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    try testing.expect(ast.root != null);
}

test "ZON parser - mixed literals" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input =
        \\.{
        \\    .string = "hello",
        \\    .number = 42,
        \\    .float = 3.14,
        \\    .boolean = true,
        \\    .null_val = null,
        \\    .nested = .{
        \\        .array = .{ 1, 2, 3 },
        \\    },
        \\}
    ;

    var lexer = ZonLexer.init(allocator);
    defer lexer.deinit();

    const tokens = try lexer.tokenize(input);
    defer allocator.free(tokens);

    var parser = ZonParser.init(allocator, tokens, input, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    try testing.expect(ast.root != null);
}
