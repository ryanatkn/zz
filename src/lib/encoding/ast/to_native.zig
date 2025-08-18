const std = @import("std");
const AST = @import("../../ast/mod.zig").AST;
const Node = @import("../../ast/mod.zig").Node;
const NodeType = @import("../../ast/mod.zig").NodeType;
const Fact = @import("../../parser/foundation/types/fact.zig").Fact;
const Span = @import("../../parser/foundation/types/span.zig").Span;

/// Convert AST node to native Zig type
/// This provides zero-allocation for primitives and efficient conversion for complex types
pub fn astToNative(comptime T: type, allocator: std.mem.Allocator, node: Node) !T {
    const type_info = @typeInfo(T);
    
    switch (type_info) {
        .Bool => return try parseBool(node),
        .Int => |int| return try parseInt(T, node, int.signedness == .signed),
        .Float => return try parseFloat(T, node),
        .Optional => |opt| {
            if (node.node_type == .null_literal) {
                return null;
            }
            return try astToNative(opt.child, allocator, node);
        },
        .Array => |arr| {
            if (node.node_type != .array) {
                return error.TypeMismatch;
            }
            var result: T = undefined;
            if (node.children.len != arr.len) {
                return error.ArraySizeMismatch;
            }
            for (node.children, 0..) |child, i| {
                result[i] = try astToNative(arr.child, allocator, child);
            }
            return result;
        },
        .Pointer => |ptr| {
            switch (ptr.size) {
                .Slice => {
                    if (ptr.child == u8) {
                        // String slice
                        return try parseString(allocator, node);
                    }
                    // Array slice
                    if (node.node_type != .array) {
                        return error.TypeMismatch;
                    }
                    var result = try allocator.alloc(ptr.child, node.children.len);
                    for (node.children, 0..) |child, i| {
                        result[i] = try astToNative(ptr.child, allocator, child);
                    }
                    return result;
                },
                else => return error.UnsupportedPointerType,
            }
        },
        .Struct => |struct_info| {
            if (node.node_type != .object and node.node_type != .struct_literal) {
                return error.TypeMismatch;
            }
            var result: T = undefined;
            
            inline for (struct_info.fields) |field| {
                const field_node = findFieldNode(node, field.name) orelse {
                    if (field.default_value) |default| {
                        @field(result, field.name) = @as(*const field.type, @ptrCast(@alignCast(default))).*;
                    } else {
                        return error.MissingField;
                    }
                    continue;
                };
                
                @field(result, field.name) = try astToNative(field.type, allocator, field_node);
            }
            return result;
        },
        .Union => |union_info| {
            if (union_info.tag_type) |_| {
                // Tagged union
                return try parseTaggedUnion(T, allocator, node);
            } else {
                return error.UntaggedUnionNotSupported;
            }
        },
        .Enum => return try parseEnum(T, node),
        else => return error.UnsupportedType,
    }
}

/// Convert AST node to std.json.Value
pub fn astNodeToValue(allocator: std.mem.Allocator, node: Node) !std.json.Value {
    switch (node.node_type) {
        .null_literal => return .null,
        .bool_literal, .boolean => {
            const val = try parseBool(node);
            return .{ .bool = val };
        },
        .number_literal, .number => {
            // Try integer first, then float
            if (std.mem.indexOfScalar(u8, node.text, '.')) |_| {
                const val = try parseFloat(f64, node);
                return .{ .float = val };
            } else {
                const val = try parseInt(i64, node, true);
                return .{ .integer = val };
            }
        },
        .string_literal, .string => {
            const str = try parseString(allocator, node);
            return .{ .string = str };
        },
        .array => {
            var arr = std.json.Array.init(allocator);
            for (node.children) |child| {
                const val = try astNodeToValue(allocator, child);
                try arr.append(val);
            }
            return .{ .array = arr };
        },
        .object, .struct_literal => {
            var obj = std.json.ObjectMap.init(allocator);
            for (node.children) |child| {
                if (child.node_type == .field_assignment or child.node_type == .property) {
                    const key = child.children[0].text;
                    const value = try astNodeToValue(allocator, child.children[1]);
                    try obj.put(key, value);
                }
            }
            return .{ .object = obj };
        },
        else => return error.UnsupportedNodeType,
    }
}

