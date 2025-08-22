/// ZON AST - Complete AST definition for ZON (Zig Object Notation)
///
/// Self-contained AST module with all ZON node types.
/// No dependencies on other language ASTs.
const std = @import("std");
const Span = @import("../../span/mod.zig").Span;

/// ZON node kinds
pub const NodeKind = enum(u8) {
    // ZON value types
    string,
    number,
    boolean,
    null,

    // ZON-specific types
    field_name, // .field_name
    identifier, // regular identifier

    // ZON containers
    object, // .{ ... }
    array, // .[ ... ] or .{}

    // ZON structural
    field, // .field = value

    // Special
    root,
    err,
};

/// String node for ZON string values
pub const StringNode = struct {
    span: Span,
    value: []const u8, // Unescaped value
    quote_style: QuoteStyle = .double,

    pub const QuoteStyle = enum { single, double, raw };

    pub fn isValid(self: StringNode) bool {
        _ = self;
        return true; // All strings are valid once parsed
    }
};

/// Number node for ZON numeric values (supports all Zig number formats)
pub const NumberNode = struct {
    span: Span,
    value: NumberValue,
    raw: []const u8, // Original text representation

    pub const NumberValue = union(enum) {
        integer: i64,
        float: f64,
        hex: u64,
        binary: u64,
        octal: u64,
    };

    pub fn isValid(self: NumberNode) bool {
        _ = self;
        return true; // Validation done during parsing
    }
};

/// Boolean node for true/false
pub const BooleanNode = struct {
    span: Span,
    value: bool,
};

/// Field name node for .field_name
pub const FieldNameNode = struct {
    span: Span,
    name: []const u8,

    pub fn isValid(self: FieldNameNode) bool {
        // ZON field names must start with letter/underscore
        if (self.name.len == 0) return false;
        const first = self.name[0];
        return std.ascii.isAlphabetic(first) or first == '_';
    }
};

/// Identifier node for regular identifiers
pub const IdentifierNode = struct {
    span: Span,
    name: []const u8,
    is_quoted: bool = false, // @"quoted identifier"
};

/// Object node for ZON anonymous structs .{ ... }
pub const ObjectNode = struct {
    span: Span,
    fields: []Node, // Array of field nodes

    pub fn findField(self: ObjectNode, name: []const u8) ?*Node {
        for (self.fields) |*field| {
            if (field.* == .field) {
                const field_node = field.field;
                if (field_node.name.* == .field_name) {
                    if (std.mem.eql(u8, field_node.name.field_name.name, name)) {
                        return field_node.value;
                    }
                }
            }
        }
        return null;
    }
};

/// Array node for ZON arrays .[ ... ]
pub const ArrayNode = struct {
    span: Span,
    elements: []Node,
    is_anonymous_list: bool = true, // .{ } vs .[ ]

    pub fn len(self: ArrayNode) usize {
        return self.elements.len;
    }

    pub fn get(self: ArrayNode, index: usize) ?*Node {
        if (index >= self.elements.len) return null;
        return &self.elements[index];
    }
};

/// Field node for .field = value assignments
pub const FieldNode = struct {
    span: Span,
    name: *Node, // field_name or identifier
    value: *Node, // Any ZON value

    pub fn getFieldName(self: FieldNode) ?[]const u8 {
        return switch (self.name.*) {
            .field_name => |n| n.name,
            .identifier => |n| n.name,
            else => null,
        };
    }
};

/// Root node - top-level container
pub const RootNode = struct {
    span: Span,
    value: *Node, // The root ZON value (usually object)
};

/// Error node for parse errors
pub const ErrorNode = struct {
    span: Span,
    message: []const u8,
    partial: ?*Node, // Partial parse result if any
};

