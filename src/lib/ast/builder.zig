const std = @import("std");
const Node = @import("node.zig").Node;
const NodeType = @import("node.zig").NodeType;
const AST = @import("mod.zig").AST;
const ASTFactory = @import("factory.zig").ASTFactory;

/// Fluent DSL for building ASTs programmatically
/// Provides a clean, readable API for constructing complex AST structures
pub const ASTBuilder = struct {
    factory: ASTFactory,
    current_pos: usize,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .factory = ASTFactory.init(allocator),
            .current_pos = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        self.factory.deinit();
    }

    /// Start building an object
    pub fn object(self: *Self) ObjectBuilder {
        return ObjectBuilder.init(self);
    }

    /// Start building an array
    pub fn array(self: *Self) ArrayBuilder {
        return ArrayBuilder.init(self);
    }

    /// Create a string literal
    pub fn string(self: *Self, value: []const u8) !Node {
        const node = try self.factory.createString(value, self.current_pos, self.current_pos + value.len + 2);
        self.current_pos = node.end_position;
        return node;
    }

    /// Create a number literal
    pub fn number(self: *Self, value: anytype) !Node {
        const node = try self.factory.createNumber(value, self.current_pos, self.current_pos + 8);
        self.current_pos = node.end_position;
        return node;
    }

    /// Create a boolean literal
    pub fn boolean(self: *Self, value: bool) !Node {
        const length: usize = if (value) 4 else 5;
        const node = try self.factory.createBoolean(value, self.current_pos, self.current_pos + length);
        self.current_pos = node.end_position;
        return node;
    }

    /// Create a null literal
    pub fn @"null"(self: *Self) !Node {
        const node = try self.factory.createNull(self.current_pos, self.current_pos + 4);
        self.current_pos = node.end_position;
        return node;
    }

    /// Create an identifier
    pub fn identifier(self: *Self, name: []const u8) !Node {
        const node = try self.factory.createIdentifier(name, self.current_pos, self.current_pos + name.len);
        self.current_pos = node.end_position;
        return node;
    }

    /// Build the final AST
    pub fn buildAST(self: *Self, root: Node) !AST {
        const source = try std.fmt.allocPrint(self.factory.allocator, "/* Generated AST */", .{});
        return try self.factory.createAST(root, source);
    }

    /// Reset position counter
    pub fn resetPosition(self: *Self) void {
        self.current_pos = 0;
    }

    /// Set current position manually
    pub fn setPosition(self: *Self, pos: usize) void {
        self.current_pos = pos;
    }
};

/// Builder for object nodes
pub const ObjectBuilder = struct {
    parent: *ASTBuilder,
    fields: std.ArrayList(Node),
    start_pos: usize,

    const Self = @This();

    fn init(parent: *ASTBuilder) Self {
        const start_pos = parent.current_pos;
        parent.current_pos += 1; // Account for opening brace

        return .{
            .parent = parent,
            .fields = std.ArrayList(Node).init(parent.factory.allocator),
            .start_pos = start_pos,
        };
    }

    /// Add a string field
    pub fn field(self: *Self, name: []const u8, value_builder: anytype) !*Self {
        const value_node = switch (@TypeOf(value_builder)) {
            Node => value_builder,
            else => @compileError("Expected Node or builder that returns Node"),
        };

        const field_node = try self.parent.factory.createFieldAssignment(
            name,
            value_node,
            self.parent.current_pos,
            value_node.end_position,
        );

        try self.fields.append(field_node);
        self.parent.current_pos = field_node.end_position + 2; // Account for comma and space

        return self;
    }

    /// Add a string field with string value
    pub fn stringField(self: *Self, name: []const u8, value: []const u8) !*Self {
        const value_node = try self.parent.string(value);
        return try self.field(name, value_node);
    }

    /// Add a number field
    pub fn numberField(self: *Self, name: []const u8, value: anytype) !*Self {
        const value_node = try self.parent.number(value);
        return try self.field(name, value_node);
    }

    /// Add a boolean field
    pub fn booleanField(self: *Self, name: []const u8, value: bool) !*Self {
        const value_node = try self.parent.boolean(value);
        return try self.field(name, value_node);
    }

    /// Add a null field
    pub fn nullField(self: *Self, name: []const u8) !*Self {
        const value_node = try self.parent.null();
        return try self.field(name, value_node);
    }

    /// Add an object field
    pub fn objectField(self: *Self, name: []const u8, builder_fn: *const fn (*ObjectBuilder) anyerror!*ObjectBuilder) !*Self {
        var obj_builder = self.parent.object();
        _ = try builder_fn(&obj_builder);
        const obj_node = try obj_builder.build();
        return try self.field(name, obj_node);
    }

    /// Add an array field
    pub fn arrayField(self: *Self, name: []const u8, builder_fn: *const fn (*ArrayBuilder) anyerror!*ArrayBuilder) !*Self {
        var arr_builder = self.parent.array();
        _ = try builder_fn(&arr_builder);
        const arr_node = try arr_builder.build();
        return try self.field(name, arr_node);
    }

    /// Build the object node
    pub fn build(self: *Self) !Node {
        const end_pos = self.parent.current_pos + 1; // Account for closing brace
        self.parent.current_pos = end_pos;

        const object_text = try std.fmt.allocPrint(self.parent.factory.allocator, "{{ /* {} fields */ }}", .{self.fields.items.len});

        const node = try self.parent.factory.createObject(
            object_text,
            self.start_pos,
            end_pos,
            self.fields.items,
        );

        self.fields.deinit();
        return node;
    }
};

