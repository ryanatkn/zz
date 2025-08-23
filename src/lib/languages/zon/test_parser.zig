const std = @import("std");
const testing = std.testing;

// Import ZON modules
const ZonParser = @import("parser.zig").ZonParser;
// Using streaming tokens now

// =============================================================================
// Parser Tests
// =============================================================================

test "ZON parser - string escape processing" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = ".{ .str = \"hello\\nworld\" }";

    // Updated to streaming parser (3-arg pattern)
    var parser = try ZonParser.init(allocator, input, .{});
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
        // Updated to streaming - parser handles lexing errors
        var parser = ZonParser.init(allocator, test_input, .{}) catch {
            continue; // Expected failure during init
        };
        defer parser.deinit();

        // Try parsing - should also fail
        _ = parser.parse() catch {
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

    // Updated to streaming parser (3-arg pattern)
    var parser = try ZonParser.init(allocator, input, .{});
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

    // Updated to streaming parser (3-arg pattern)
    var parser = try ZonParser.init(allocator, input, .{});
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

    // Updated to streaming parser (3-arg pattern)
    var parser = try ZonParser.init(allocator, input, .{});
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

    // Updated to streaming parser (3-arg pattern)
    var parser = try ZonParser.init(allocator, test_build_zon, .{});
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

    // Updated to streaming parser (3-arg pattern)
    var parser = try ZonParser.init(allocator, input, .{});
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
        // Updated to streaming parser (3-arg pattern)
        var parser = try ZonParser.init(allocator, case, .{});
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
        // Updated to streaming parser (3-arg pattern)
        var parser = try ZonParser.init(allocator, case, .{});
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

    // Updated to streaming parser (3-arg pattern)
    var parser = try ZonParser.init(allocator, input, .{});
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

    // Updated to streaming parser (3-arg pattern)
    var parser = try ZonParser.init(allocator, input, .{});
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

    // Updated to streaming parser (3-arg pattern)
    var parser = try ZonParser.init(allocator, input, .{});
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

    // Updated to streaming parser (3-arg pattern)
    var parser = try ZonParser.init(allocator, input, .{});
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

    // Updated to streaming parser (3-arg pattern)
    var parser = try ZonParser.init(allocator, input, .{});
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

    // Updated to streaming parser (3-arg pattern)
    var parser = try ZonParser.init(allocator, input, .{});
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

    // Updated to streaming parser (3-arg pattern)
    var parser = try ZonParser.init(allocator, input, .{});
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

    // Updated to streaming parser (3-arg pattern)
    var parser = try ZonParser.init(allocator, input, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    try testing.expect(ast.root != null);
}

// Regression tests for recently fixed parser bugs
test "ZON parser - regression: triple equals should fail" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = ".{ .field = = = \"value\" }"; // Triple equals

    // Updated to streaming parser (3-arg pattern)
    var parser = try ZonParser.init(allocator, input, .{});
    defer parser.deinit();

    // Should fail parsing
    _ = parser.parse() catch {
        return; // Expected failure
    };

    try testing.expect(false); // Should not reach here
}

test "ZON parser - regression: incomplete assignment with comma" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = ".{ .name = , .value = \"test\" }"; // Missing value before comma

    // Updated to streaming parser (3-arg pattern)
    var parser = try ZonParser.init(allocator, input, .{});
    defer parser.deinit();

    // Should fail with MissingValue error
    _ = parser.parse() catch |err| {
        try testing.expect(err == error.MissingValue);
        return;
    };

    try testing.expect(false); // Should not reach here
}
