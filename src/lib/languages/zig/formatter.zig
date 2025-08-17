const std = @import("std");
const ts = @import("tree-sitter");
const FormatterOptions = @import("../../parsing/formatter.zig").FormatterOptions;
const LineBuilder = @import("../../parsing/formatter.zig").LineBuilder;

// Import all Zig-specific formatter modules
const ZigNodeDispatcher = @import("node_dispatcher.zig").ZigNodeDispatcher;


/// Format Zig using AST-based approach - main entry point
pub fn formatAst(allocator: std.mem.Allocator, node: ts.Node, source: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
    _ = allocator;
    
    // Delegate all formatting to the node dispatcher
    try ZigNodeDispatcher.formatNode(node, source, builder, 0, options);
}

/// Check if node type represents a Zig declaration
pub fn isZigDeclaration(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "VarDecl") or
           std.mem.eql(u8, node_type, "Decl") or
           std.mem.eql(u8, node_type, "TestDecl");
}

/// Check if node type represents a Zig test
pub fn isZigTest(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "TestDecl");
}