/// Builder for array nodes
pub const ArrayBuilder = struct {
    parent: *ASTBuilder,
    items: std.ArrayList(Node),
    start_pos: usize,

    const Self = @This();

    fn init(parent: *ASTBuilder) Self {
        const start_pos = parent.current_pos;
        parent.current_pos += 1; // Account for opening bracket

        return .{
            .parent = parent,
            .items = std.ArrayList(Node).init(parent.factory.allocator),
            .start_pos = start_pos,
        };
    }

    /// Add an item to the array
    pub fn item(self: *Self, value_builder: anytype) !*Self {
        const item_node = switch (@TypeOf(value_builder)) {
            Node => value_builder,
            else => @compileError("Expected Node or builder that returns Node"),
        };

        try self.items.append(item_node);
        self.parent.current_pos = item_node.end_position + 2; // Account for comma and space

        return self;
    }

    /// Add a string item
    pub fn stringItem(self: *Self, value: []const u8) !*Self {
        const item_node = try self.parent.string(value);
        return try self.item(item_node);
    }

    /// Add a number item
    pub fn numberItem(self: *Self, value: anytype) !*Self {
        const item_node = try self.parent.number(value);
        return try self.item(item_node);
    }

    /// Add a boolean item
    pub fn booleanItem(self: *Self, value: bool) !*Self {
        const item_node = try self.parent.boolean(value);
        return try self.item(item_node);
    }

    /// Add a null item
    pub fn nullItem(self: *Self) !*Self {
        const item_node = try self.parent.null();
        return try self.item(item_node);
    }

    /// Add an object item
    pub fn objectItem(self: *Self, builder_fn: *const fn (*ObjectBuilder) anyerror!*ObjectBuilder) !*Self {
        var obj_builder = self.parent.object();
        _ = try builder_fn(&obj_builder);
        const obj_node = try obj_builder.build();
        return try self.item(obj_node);
    }

    /// Add an array item
    pub fn arrayItem(self: *Self, builder_fn: *const fn (*ArrayBuilder) anyerror!*ArrayBuilder) !*Self {
        var arr_builder = self.parent.array();
        _ = try builder_fn(&arr_builder);
        const arr_node = try arr_builder.build();
        return try self.item(arr_node);
    }

    /// Build the array node
    pub fn build(self: *Self) !Node {
        const end_pos = self.parent.current_pos + 1; // Account for closing bracket
        self.parent.current_pos = end_pos;

        const array_text = try std.fmt.allocPrint(self.parent.factory.allocator, "[ /* {} items */ ]", .{self.items.items.len});

        const node = try self.parent.factory.createArray(
            array_text,
            self.start_pos,
            end_pos,
            self.items.items,
        );

        self.items.deinit();
        return node;
    }
};

// ============================================================================
// Convenience Functions
// ============================================================================

/// Quick builder for simple objects
pub fn quickObject(allocator: std.mem.Allocator, fields: []const QuickField) !AST {
    var builder = ASTBuilder.init(allocator);
    errdefer builder.deinit();

    var obj_builder = builder.object();
    for (fields) |field| {
        switch (field.value) {
            .string => |s| _ = try obj_builder.stringField(field.name, s),
            .number => |n| _ = try obj_builder.numberField(field.name, n),
            .boolean => |b| _ = try obj_builder.booleanField(field.name, b),
            .null_value => _ = try obj_builder.nullField(field.name),
        }
    }

    const root = try obj_builder.build();
    return try builder.buildAST(root);
}