/// Convert facts to native type (more efficient than AST)
pub fn factsToNative(comptime T: type, allocator: std.mem.Allocator, facts: []const Fact) !T {
    // Build type from facts without constructing full AST
    // This is more efficient for streaming scenarios
    const type_info = @typeInfo(T);
    
    switch (type_info) {
        .Struct => {
            var result: T = undefined;
            
            // Find facts that represent struct fields
            for (facts) |fact| {
                switch (fact.predicate) {
                    .field_name => {
                        if (fact.object) |obj| {
                            const field_name = obj.string;
                            inline for (@typeInfo(T).Struct.fields) |field| {
                                if (std.mem.eql(u8, field.name, field_name)) {
                                    // Find corresponding value fact
                                    const value_fact = findValueFact(facts, fact.subject) orelse {
                                        if (field.default_value) |default| {
                                            @field(result, field.name) = @as(*const field.type, @ptrCast(@alignCast(default))).*;
                                        } else {
                                            return error.MissingField;
                                        }
                                        continue;
                                    };
                                    @field(result, field.name) = try factToValue(field.type, allocator, value_fact);
                                }
                            }
                        }
                    },
                    else => {},
                }
            }
            return result;
        },
        else => {
            // For simple types, find the root fact
            const root_fact = findRootFact(facts) orelse return error.NoRootFact;
            return try factToValue(T, allocator, root_fact);
        },
    }
}

// Helper functions

fn parseBool(node: Node) !bool {
    if (std.mem.eql(u8, node.text, "true")) return true;
    if (std.mem.eql(u8, node.text, "false")) return false;
    return error.InvalidBool;
}

fn parseInt(comptime T: type, node: Node, signed: bool) !T {
    _ = signed;
    return try std.fmt.parseInt(T, node.text, 0);
}

fn parseFloat(comptime T: type, node: Node) !T {
    return try std.fmt.parseFloat(T, node.text);
}

fn parseString(allocator: std.mem.Allocator, node: Node) ![]const u8 {
    // Remove quotes if present
    var text = node.text;
    if (text.len >= 2 and text[0] == '"' and text[text.len - 1] == '"') {
        text = text[1 .. text.len - 1];
    }
    // Unescape string
    return try unescapeString(allocator, text);
}

fn parseEnum(comptime T: type, node: Node) !T {
    const enum_info = @typeInfo(T).Enum;
    inline for (enum_info.fields) |field| {
        if (std.mem.eql(u8, field.name, node.text)) {
            return @enumFromInt(field.value);
        }
    }
    return error.InvalidEnumValue;
}

fn parseTaggedUnion(comptime T: type, allocator: std.mem.Allocator, node: Node) !T {
    const union_info = @typeInfo(T).Union;
    
    // Find the tag field
    const tag_node = findFieldNode(node, "tag") orelse return error.MissingUnionTag;
    const tag_name = tag_node.text;
    
    inline for (union_info.fields) |field| {
        if (std.mem.eql(u8, field.name, tag_name)) {
            const value_node = findFieldNode(node, "value") orelse node;
            const value = try astToNative(field.type, allocator, value_node);
            return @unionInit(T, field.name, value);
        }
    }
    return error.InvalidUnionTag;
}

fn findFieldNode(node: Node, field_name: []const u8) ?Node {
    for (node.children) |child| {
        if (child.node_type == .field_assignment or child.node_type == .property) {
            if (child.children.len >= 2 and std.mem.eql(u8, child.children[0].text, field_name)) {
                return child.children[1];
            }
        }
    }
    return null;
}

fn findValueFact(facts: []const Fact, span: Span) ?Fact {
    for (facts) |fact| {
        if (fact.subject.start == span.start and fact.subject.end == span.end) {
            switch (fact.predicate) {
                .literal_value, .field_value => return fact,
                else => {},
            }
        }
    }
    return null;
}

fn findRootFact(facts: []const Fact) ?Fact {
    // Find the fact with the largest span (likely the root)
    var root: ?Fact = null;
    var max_span: usize = 0;
    
    for (facts) |fact| {
        const span_size = fact.subject.end - fact.subject.start;
        if (span_size > max_span) {
            max_span = span_size;
            root = fact;
        }
    }
    return root;
}

fn factToValue(comptime T: type, allocator: std.mem.Allocator, fact: Fact) !T {
    _ = allocator;
    
    if (fact.object) |obj| {
        const type_info = @typeInfo(T);
        switch (type_info) {
            .Bool => return obj.boolean,
            .Int => return @intCast(obj.integer),
            .Float => return @floatCast(obj.float),
            else => return error.UnsupportedFactConversion,
        }
    }
    return error.NoFactValue;
}

