const std = @import("std");

/// ZON AST visitor stub
/// TODO: Implement when ZON tree-sitter grammar becomes available
/// For now, ZON parsing uses text-based extraction in parser.zig

/// Placeholder visitor function for future AST support
pub fn visitor(context: anytype, node: anytype) !bool {
    _ = context;
    _ = node;
    @compileError("ZON AST visitor not yet implemented - tree-sitter grammar needed");
}

/// ZON node type checking functions (for future use)
pub fn isStructuralNode(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "struct") or
        std.mem.eql(u8, node_type, "field") or
        std.mem.eql(u8, node_type, "array") or
        std.mem.eql(u8, node_type, "document");
}

pub fn isFieldNode(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "field") or
        std.mem.eql(u8, node_type, "quoted_field");
}

pub fn isValueNode(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "string") or
        std.mem.eql(u8, node_type, "number") or
        std.mem.eql(u8, node_type, "boolean") or
        std.mem.eql(u8, node_type, "array") or
        std.mem.eql(u8, node_type, "struct");
}