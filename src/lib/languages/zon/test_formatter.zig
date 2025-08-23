const std = @import("std");
const testing = std.testing;

// Import ZON modules
const ZonParser = @import("parser.zig").ZonParser;
const ZonFormatter = @import("formatter.zig").ZonFormatter;
const formatZonString = @import("mod.zig").formatZonString;
const FormatOptions = @import("../interface.zig").FormatOptions;

// =============================================================================
// Formatter Tests
// =============================================================================

test "ZON formatter - basic formatting" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = ".{.name=\"test\",.version=\"1.0.0\"}";

    // Updated to streaming parser (3-arg pattern)
    var parser = try ZonParser.init(allocator, input, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    var formatter = ZonFormatter.init(allocator, .{});
    defer formatter.deinit();

    const formatted = try formatter.format(ast);
    defer allocator.free(formatted);

    try testing.expect(formatted.len > input.len); // Should have whitespace
}

test "ZON formatter - preserve structure" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input =
        \\.{
        \\    .name = "test",
        \\    .dependencies = .{
        \\        .package = .{
        \\            .url = "https://example.com",
        \\        },
        \\    },
        \\}
    ;

    // Updated to streaming parser (3-arg pattern)
    var parser = try ZonParser.init(allocator, input, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    var formatter = ZonFormatter.init(allocator, .{});
    defer formatter.deinit();

    const formatted = try formatter.format(ast);
    defer allocator.free(formatted);

    try testing.expect(formatted.len > 0);
}

test "ZON formatter - compact vs multiline" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = ".{ .name = \"test\", .version = \"1.0.0\" }";

    // Updated to streaming parser (3-arg pattern)
    var parser = try ZonParser.init(allocator, input, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    // Test compact formatting
    var compact_formatter = ZonFormatter.init(allocator, .{ .compact_small_objects = true, .compact_small_arrays = true });
    defer compact_formatter.deinit();

    const compact = try compact_formatter.format(ast);
    defer allocator.free(compact);

    // Test multiline formatting
    var multiline_formatter = ZonFormatter.init(allocator, .{ .compact_small_objects = false, .compact_small_arrays = false });
    defer multiline_formatter.deinit();

    const multiline = try multiline_formatter.format(ast);
    defer allocator.free(multiline);

    try testing.expect(compact.len < multiline.len);
}

test "ZON formatter - round trip" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const inputs = [_][]const u8{
        ".{ .name = \"test\" }",
        ".{ .number = 42 }",
        ".{ .boolean = true }",
        ".{ .null_val = null }",
        ".{ .nested = .{ .field = \"value\" } }",
    };

    for (inputs) |input| {
        // Parse original - Updated to streaming parser
        var parser1 = try ZonParser.init(allocator, input, .{});
        defer parser1.deinit();

        var ast1 = try parser1.parse();
        defer ast1.deinit();

        // Format it
        var formatter = ZonFormatter.init(allocator, .{});
        defer formatter.deinit();

        const formatted = try formatter.format(ast1);
        defer allocator.free(formatted);

        // Parse formatted version
        // Updated to streaming parser (3-arg pattern)
        var parser2 = try ZonParser.init(allocator, formatted, .{});
        defer parser2.deinit();

        var ast2 = try parser2.parse();
        defer ast2.deinit();

        // Both should be valid
        try testing.expect(ast1.root != null);
        try testing.expect(ast2.root != null);
    }
}

// =============================================================================
// Demo Issue Tests - Exact scenarios from the demo that were failing
// =============================================================================

test "ZON formatter - demo issue: simple config with leading dot" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // This is the exact input from the demo that was dropping the leading dot
    const input = ".{.name=\"zz\",.version=\"1.0.0\",.debug=true,.workers=4,}";

    // Updated to streaming parser (3-arg pattern)
    var parser = try ZonParser.init(allocator, input, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    var formatter = ZonFormatter.init(allocator, .{});
    defer formatter.deinit();

    const formatted = try formatter.format(ast);
    defer allocator.free(formatted);

    // Check that the formatted output starts with ".{" not just "{"
    try testing.expect(std.mem.startsWith(u8, formatted, ".{"));

    // Should not contain just "{" without the leading dot
    try testing.expect(!std.mem.startsWith(u8, formatted, "{\n"));
}

test "ZON formatter - demo issue: tuple structures should use .{ not [" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // This is the exact input from the demo that was getting formatted with []
    const input = ".{.{.id=1,.name=\"Alice\",.active=true,.role=\"admin\"},.{.id=2,.name=\"Bob\",.active=false,.role=\"user\"},.{.id=3,.name=\"Charlie\",.active=true,.role=\"moderator\"},}";

    // Updated to streaming parser (3-arg pattern)
    var parser = try ZonParser.init(allocator, input, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    var formatter = ZonFormatter.init(allocator, .{});
    defer formatter.deinit();

    const formatted = try formatter.format(ast);
    defer allocator.free(formatted);

    // Check that the formatted output starts with ".{" not "["
    try testing.expect(std.mem.startsWith(u8, formatted, ".{"));

    // Should not contain square brackets
    try testing.expect(std.mem.indexOf(u8, formatted, "[") == null);
    try testing.expect(std.mem.indexOf(u8, formatted, "]") == null);

    // Should contain the proper ZON tuple syntax ".{" for nested objects
    try testing.expect(std.mem.indexOf(u8, formatted, ".{") != null);
}

