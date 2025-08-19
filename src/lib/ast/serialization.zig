const std = @import("std");
const Node = @import("node.zig").Node;
const NodeType = @import("node.zig").NodeType;
const AST = @import("mod.zig").AST;
const CommonRules = @import("rules.zig").CommonRules;

/// High-performance AST serialization using ZON format
/// Native Zig serialization for maximum performance and compatibility
/// Serialization options
pub const SerializeOptions = struct {
    /// Pretty-print with indentation
    pretty: bool = true,

    /// Include position information
    include_positions: bool = true,

    /// Include text content
    include_text: bool = true,

    /// Include node attributes
    include_attributes: bool = true,

    /// Maximum depth to serialize (0 = unlimited)
    max_depth: usize = 0,

    /// Compress identical subtrees
    compress_duplicates: bool = false,
};

/// AST Serializer for ZON format
pub const ASTSerializer = struct {
    allocator: std.mem.Allocator,
    options: SerializeOptions,

    pub fn init(allocator: std.mem.Allocator, options: SerializeOptions) ASTSerializer {
        return .{
            .allocator = allocator,
            .options = options,
        };
    }

    /// Serialize AST to ZON string
    pub fn serialize(self: ASTSerializer, ast: *const AST) ![]const u8 {
        var buffer = std.ArrayList(u8).init(self.allocator);
        defer buffer.deinit();

        try self.writeAST(&buffer.writer(), ast);
        return buffer.toOwnedSlice();
    }

    /// Serialize single node to ZON
    pub fn serializeNode(self: ASTSerializer, node: *const Node) ![]const u8 {
        var buffer = std.ArrayList(u8).init(self.allocator);
        defer buffer.deinit();

        try self.writeNode(&buffer.writer(), node, 0);
        return buffer.toOwnedSlice();
    }

    /// Write AST structure to writer
    fn writeAST(self: ASTSerializer, writer: anytype, ast: *const AST) !void {
        if (self.options.pretty) {
            try writer.writeAll(".{\n");
            try self.writeIndent(writer, 1);
            try writer.writeAll(".source = ");
            try self.writeEscapedString(writer, ast.source);
            try writer.writeAll(",\n");
            try self.writeIndent(writer, 1);
            try writer.writeAll(".root = ");
            try self.writeNode(writer, &ast.root, 1);
            try writer.writeAll(",\n");
            try writer.writeAll("}");
        } else {
            try writer.writeAll(".{.source=");
            try self.writeEscapedString(writer, ast.source);
            try writer.writeAll(",.root=");
            try self.writeNode(writer, &ast.root, 0);
            try writer.writeAll("}");
        }
    }

    /// Write single node to writer
    fn writeNode(self: ASTSerializer, writer: anytype, node: *const Node, depth: usize) !void {
        if (self.options.max_depth > 0 and depth >= self.options.max_depth) {
            try writer.writeAll("null");
            return;
        }

        if (self.options.pretty) {
            try writer.writeAll(".{\n");
            try self.writeNodeFields(writer, node, depth + 1);
            try self.writeIndent(writer, depth);
            try writer.writeAll("}");
        } else {
            try writer.writeAll(".{");
            try self.writeNodeFieldsCompact(writer, node);
            try writer.writeAll("}");
        }
    }

    fn writeNodeFields(self: ASTSerializer, writer: anytype, node: *const Node, depth: usize) !void {
        // Rule ID
        try self.writeIndent(writer, depth);
        try writer.print(".rule_id = {},\n", .{node.rule_id});

        // Node type
        try self.writeIndent(writer, depth);
        try writer.writeAll(".node_type = .");
        try writer.writeAll(@tagName(node.node_type));
        try writer.writeAll(",\n");

        // Text content
        if (self.options.include_text) {
            try self.writeIndent(writer, depth);
            try writer.writeAll(".text = ");
            try self.writeEscapedString(writer, node.text);
            try writer.writeAll(",\n");
        }

        // Positions
        if (self.options.include_positions) {
            try self.writeIndent(writer, depth);
            try writer.print(".start_position = {},\n", .{node.start_position});
            try self.writeIndent(writer, depth);
            try writer.print(".end_position = {},\n", .{node.end_position});
        }

        // Children
        try self.writeIndent(writer, depth);
        try writer.writeAll(".children = .{\n");
        for (node.children, 0..) |child, i| {
            try self.writeIndent(writer, depth + 1);
            try self.writeNode(writer, &child, depth + 1);
            if (i < node.children.len - 1) {
                try writer.writeAll(",");
            }
            try writer.writeAll("\n");
        }
        try self.writeIndent(writer, depth);
        try writer.writeAll("},\n");

        // Attributes (if present and requested)
        if (self.options.include_attributes and node.attributes != null) {
            try self.writeIndent(writer, depth);
            try writer.writeAll(".attributes = ");
            // TODO: Serialize attributes when implemented
            try writer.writeAll("null,\n");
        }
    }

    fn writeNodeFieldsCompact(self: ASTSerializer, writer: anytype, node: *const Node) !void {
        try writer.print(".rule_id={}", .{node.rule_id});
        try writer.writeAll(",.node_type=.");
        try writer.writeAll(@tagName(node.node_type));

        if (self.options.include_text) {
            try writer.writeAll(",.text=");
            try self.writeEscapedString(writer, node.text);
        }

        if (self.options.include_positions) {
            try writer.print(",.start_position={},.end_position={}", .{ node.start_position, node.end_position });
        }

        try writer.writeAll(",.children=.{");
        for (node.children, 0..) |child, i| {
            try self.writeNode(writer, &child, 0);
            if (i < node.children.len - 1) try writer.writeAll(",");
        }
        try writer.writeAll("}");
    }

    fn writeIndent(self: ASTSerializer, writer: anytype, depth: usize) !void {
        if (!self.options.pretty) return;
        for (0..depth * 4) |_| {
            try writer.writeAll(" ");
        }
    }

    fn writeEscapedString(self: ASTSerializer, writer: anytype, string: []const u8) !void {
        _ = self;
        try writer.writeAll("\"");
        for (string) |char| {
            switch (char) {
                '\n' => try writer.writeAll("\\n"),
                '\r' => try writer.writeAll("\\r"),
                '\t' => try writer.writeAll("\\t"),
                '\\' => try writer.writeAll("\\\\"),
                '"' => try writer.writeAll("\\\""),
                else => try writer.writeByte(char),
            }
        }
        try writer.writeAll("\"");
    }
};

