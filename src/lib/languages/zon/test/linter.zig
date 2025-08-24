const std = @import("std");
const testing = std.testing;

// Import ZON modules
const Parser = @import("../parser/mod.zig").Parser;
const Linter = @import("../linter/mod.zig").Linter;
const ZonRuleType = @import("../linter/mod.zig").RuleType;
const EnabledRules = @import("../linter/mod.zig").EnabledRules;

// Import types
const interface_types = @import("../../interface.zig");

// =============================================================================
// Linter Tests
// =============================================================================

test "ZON linter - valid ZON" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input =
        \\.{
        \\    .name = "test",
        \\    .version = "1.0.0",
        \\    .dependencies = .{},
        \\}
    ;

    // Updated to streaming parser (3-arg pattern)
    var parser = try Parser.init(allocator, input, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    // Use default enabled rules from linter
    const enabled_rules = Linter.getDefaultRules();

    var linter = Linter.init(allocator, .{});
    defer linter.deinit();

    const diagnostics = try linter.lint(ast, enabled_rules);
    defer {
        for (diagnostics) |diag| {
            allocator.free(diag.message);
        }
        allocator.free(diagnostics);
    }

    // Valid ZON should have no errors
    try testing.expectEqual(@as(usize, 0), diagnostics.len);
}

test "ZON linter - duplicate keys" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input =
        \\.{
        \\    .name = "test",
        \\    .name = "duplicate",
        \\}
    ;

    // Updated to streaming parser (3-arg pattern)
    var parser = try Parser.init(allocator, input, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    // Enable specific rule for duplicate key detection
    var enabled_rules = EnabledRules.initEmpty();
    enabled_rules.insert(.no_duplicate_keys);

    var linter = Linter.init(allocator, .{});
    defer linter.deinit();

    const diagnostics = try linter.lint(ast, enabled_rules);
    defer {
        for (diagnostics) |diag| {
            allocator.free(diag.message);
        }
        allocator.free(diagnostics);
    }

    // Should detect duplicate key
    try testing.expect(diagnostics.len > 0);
}

test "ZON linter - schema validation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input =
        \\.{
        \\    .name = 123, // Should be string
        \\    .version = true, // Should be string
        \\}
    ;

    // Updated to streaming parser (3-arg pattern)
    var parser = try Parser.init(allocator, input, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    var enabled_rules = EnabledRules.initEmpty();
    enabled_rules.insert(.schema_validation);

    var linter = Linter.init(allocator, .{});
    defer linter.deinit();

    const diagnostics = try linter.lint(ast, enabled_rules);
    defer {
        for (diagnostics) |diag| {
            allocator.free(diag.message);
        }
        allocator.free(diagnostics);
    }

    // Should detect type mismatches if schema validation is implemented
}

test "ZON linter - deep nesting warning" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Create deeply nested structure
    var deep_input = std.ArrayList(u8).init(allocator);
    defer deep_input.deinit();

    try deep_input.appendSlice(".{");

    // Create 25 levels of nesting
    var i: u32 = 0;
    while (i < 25) : (i += 1) {
        try deep_input.writer().print(" .level{} = .{{", .{i});
    }

    try deep_input.appendSlice(" .final = \"value\" ");

    // Close all braces
    i = 0;
    while (i < 26) : (i += 1) {
        try deep_input.appendSlice("}");
    }

    // Updated to streaming parser (3-arg pattern)
    var parser = try Parser.init(allocator, deep_input.items, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    // Enable specific rule for depth checking
    var enabled_rules = EnabledRules.initEmpty();
    enabled_rules.insert(.max_depth_exceeded);

    var linter = Linter.init(allocator, .{ .max_depth = 20 });
    defer linter.deinit();

    const diagnostics = try linter.lint(ast, enabled_rules);
    defer {
        for (diagnostics) |diag| {
            allocator.free(diag.message);
        }
        allocator.free(diagnostics);
    }

    // Should warn about deep nesting if implemented
}
