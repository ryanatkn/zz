/// AST Node - Temporary stub for new architecture
///
/// This is a minimal AST definition for the progressive parser.
/// Will be expanded as needed.

const std = @import("std");

/// Simple AST structure
pub const AST = struct {
    root: *Node,
    source: []const u8,
    allocator: std.mem.Allocator,
    
    pub fn deinit(self: *AST) void {
        self.root.deinit(self.allocator);
        self.allocator.destroy(self.root);
    }
};

/// AST Node
pub const Node = struct {
    kind: NodeKind,
    span: Span,
    children: std.ArrayList(*Node),
    data: NodeData,
    
    const Span = @import("../span/span.zig").Span;
    
    pub fn init(allocator: std.mem.Allocator, kind: NodeKind, span: Span) !*Node {
        const node = try allocator.create(Node);
        node.* = .{
            .kind = kind,
            .span = span,
            .children = std.ArrayList(*Node).init(allocator),
            .data = .{ .none = {} },
        };
        return node;
    }
    
    pub fn deinit(self: *Node, allocator: std.mem.Allocator) void {
        for (self.children.items) |child| {
            child.deinit(allocator);
            allocator.destroy(child);
        }
        self.children.deinit();
    }
    
    pub fn addChild(self: *Node, child: *Node) !void {
        try self.children.append(child);
    }
};

/// Node types
pub const NodeKind = enum {
    // Literals
    identifier,
    string_literal,
    number_literal,
    boolean_literal,
    null_literal,
    
    // Expressions
    binary_expression,
    unary_expression,
    call_expression,
    member_expression,
    
    // Statements
    block_statement,
    if_statement,
    while_statement,
    for_statement,
    return_statement,
    
    // Declarations
    variable_declaration,
    function_declaration,
    class_declaration,
    
    // Structures
    object,
    array,
    property,
    
    // Other
    program,
    comment,
    error, // TODO reserved word
};

/// Additional node data
pub const NodeData = union {
    none: void,
    string: []const u8,
    number: f64,
    boolean: bool,
    identifier: []const u8,
};