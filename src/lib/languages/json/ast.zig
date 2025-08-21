/// JSON AST - Complete AST definition for JSON
///
/// Self-contained AST module with all JSON node types.
/// No dependencies on other language ASTs.
const std = @import("std");
const Span = @import("../../span/span.zig").Span;

/// JSON node kinds
pub const NodeKind = enum(u8) {
    // JSON value types
    string,
    number,
    boolean,
    null,
    
    // JSON containers
    object,
    array,
    
    // JSON structural
    property,
    
    // Special
    root,
    err,
};

/// String node for JSON string values
pub const StringNode = struct {
    span: Span,
    value: []const u8, // Unescaped value
    
    // JSON strings only use double quotes
    pub fn isValid(self: StringNode) bool {
        _ = self;
        return true; // All strings are valid once parsed
    }
};

/// Number node for JSON numeric values
pub const NumberNode = struct {
    span: Span,
    value: f64, // Parsed numeric value
    raw: []const u8, // Original text representation
    
    // JSON number validation (no leading zeros, etc.)
    pub fn isValid(self: NumberNode) bool {
        // RFC 8259 validation done during parsing
        _ = self;
        return true;
    }
};

/// Boolean node for true/false
pub const BooleanNode = struct {
    span: Span,
    value: bool,
};

/// Object node for JSON objects
pub const ObjectNode = struct {
    span: Span,
    properties: []Node, // Array of property nodes
    
    pub fn findProperty(self: ObjectNode, key: []const u8) ?*Node {
        for (self.properties) |*prop| {
            if (prop.* == .property) {
                const prop_node = prop.property;
                if (prop_node.key.* == .string) {
                    if (std.mem.eql(u8, prop_node.key.string.value, key)) {
                        return prop_node.value;
                    }
                }
            }
        }
        return null;
    }
};

/// Array node for JSON arrays
pub const ArrayNode = struct {
    span: Span,
    elements: []Node,
    
    pub fn len(self: ArrayNode) usize {
        return self.elements.len;
    }
    
    pub fn get(self: ArrayNode, index: usize) ?*Node {
        if (index >= self.elements.len) return null;
        return &self.elements[index];
    }
};

/// Property node for key-value pairs in objects
pub const PropertyNode = struct {
    span: Span,
    key: *Node, // Must be a string in valid JSON
    value: *Node, // Any JSON value
    
    pub fn getKeyString(self: PropertyNode) ?[]const u8 {
        if (self.key.* == .string) {
            return self.key.string.value;
        }
        return null;
    }
};

/// Root node - top-level container
pub const RootNode = struct {
    span: Span,
    value: *Node, // The root JSON value (object, array, or primitive)
};

/// Error node for parse errors
pub const ErrorNode = struct {
    span: Span,
    message: []const u8,
    partial: ?*Node, // Partial parse result if any
};

/// JSON Node - complete union of all JSON node types
pub const Node = union(NodeKind) {
    // JSON values
    string: StringNode,
    number: NumberNode,
    boolean: BooleanNode,
    null: Span, // null only needs position info
    
    // JSON containers
    object: ObjectNode,
    array: ArrayNode,
    
    // JSON structural
    property: PropertyNode,
    
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
            .object => |n| n.span,
            .array => |n| n.span,
            .property => |n| n.span,
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
            .string, .number, .boolean, .null => true,
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
            .object => |n| n.properties,
            .array => |n| n.elements,
            else => &.{}, // Values have no children
        };
    }
    
    /// Convert to JSON string (for debugging)
    pub fn toJsonString(self: Node, writer: anytype) !void {
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
            .object => |n| {
                try writer.writeByte('{');
                for (n.properties, 0..) |prop, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try prop.toJsonString(writer);
                }
                try writer.writeByte('}');
            },
            .array => |n| {
                try writer.writeByte('[');
                for (n.elements, 0..) |elem, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try elem.toJsonString(writer);
                }
                try writer.writeByte(']');
            },
            .property => |n| {
                try n.key.toJsonString(writer);
                try writer.writeAll(": ");
                try n.value.toJsonString(writer);
            },
            .root => |n| try n.value.toJsonString(writer),
            .err => |n| try writer.print("/* ERROR: {} */", .{n.message}),
        }
    }
};

/// JSON AST structure
pub const AST = struct {
    root: *Node,
    arena: *std.heap.ArenaAllocator,
    source: []const u8,
    nodes: []Node, // All nodes for iteration
    
    /// Single deinit frees everything
    pub fn deinit(self: *AST) void {
        self.arena.deinit();
        self.arena.child_allocator.destroy(self.arena);
    }
    
    /// Get source text for a span
    pub fn getText(self: AST, node_span: Span) []const u8 {
        const start = @min(node_span.start, self.source.len);
        const end = @min(node_span.end, self.source.len);
        return self.source[start..end];
    }
    
    /// Get root value (unwraps root node if present)
    pub fn getRootValue(self: AST) *Node {
        if (self.root.* == .root) {
            return self.root.root.value;
        }
        return self.root;
    }
    
    /// Validate JSON structure
    pub fn validate(self: AST) !void {
        try self.validateNode(self.root);
    }
    
    fn validateNode(self: AST, node: *Node) !void {
        switch (node.*) {
            .property => |prop| {
                // JSON keys must be strings
                if (prop.key.* != .string) {
                    return error.InvalidPropertyKey;
                }
                try self.validateNode(prop.value);
            },
            .object => |obj| {
                // Check for duplicate keys
                var seen = std.StringHashMap(void).init(self.arena.allocator());
                defer seen.deinit();
                
                for (obj.properties) |*prop| {
                    if (prop.* == .property) {
                        if (prop.property.key.* == .string) {
                            const key = prop.property.key.string.value;
                            if (seen.contains(key)) {
                                return error.DuplicateObjectKey;
                            }
                            try seen.put(key, {});
                        }
                    }
                    try self.validateNode(prop);
                }
            },
            .array => |arr| {
                for (arr.elements) |*elem| {
                    try self.validateNode(elem);
                }
            },
            .root => |r| try self.validateNode(r.value),
            else => {}, // Leaf nodes are always valid
        }
    }
};