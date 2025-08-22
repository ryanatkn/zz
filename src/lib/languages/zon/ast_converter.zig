/// ZON AST Converter - Simplified stub for migration
///
/// This module is temporarily stubbed during the progressive parser refactor.
/// It will be fully reimplemented to work with the new ZON AST structure.
const std = @import("std");
const zon_ast = @import("ast.zig");
const Node = zon_ast.Node;
const AST = zon_ast.AST;

pub const AstConverter = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) AstConverter {
        return .{ .allocator = allocator };
    }

    /// Convert an AST node to the specified type T - STUB
    pub fn toStruct(self: *AstConverter, comptime T: type, node: Node) !T {
        _ = self;
        _ = node;
        // Return default value for now
        return std.mem.zeroes(T);
    }
};

/// Parse ZON content to a specific type (compatibility function)
pub fn parseFromSlice(comptime T: type, allocator: std.mem.Allocator, content: []const u8) !T {
    _ = allocator;
    _ = content;
    // Return default value for now
    return std.mem.zeroes(T);
}

/// Free parsed ZON data (compatibility function)
pub fn free(allocator: std.mem.Allocator, parsed_data: anytype) void {
    _ = allocator;
    _ = parsed_data;
    // Nothing to free in stub
}