fn unescapeString(allocator: std.mem.Allocator, text: []const u8) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();
    
    var i: usize = 0;
    while (i < text.len) {
        if (text[i] == '\\' and i + 1 < text.len) {
            switch (text[i + 1]) {
                'n' => try result.append('\n'),
                'r' => try result.append('\r'),
                't' => try result.append('\t'),
                '\\' => try result.append('\\'),
                '"' => try result.append('"'),
                else => {
                    try result.append(text[i]);
                    try result.append(text[i + 1]);
                },
            }
            i += 2;
        } else {
            try result.append(text[i]);
            i += 1;
        }
    }
    
    return try result.toOwnedSlice();
}

// Tests
const testing = std.testing;
const builder = @import("../../ast/builder.zig");

test "astToNative - primitive types" {
    const allocator = testing.allocator;
    
    // Boolean
    {
        const node = Node{
            .rule_name = "bool",
            .node_type = .bool_literal,
            .text = "true",
            .start_position = 0,
            .end_position = 4,
            .children = &.{},
            .attributes = null,
            .parent = null,
        };
        const val = try astToNative(bool, allocator, node);
        try testing.expect(val == true);
    }
    
    // Integer
    {
        const node = Node{
            .rule_name = "number",
            .node_type = .number_literal,
            .text = "42",
            .start_position = 0,
            .end_position = 2,
            .children = &.{},
            .attributes = null,
            .parent = null,
        };
        const val = try astToNative(i32, allocator, node);
        try testing.expect(val == 42);
    }
    
    // Float
    {
        const node = Node{
            .rule_name = "number",
            .node_type = .number_literal,
            .text = "3.14",
            .start_position = 0,
            .end_position = 4,
            .children = &.{},
            .attributes = null,
            .parent = null,
        };
        const val = try astToNative(f64, allocator, node);
        try testing.expectApproxEqAbs(val, 3.14, 0.001);
    }
}

test "astToNative - struct conversion" {
    const TestStruct = struct {
        name: []const u8,
        value: i32,
        enabled: bool = false,
    };
    
    const allocator = testing.allocator;
    
    // Create a mock AST for the struct
    var name_field = Node{
        .rule_name = "field",
        .node_type = .field_assignment,
        .text = "",
        .start_position = 0,
        .end_position = 0,
        .children = undefined,
        .attributes = null,
        .parent = null,
    };
    
    const name_key = Node{
        .rule_name = "identifier",
        .node_type = .identifier,
        .text = "name",
        .start_position = 0,
        .end_position = 4,
        .children = &.{},
        .attributes = null,
        .parent = null,
    };
    
    const name_value = Node{
        .rule_name = "string",
        .node_type = .string_literal,
        .text = "\"test\"",
        .start_position = 5,
        .end_position = 11,
        .children = &.{},
        .attributes = null,
        .parent = null,
    };
    
    name_field.children = &[_]Node{ name_key, name_value };
    
    var value_field = Node{
        .rule_name = "field",
        .node_type = .field_assignment,
        .text = "",
        .start_position = 12,
        .end_position = 20,
        .children = undefined,
        .attributes = null,
        .parent = null,
    };
    
    const value_key = Node{
        .rule_name = "identifier",
        .node_type = .identifier,
        .text = "value",
        .start_position = 12,
        .end_position = 17,
        .children = &.{},
        .attributes = null,
        .parent = null,
    };
    
    const value_value = Node{
        .rule_name = "number",
        .node_type = .number_literal,
        .text = "123",
        .start_position = 18,
        .end_position = 21,
        .children = &.{},
        .attributes = null,
        .parent = null,
    };
    
    value_field.children = &[_]Node{ value_key, value_value };
    
    const struct_node = Node{
        .rule_name = "struct",
        .node_type = .struct_literal,
        .text = "",
        .start_position = 0,
        .end_position = 22,
        .children = &[_]Node{ name_field, value_field },
        .attributes = null,
        .parent = null,
    };
    
    const result = try astToNative(TestStruct, allocator, struct_node);
    defer allocator.free(result.name);
    
    try testing.expectEqualStrings("test", result.name);
    try testing.expectEqual(@as(i32, 123), result.value);
    try testing.expectEqual(false, result.enabled); // Default value
}