/// AST Deserializer from ZON format
pub const ASTDeserializer = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ASTDeserializer {
        return .{ .allocator = allocator };
    }

    /// Deserialize ZON string to AST
    pub fn deserialize(self: ASTDeserializer, zon_content: []const u8) !AST {
        // Use our ZON parser to parse the serialized AST
        const zon_mod = @import("../languages/zon/mod.zig");
        const parsed_zon = try zon_mod.parseZonString(self.allocator, zon_content);
        defer parsed_zon.deinit();

        // Extract AST fields from parsed ZON
        const source = try self.extractField(&parsed_zon.root, "source");
        const root_node = try self.extractNodeField(&parsed_zon.root, "root");

        return AST{
            .root = root_node,
            .source = try self.allocator.dupe(u8, source),
            .owned_texts = std.ArrayList([]const u8).init(self.allocator),
        };
    }

    /// Extract string field from ZON node
    fn extractField(self: ASTDeserializer, node: *const Node, field_name: []const u8) ![]const u8 {
        _ = self;

        for (node.children) |child| {
            // TODO: Replace with rule_id comparison when ZonRules are available
            if (child.rule_id == 0) { // Placeholder - needs proper ZonRules.field_assignment
                // Check if this is the field we want
                if (child.children.len >= 3) {
                    const name_node = &child.children[0];
                    if (std.mem.indexOf(u8, name_node.text, field_name) != null) {
                        const value_node = &child.children[2];
                        // Remove quotes from string value
                        if (value_node.text.len >= 2 and
                            value_node.text[0] == '"' and
                            value_node.text[value_node.text.len - 1] == '"')
                        {
                            return value_node.text[1 .. value_node.text.len - 1];
                        }
                        return value_node.text;
                    }
                }
            }
        }
        return "";
    }

    /// Extract Node field from ZON
    fn extractNodeField(self: ASTDeserializer, node: *const Node, field_name: []const u8) !Node {
        _ = self;
        _ = node;
        _ = field_name;

        // TODO: Implement full node deserialization
        // For now, return a minimal node
        return Node{
            .rule_id = @intFromEnum(CommonRules.unknown),
            .node_type = .rule,
            .text = "",
            .start_position = 0,
            .end_position = 0,
            .children = &[_]Node{},
            .attributes = null,
            .parent = null,
        };
    }
};

// ============================================================================
// Convenience Functions
// ============================================================================