test "ZON formatter - verify all containers use .{ syntax" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const test_cases = [_][]const u8{
        ".{}",
        ".{.name=\"test\"}",
        ".{.nested=.{.inner=\"value\"}}",
        ".{.list=.{\"one\",\"two\",\"three\"}}",
        ".{.mixed=.{.str=\"hello\",.num=42,.bool=true}}",
    };

    for (test_cases) |input| {
        // Updated to streaming parser (3-arg pattern)
        var parser = try ZonParser.init(allocator, input, .{});
        defer parser.deinit();

        var ast = try parser.parse();
        defer ast.deinit();

        var formatter = ZonFormatter.init(allocator, .{});
        defer formatter.deinit();

        const formatted = try formatter.format(ast);
        defer allocator.free(formatted);

        // All ZON structures should start with ".{"
        try testing.expect(std.mem.startsWith(u8, formatted, ".{"));

        // Should never have square brackets or plain braces without dots
        try testing.expect(std.mem.indexOf(u8, formatted, "[") == null);
        try testing.expect(std.mem.indexOf(u8, formatted, "]") == null);
        try testing.expect(!std.mem.startsWith(u8, formatted, "{"));
    }
}

// =============================================================================
// Edge Case Tests for Formatter Robustness
// =============================================================================

test "ZON formatter - empty structure formatting" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const test_cases = [_][]const u8{
        ".{}",
        ".{ }",
        ".{\n}",
    };

    for (test_cases) |input| {
        // Updated to streaming parser (3-arg pattern)
        var parser = try ZonParser.init(allocator, input, .{});
        defer parser.deinit();

        var ast = try parser.parse();
        defer ast.deinit();

        var formatter = ZonFormatter.init(allocator, .{});
        defer formatter.deinit();

        const formatted = try formatter.format(ast);
        defer allocator.free(formatted);

        // Empty structures should format to ".{}"
        try testing.expectEqualStrings(".{}", formatted);
    }
}

test "ZON formatter - deeply nested structures" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = ".{.a=.{.b=.{.c=\"deep\"}}}";

    // Updated to streaming parser (3-arg pattern)
    var parser = try ZonParser.init(allocator, input, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    var formatter = ZonFormatter.init(allocator, .{});
    defer formatter.deinit();

    const formatted = try formatter.format(ast);
    defer allocator.free(formatted);

    // Should start with .{ and contain nested structures
    try testing.expect(std.mem.startsWith(u8, formatted, ".{"));
    try testing.expect(std.mem.indexOf(u8, formatted, ".a") != null);
    try testing.expect(std.mem.indexOf(u8, formatted, ".b") != null);
    try testing.expect(std.mem.indexOf(u8, formatted, ".c") != null);
}

test "ZON formatter - mixed value types in structures" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = ".{.str=\"hello\",.num=42,.bool=true,.null_val=null}";

    // Updated to streaming parser (3-arg pattern)
    var parser = try ZonParser.init(allocator, input, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    var formatter = ZonFormatter.init(allocator, .{});
    defer formatter.deinit();

    const formatted = try formatter.format(ast);
    defer allocator.free(formatted);

    // Should contain all value types correctly formatted
    try testing.expect(std.mem.startsWith(u8, formatted, ".{"));
    try testing.expect(std.mem.indexOf(u8, formatted, "\"hello\"") != null);
    try testing.expect(std.mem.indexOf(u8, formatted, "42") != null);
    try testing.expect(std.mem.indexOf(u8, formatted, "true") != null);
    try testing.expect(std.mem.indexOf(u8, formatted, "null") != null);
}

test "ZON formatter - compact vs multiline decisions" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = ".{.field1=\"value1\",.field2=\"value2\",.field3=\"value3\",.field4=\"value4\"}";

    // Updated to streaming parser (3-arg pattern)
    var parser = try ZonParser.init(allocator, input, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    // Test compact formatting
    var compact_formatter = ZonFormatter.init(allocator, .{ .compact_small_objects = true });
    defer compact_formatter.deinit();

    const compact = try compact_formatter.format(ast);
    defer allocator.free(compact);

    // Test multiline formatting
    var multiline_formatter = ZonFormatter.init(allocator, .{ .compact_small_objects = false });
    defer multiline_formatter.deinit();

    const multiline = try multiline_formatter.format(ast);
    defer allocator.free(multiline);

    // Compact should be shorter than multiline
    try testing.expect(compact.len < multiline.len);

    // Both should start with .{
    try testing.expect(std.mem.startsWith(u8, compact, ".{"));
    try testing.expect(std.mem.startsWith(u8, multiline, ".{"));

    // Multiline should contain newlines
    try testing.expect(std.mem.indexOf(u8, multiline, "\n") != null);
}

test "ZON formatter - formatZonString function integration" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = ".{.name=\"test\",.value=123}";

    const formatted = try formatZonString(allocator, input);
    defer allocator.free(formatted);

    // Should produce valid formatted output starting with .{
    try testing.expect(std.mem.startsWith(u8, formatted, ".{"));
    try testing.expect(std.mem.indexOf(u8, formatted, ".name") != null);
    try testing.expect(std.mem.indexOf(u8, formatted, ".value") != null);
    try testing.expect(formatted.len > input.len); // Should be expanded with formatting
}
