/// AST Utilities Tests
///
/// Tests for generic AST utilities. Since these work with any AST type,
/// tests use a minimal test AST type to verify the functionality.
const std = @import("std");
const testing = std.testing;

// Test the generic utilities exist and compile
test {
    _ = @import("builder.zig");
    _ = @import("walker.zig");
}

// Example AST types for testing the generic utilities
const Span = struct { start: u32, end: u32 };

const TestNodeKind = enum { string, object, array };

const TestNode = union(TestNodeKind) {
    string: struct { span: Span, value: []const u8 },
    object: struct { span: Span, properties: []TestNode },
    array: struct { span: Span, elements: []TestNode },

    pub fn children(self: TestNode) []TestNode {
        return switch (self) {
            .object => |n| n.properties,
            .array => |n| n.elements,
            .string => &.{},
        };
    }

    pub fn span(self: TestNode) Span {
        return switch (self) {
            inline else => |n| n.span,
        };
    }
};

const TestAST = struct {
    root: *TestNode,
    arena: *std.heap.ArenaAllocator,
    source: []const u8,
};

const Walker = @import("walker.zig").Walker;
const ArenaBuilder = @import("builder.zig").ArenaBuilder;

test "generic walker compiles with test AST" {
    // Test the walker compiles with our TestNode type
    const TestWalker = Walker(TestNode);

    // Verify the types exist
    _ = TestWalker.Order.pre_order;
    _ = TestWalker.WalkResult.continue_walk;
}

test "generic arena builder works with test AST" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test that the builder compiles
    var builder = try ArenaBuilder(TestAST).init(allocator, "test source");
    defer builder.deinit();

    const test_string = try builder.ownString("hello");
    try testing.expectEqualStrings("hello", test_string);
}