/// Quick AST serialization with default options
pub fn serializeAST(allocator: std.mem.Allocator, ast: *const AST) ![]const u8 {
    const serializer = ASTSerializer.init(allocator, .{});
    return serializer.serialize(ast);
}

/// Quick compact serialization
pub fn serializeASTCompact(allocator: std.mem.Allocator, ast: *const AST) ![]const u8 {
    const serializer = ASTSerializer.init(allocator, .{ .pretty = false });
    return serializer.serialize(ast);
}

/// Quick node serialization
pub fn serializeNode(allocator: std.mem.Allocator, node: *const Node) ![]const u8 {
    const serializer = ASTSerializer.init(allocator, .{});
    return serializer.serializeNode(node);
}

/// Quick deserialization
pub fn deserializeAST(allocator: std.mem.Allocator, zon_content: []const u8) !AST {
    const deserializer = ASTDeserializer.init(allocator);
    return deserializer.deserialize(zon_content);
}

/// Save AST to file
pub fn saveASTToFile(allocator: std.mem.Allocator, ast: *const AST, file_path: []const u8) !void {
    const serialized = try serializeAST(allocator, ast);
    defer allocator.free(serialized);

    try std.fs.cwd().writeFile(file_path, serialized);
}

/// Load AST from file
pub fn loadASTFromFile(allocator: std.mem.Allocator, file_path: []const u8) !AST {
    const content = try std.fs.cwd().readFileAlloc(allocator, file_path, 10 * 1024 * 1024);
    defer allocator.free(content);

    return deserializeAST(allocator, content);
}

// ============================================================================
// Binary Serialization (Future Enhancement)
// ============================================================================

/// Binary format header
const BINARY_MAGIC = [4]u8{ 'Z', 'A', 'S', 'T' }; // Zig AST
const BINARY_VERSION: u32 = 1;

/// Binary serialization for performance-critical applications
pub const BinarySerializer = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) BinarySerializer {
        return .{ .allocator = allocator };
    }

    /// Serialize to binary format (placeholder)
    pub fn serializeBinary(self: BinarySerializer, ast: *const AST) ![]const u8 {
        _ = self;
        _ = ast;
        // TODO: Implement binary serialization for maximum performance
        return &[_]u8{};
    }

    /// Deserialize from binary format (placeholder)
    pub fn deserializeBinary(self: BinarySerializer, data: []const u8) !AST {
        _ = data;
        // TODO: Implement binary deserialization
        return AST{
            .root = undefined,
            .source = "",
            .owned_texts = std.ArrayList([]const u8).init(self.allocator),
        };
    }
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;
const ASTTestHelpers = @import("test_helpers.zig").ASTTestHelpers;

test "AST serialization to ZON" {
    var ast = try ASTTestHelpers.createMinimalAST(testing.allocator, "test_node", "test content");
    defer ast.deinit();

    const serialized = try serializeAST(testing.allocator, &ast);
    defer testing.allocator.free(serialized);

    // Check that serialization contains expected content
    // Check that serialization contains rule_id
    try testing.expect(std.mem.indexOf(u8, serialized, "rule_id") != null);
    try testing.expect(std.mem.indexOf(u8, serialized, "test content") != null);
}

test "compact serialization" {
    var ast = try ASTTestHelpers.createMinimalAST(testing.allocator, "compact", "test");
    defer ast.deinit();

    const compact = try serializeASTCompact(testing.allocator, &ast);
    defer testing.allocator.free(compact);

    // Compact format should not contain newlines
    try testing.expect(std.mem.indexOf(u8, compact, "\n") == null);
}

test "node serialization" {
    var ast = try ASTTestHelpers.createMinimalAST(testing.allocator, "single_node", "content");
    defer ast.deinit();

    const serialized = try serializeNode(testing.allocator, &ast.root);
    defer testing.allocator.free(serialized);

    // Check that serialization contains rule_id
    try testing.expect(std.mem.indexOf(u8, serialized, "rule_id") != null);
}

test "serialization options" {
    var ast = try ASTTestHelpers.createMinimalAST(testing.allocator, "options_test", "content");
    defer ast.deinit();

    const serializer = ASTSerializer.init(testing.allocator, .{
        .include_positions = false,
        .include_text = false,
        .pretty = false,
    });

    const serialized = try serializer.serialize(&ast);
    defer testing.allocator.free(serialized);

    // Should not contain position or text information
    try testing.expect(std.mem.indexOf(u8, serialized, "start_position") == null);
    try testing.expect(std.mem.indexOf(u8, serialized, ".text") == null);
}