/// Quick builder for simple arrays
pub fn quickArray(allocator: std.mem.Allocator, items: []const QuickValue) !AST {
    var builder = ASTBuilder.init(allocator);
    errdefer builder.deinit();

    var arr_builder = builder.array();
    for (items) |item| {
        switch (item) {
            .string => |s| _ = try arr_builder.stringItem(s),
            .number => |n| _ = try arr_builder.numberItem(n),
            .boolean => |b| _ = try arr_builder.booleanItem(b),
            .null_value => _ = try arr_builder.nullItem(),
        }
    }

    const root = try arr_builder.build();
    return try builder.buildAST(root);
}

pub const QuickField = struct {
    name: []const u8,
    value: QuickValue,
};

pub const QuickValue = union(enum) {
    string: []const u8,
    number: i64,
    boolean: bool,
    null_value,
};

// ============================================================================
// Example Usage and Tests
// ============================================================================

const testing = std.testing;

test "fluent object building" {
    const CommonRules = @import("rules.zig").CommonRules;
    var builder = ASTBuilder.init(testing.allocator);
    defer builder.deinit();

    var obj = builder.object();
    _ = try obj.stringField("name", "test_package");
    _ = try obj.numberField("version_major", 1);
    _ = try obj.booleanField("is_public", true);
    _ = try obj.nullField("description");
    const root = try obj.build();

    try testing.expectEqual(@intFromEnum(CommonRules.object), root.rule_id);
    try testing.expectEqual(@as(usize, 4), root.children.len);
}

test "fluent array building" {
    const CommonRules = @import("rules.zig").CommonRules;
    var builder = ASTBuilder.init(testing.allocator);
    defer builder.deinit();

    var arr = builder.array();
    _ = try arr.stringItem("first");
    _ = try arr.numberItem(42);
    _ = try arr.booleanItem(true);
    _ = try arr.nullItem();
    const root = try arr.build();

    try testing.expectEqual(@intFromEnum(CommonRules.array), root.rule_id);
    try testing.expectEqual(@as(usize, 4), root.children.len);
}

test "nested object and array" {
    var builder = ASTBuilder.init(testing.allocator);
    defer builder.deinit();

    var obj = builder.object();
    _ = try obj.stringField("name", "complex_example");
    _ = try obj.objectField("metadata", struct {
        fn build_metadata(obj_inner: *ObjectBuilder) !*ObjectBuilder {
            _ = try obj_inner.stringField("author", "test");
            _ = try obj_inner.stringField("license", "MIT");
            return obj_inner;
        }
    }.build_metadata);
    _ = try obj.arrayField("dependencies", struct {
        fn build_deps(arr_inner: *ArrayBuilder) !*ArrayBuilder {
            _ = try arr_inner.stringItem("dep1");
            _ = try arr_inner.stringItem("dep2");
            return arr_inner;
        }
    }.build_deps);
    const root = try obj.build();

    const CommonRules = @import("rules.zig").CommonRules;
    try testing.expectEqual(@intFromEnum(CommonRules.object), root.rule_id);
    try testing.expectEqual(@as(usize, 3), root.children.len);
}

test "quick object builder" {
    const fields = [_]QuickField{
        .{ .name = "name", .value = .{ .string = "test" } },
        .{ .name = "count", .value = .{ .number = 42 } },
        .{ .name = "enabled", .value = .{ .boolean = true } },
        .{ .name = "optional", .value = .null_value },
    };

    var ast = try quickObject(testing.allocator, &fields);
    defer ast.deinit();

    const CommonRules = @import("rules.zig").CommonRules;
    try testing.expectEqual(@intFromEnum(CommonRules.object), ast.root.rule_id);
    try testing.expectEqual(@as(usize, 4), ast.root.children.len);
}

test "quick array builder" {
    const items = [_]QuickValue{
        .{ .string = "hello" },
        .{ .number = 123 },
        .{ .boolean = false },
        .null_value,
    };

    var ast = try quickArray(testing.allocator, &items);
    defer ast.deinit();

    const CommonRules = @import("rules.zig").CommonRules;
    try testing.expectEqual(@intFromEnum(CommonRules.array), ast.root.rule_id);
    try testing.expectEqual(@as(usize, 4), ast.root.children.len);
}
