/// JSON Parser - Combined Core and Values Functionality
///
/// This module provides a unified interface to the split parser components
const std = @import("std");

// Re-export core parser
pub const JsonParser = @import("core.zig").JsonParser;

// Re-export value parsing utilities (accessible as parser.values.*)
pub const values = @import("values.zig");

// Re-export commonly used types and functions
pub const ParseError = JsonParser.ParseError;
pub const ParserOptions = JsonParser.ParserOptions;

// ============================================================================
// Tests for Complete Parser Functionality
// ============================================================================

test "JSON streaming parser - simple values" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const inputs = [_][]const u8{
        "\"hello\"",
        "123",
        "true",
        "false",
        "null",
    };

    for (inputs) |input| {
        var parser = try JsonParser.init(allocator, input, .{});
        defer parser.deinit();

        var ast = try parser.parse();
        defer ast.deinit();

        // ast.root is now a non-null pointer, so this check is unnecessary
        _ = ast.root;
    }
}

test "JSON streaming parser - objects" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const input = "{\"name\": \"test\", \"value\": 42}";

    var parser = try JsonParser.init(allocator, input, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    // ast.root is now a non-null pointer, so this check is unnecessary
    _ = ast.root;
    const json_ast = @import("../ast/mod.zig");
    const NodeKind = json_ast.NodeKind;
    try testing.expectEqual(NodeKind.object, @as(NodeKind, ast.root.*));
}

test "JSON streaming parser - arrays" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const input = "[1, 2, 3, \"test\", true, null]";

    var parser = try JsonParser.init(allocator, input, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    // ast.root is now a non-null pointer, so this check is unnecessary
    _ = ast.root;
    const json_ast = @import("../ast/mod.zig");
    const NodeKind = json_ast.NodeKind;
    try testing.expectEqual(NodeKind.array, @as(NodeKind, ast.root.*));
}

// Include value parsing tests
test {
    _ = values;
}