/// ZON Node - complete union of all ZON node types
pub const Node = union(NodeKind) {
    // ZON values
    string: StringNode,
    number: NumberNode,
    boolean: BooleanNode,
    null: Span, // null only needs position info

    // ZON-specific
    field_name: FieldNameNode,
    identifier: IdentifierNode,

    // ZON containers
    object: ObjectNode,
    array: ArrayNode,

    // ZON structural
    field: FieldNode,

    // Special
    root: RootNode,
    err: ErrorNode,

    /// Get node span
    pub fn span(self: Node) Span {
        return switch (self) {
            .string => |n| n.span,
            .number => |n| n.span,
            .boolean => |n| n.span,
            .null => |s| s,
            .field_name => |n| n.span,
            .identifier => |n| n.span,
            .object => |n| n.span,
            .array => |n| n.span,
            .field => |n| n.span,
            .root => |n| n.span,
            .err => |n| n.span,
        };
    }

    /// Get node kind
    pub fn kind(self: Node) NodeKind {
        return @as(NodeKind, self);
    }

    /// Check if node is a value (not container or structural)
    pub fn isValue(self: Node) bool {
        return switch (self) {
            .string, .number, .boolean, .null, .field_name, .identifier => true,
            else => false,
        };
    }

    /// Check if node is a container
    pub fn isContainer(self: Node) bool {
        return switch (self) {
            .object, .array => true,
            else => false,
        };
    }

    /// Get children for iteration
    pub fn children(self: Node) []Node {
        return switch (self) {
            .object => |n| n.fields,
            .array => |n| n.elements,
            else => &.{}, // Values have no children
        };
    }

    /// Convert to ZON string (for debugging)
    pub fn toZonString(self: Node, writer: anytype) !void {
        switch (self) {
            .string => |n| {
                try writer.writeByte('"');
                // TODO: Escape the string properly
                try writer.writeAll(n.value);
                try writer.writeByte('"');
            },
            .number => |n| try writer.writeAll(n.raw),
            .boolean => |n| try writer.writeAll(if (n.value) "true" else "false"),
            .null => try writer.writeAll("null"),
            .field_name => |n| {
                try writer.writeByte('.');
                try writer.writeAll(n.name);
            },
            .identifier => |n| {
                if (n.is_quoted) {
                    try writer.writeAll("@\"");
                    try writer.writeAll(n.name);
                    try writer.writeByte('"');
                } else {
                    try writer.writeAll(n.name);
                }
            },
            .object => |n| {
                try writer.writeAll(".{");
                for (n.fields, 0..) |field, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try field.toZonString(writer);
                }
                try writer.writeByte('}');
            },
            .array => |n| {
                if (n.is_anonymous_list) {
                    try writer.writeAll(".{");
                } else {
                    try writer.writeAll(".[");
                }
                for (n.elements, 0..) |elem, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try elem.toZonString(writer);
                }
                if (n.is_anonymous_list) {
                    try writer.writeByte('}');
                } else {
                    try writer.writeByte(']');
                }
            },
            .field => |n| {
                try n.name.toZonString(writer);
                try writer.writeAll(" = ");
                try n.value.toZonString(writer);
            },
            .root => |n| try n.value.toZonString(writer),
            .err => |n| {
                try writer.writeAll("/* ERROR: ");
                try writer.writeAll(n.message);
                try writer.writeAll(" */");
                if (n.partial) |partial| {
                    try partial.toZonString(writer);
                }
            },
        }
    }
};

/// ZON AST container
pub const AST = struct {
    allocator: std.mem.Allocator,
    root: ?*Node,
    owned_texts: std.ArrayList([]const u8), // For cleanup

    pub fn init(allocator: std.mem.Allocator) AST {
        return .{
            .allocator = allocator,
            .root = null,
            .owned_texts = std.ArrayList([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *AST) void {
        if (self.root) |root| {
            self.destroyNode(root);
            self.allocator.destroy(root);
        }
        // Free owned texts
        for (self.owned_texts.items) |text| {
            self.allocator.free(text);
        }
        self.owned_texts.deinit();
    }

    pub fn createNode(self: *AST, node: Node) !*Node {
        const ptr = try self.allocator.create(Node);
        ptr.* = node;
        return ptr;
    }

    pub fn destroyNode(self: *AST, node: *Node) void {
        // Recursively destroy children
        switch (node.*) {
            .object => |n| {
                for (n.fields) |*field| {
                    self.destroyNode(field);
                }
                self.allocator.free(n.fields);
            },
            .array => |n| {
                for (n.elements) |*elem| {
                    self.destroyNode(elem);
                }
                self.allocator.free(n.elements);
            },
            .field => |n| {
                self.destroyNode(n.name);
                self.destroyNode(n.value);
            },
            .root => |n| {
                self.destroyNode(n.value);
            },
            .err => |n| {
                if (n.partial) |partial| {
                    self.destroyNode(partial);
                }
            },
            else => {}, // Leaf nodes need no cleanup
        }
        self.allocator.destroy(node);
    }

    /// Pretty print for debugging
    pub fn print(self: AST, writer: anytype) !void {
        if (self.root) |root| {
            try root.toZonString(writer);
        } else {
            try writer.writeAll("/* empty AST */");
        }
    }
};
