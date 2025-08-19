const std = @import("std");
const AST = @import("../../ast/mod.zig").AST;
const Node = @import("../../ast/mod.zig").Node;
const NodeType = @import("../../ast/mod.zig").NodeType;
const ASTFactory = @import("../../ast/factory.zig").ASTFactory;
const Fact = @import("../../parser/foundation/types/fact.zig").Fact;
const Span = @import("../../parser/foundation/types/span.zig").Span;
const Predicate = @import("../../parser/foundation/types/predicate.zig").Predicate;

/// Convert native Zig type to AST node
/// Uses AST factory for safe construction with proper memory management
pub fn nativeToAST(value: anytype, factory: *ASTFactory) !Node {
    const T = @TypeOf(value);
    const type_info = @typeInfo(T);
    
    switch (type_info) {
        .Bool => {
            const text = if (value) "true" else "false";
            return try factory.createLiteral(.bool_literal, text, 0, text.len);
        },
        .Int, .ComptimeInt => {
            var buf: [64]u8 = undefined;
            const text = try std.fmt.bufPrint(&buf, "{}", .{value});
            const owned_text = try factory.allocator.dupe(u8, text);
            try factory.addOwnedText(owned_text);
            return try factory.createLiteral(.number_literal, owned_text, 0, owned_text.len);
        },
        .Float, .ComptimeFloat => {
            var buf: [64]u8 = undefined;
            const text = try std.fmt.bufPrint(&buf, "{d}", .{value});
            const owned_text = try factory.allocator.dupe(u8, text);
            try factory.addOwnedText(owned_text);
            return try factory.createLiteral(.number_literal, owned_text, 0, owned_text.len);
        },
        .Optional => {
            if (value) |val| {
                return try nativeToAST(val, factory);
            } else {
                return try factory.createLiteral(.null_literal, "null", 0, 4);
            }
        },
        .Array => {
            var children = try factory.allocator.alloc(Node, value.len);
            for (value, 0..) |item, i| {
                children[i] = try nativeToAST(item, factory);
            }
            return try factory.createContainer(.array, children, 0, 100); // Position would be calculated
        },
        .Pointer => |ptr| {
            switch (ptr.size) {
                .One => return try nativeToAST(value.*, factory),
                .Slice => {
                    if (ptr.child == u8) {
                        // String
                        return try createStringNode(factory, value);
                    }
                    // Array slice
                    var children = try factory.allocator.alloc(Node, value.len);
                    for (value, 0..) |item, i| {
                        children[i] = try nativeToAST(item, factory);
                    }
                    return try factory.createContainer(.array, children, 0, 100);
                },
                else => return error.UnsupportedPointerType,
            }
        },
        .Struct => |struct_info| {
            var children = std.ArrayList(Node).init(factory.allocator);
            defer children.deinit();
            
            inline for (struct_info.fields) |field| {
                const field_value = @field(value, field.name);
                
                // Skip optional fields that are null
                if (@typeInfo(field.type) == .Optional) {
                    if (field_value == null) continue;
                }
                
                // Create field assignment node
                const key_node = try factory.createLiteral(.identifier, field.name, 0, field.name.len);
                const value_node = try nativeToAST(field_value, factory);
                
                const field_children = try factory.allocator.alloc(Node, 2);
                field_children[0] = key_node;
                field_children[1] = value_node;
                
                const field_node = try factory.createContainer(.field_assignment, field_children, 0, 100);
                try children.append(field_node);
            }
            
            return try factory.createContainer(.struct_literal, try children.toOwnedSlice(), 0, 100);
        },
        .Union => |union_info| {
            if (union_info.tag_type) |_| {
                // Tagged union
                const active_tag = std.meta.activeTag(value);
                const tag_name = @tagName(active_tag);
                
                inline for (union_info.fields) |field| {
                    if (std.mem.eql(u8, field.name, tag_name)) {
                        const union_value = @field(value, field.name);
                        
                        // Create a struct-like representation
                        var children = try factory.allocator.alloc(Node, 2);
                        
                        // Tag field
                        const tag_key = try factory.createLiteral(.identifier, "tag", 0, 3);
                        const tag_value = try factory.createLiteral(.string_literal, tag_name, 0, tag_name.len);
                        const tag_children = try factory.allocator.alloc(Node, 2);
                        tag_children[0] = tag_key;
                        tag_children[1] = tag_value;
                        children[0] = try factory.createContainer(.field_assignment, tag_children, 0, 50);
                        
                        // Value field
                        const value_key = try factory.createLiteral(.identifier, "value", 0, 5);
                        const value_node = try nativeToAST(union_value, factory);
                        const value_children = try factory.allocator.alloc(Node, 2);
                        value_children[0] = value_key;
                        value_children[1] = value_node;
                        children[1] = try factory.createContainer(.field_assignment, value_children, 50, 100);
                        
                        return try factory.createContainer(.struct_literal, children, 0, 100);
                    }
                }
            }
            return error.UntaggedUnionNotSupported;
        },
        .Enum => {
            const enum_name = @tagName(value);
            return try factory.createLiteral(.enum_literal, enum_name, 0, enum_name.len);
        },
        .Null => {
            return try factory.createLiteral(.null_literal, "null", 0, 4);
        },
        .Void => {
            return try factory.createLiteral(.void_literal, "void", 0, 4);
        },
        else => return error.UnsupportedType,
    }
}

// Note: std.json.Value conversion removed - use nativeToAST() for Zig types instead

/// Generate facts directly from native type (more efficient than AST)
pub fn nativeToFacts(value: anytype, allocator: std.mem.Allocator) ![]Fact {
    var facts = std.ArrayList(Fact).init(allocator);
    defer facts.deinit();
    
    var fact_id: u32 = 0;
    var position: usize = 0;
    
    try generateFactsForValue(value, &facts, &fact_id, &position);
    
    return try facts.toOwnedSlice();
}

// Helper functions

fn createStringNode(factory: *ASTFactory, text: []const u8) !Node {
    // Escape and quote the string
    var result = std.ArrayList(u8).init(factory.allocator);
    defer result.deinit();
    
    try result.append('"');
    for (text) |c| {
        switch (c) {
            '\n' => try result.appendSlice("\\n"),
            '\r' => try result.appendSlice("\\r"),
            '\t' => try result.appendSlice("\\t"),
            '\\' => try result.appendSlice("\\\\"),
            '"' => try result.appendSlice("\\\""),
            else => try result.append(c),
        }
    }
    try result.append('"');
    
    const owned_text = try result.toOwnedSlice();
    try factory.addOwnedText(owned_text);
    return try factory.createLiteral(.string_literal, owned_text, 0, owned_text.len);
}

fn generateFactsForValue(value: anytype, facts: *std.ArrayList(Fact), fact_id: *u32, position: *usize) !void {
    const T = @TypeOf(value);
    const type_info = @typeInfo(T);
    
    const start_pos = position.*;
    
    switch (type_info) {
        .Bool => {
            const text_len = if (value) 4 else 5; // "true" or "false"
            const fact = Fact.init(
                fact_id.*,
                Span.init(start_pos, start_pos + text_len),
                .{ .literal_value = .{ .boolean = value } },
                null,
                1.0,
                0,
            );
            try facts.append(fact);
            fact_id.* += 1;
            position.* += text_len;
        },
        .Int, .ComptimeInt => {
            var buf: [64]u8 = undefined;
            const text = try std.fmt.bufPrint(&buf, "{}", .{value});
            const fact = Fact.init(
                fact_id.*,
                Span.init(start_pos, start_pos + text.len),
                .{ .literal_value = .{ .integer = @intCast(value) } },
                null,
                1.0,
                0,
            );
            try facts.append(fact);
            fact_id.* += 1;
            position.* += text.len;
        },
        .Float, .ComptimeFloat => {
            var buf: [64]u8 = undefined;
            const text = try std.fmt.bufPrint(&buf, "{d}", .{value});
            const fact = Fact.init(
                fact_id.*,
                Span.init(start_pos, start_pos + text.len),
                .{ .literal_value = .{ .float = @floatCast(value) } },
                null,
                1.0,
                0,
            );
            try facts.append(fact);
            fact_id.* += 1;
            position.* += text.len;
        },
        .Pointer => |ptr| {
            if (ptr.child == u8 and ptr.size == .Slice) {
                // String
                const text_len = value.len + 2; // Include quotes
                const fact = Fact.init(
                    fact_id.*,
                    Span.init(start_pos, start_pos + text_len),
                    .{ .literal_value = .{ .string = value } },
                    null,
                    1.0,
                    0,
                );
                try facts.append(fact);
                fact_id.* += 1;
                position.* += text_len;
            } else if (ptr.size == .Slice) {
                // Array slice
                const array_start = position.*;
                position.* += 1; // [
                
                for (value) |item| {
                    try generateFactsForValue(item, facts, fact_id, position);
                    position.* += 1; // comma or space
                }
                
                position.* += 1; // ]
                
                // Add array boundary fact
                const array_fact = Fact.init(
                    fact_id.*,
                    Span.init(array_start, position.*),
                    .{ .boundary_kind = .array },
                    null,
                    1.0,
                    0,
                );
                try facts.append(array_fact);
                fact_id.* += 1;
            }
        },
        .Struct => |struct_info| {
            const struct_start = position.*;
            position.* += 2; // .{
            
            inline for (struct_info.fields) |field| {
                const field_value = @field(value, field.name);
                
                // Skip optional null fields
                if (@typeInfo(field.type) == .Optional) {
                    if (field_value == null) continue;
                }
                
                // Field name fact
                const name_start = position.*;
                position.* += 1; // .
                position.* += field.name.len;
                
                const name_fact = Fact.init(
                    fact_id.*,
                    Span.init(name_start, position.*),
                    .{ .field_name = .{ .string = field.name } },
                    null,
                    1.0,
                    0,
                );
                try facts.append(name_fact);
                fact_id.* += 1;
                
                position.* += 3; // " = "
                
                // Field value
                try generateFactsForValue(field_value, facts, fact_id, position);
                position.* += 2; // ", "
            }
            
            position.* += 1; // }
            
            // Add struct boundary fact
            const struct_fact = Fact.init(
                fact_id.*,
                Span.init(struct_start, position.*),
                .{ .boundary_kind = .object },
                null,
                1.0,
                0,
            );
            try facts.append(struct_fact);
            fact_id.* += 1;
        },
        else => {},
    }
}

// Tests
const testing = std.testing;

test "nativeToAST - primitive types" {
    const allocator = testing.allocator;
    var factory = ASTFactory.init(allocator);
    defer factory.deinit();
    
    // Boolean
    {
        const node = try nativeToAST(true, &factory);
        try testing.expectEqual(NodeType.bool_literal, node.node_type);
        try testing.expectEqualStrings("true", node.text);
    }
    
    // Integer
    {
        const node = try nativeToAST(@as(i32, 42), &factory);
        try testing.expectEqual(NodeType.number_literal, node.node_type);
        try testing.expectEqualStrings("42", node.text);
    }
    
    // Float
    {
        const node = try nativeToAST(@as(f64, 3.14), &factory);
        try testing.expectEqual(NodeType.number_literal, node.node_type);
        // Float formatting may vary
        try testing.expect(node.text.len > 0);
    }
    
    // String
    {
        const node = try nativeToAST("hello", &factory);
        try testing.expectEqual(NodeType.string_literal, node.node_type);
        try testing.expectEqualStrings("\"hello\"", node.text);
    }
}

test "nativeToAST - struct conversion" {
    const TestStruct = struct {
        name: []const u8,
        value: i32,
        enabled: bool,
    };
    
    const allocator = testing.allocator;
    var factory = ASTFactory.init(allocator);
    defer factory.deinit();
    
    const test_data = TestStruct{
        .name = "test",
        .value = 123,
        .enabled = true,
    };
    
    const node = try nativeToAST(test_data, &factory);
    try testing.expectEqual(NodeType.struct_literal, node.node_type);
    try testing.expectEqual(@as(usize, 3), node.children.len);
    
    // Check fields
    for (node.children) |child| {
        try testing.expectEqual(NodeType.field_assignment, child.node_type);
        try testing.expectEqual(@as(usize, 2), child.children.len);
    }
}

test "nativeToAST - array conversion" {
    const allocator = testing.allocator;
    var factory = ASTFactory.init(allocator);
    defer factory.deinit();
    
    const array = [_]i32{ 1, 2, 3 };
    const node = try nativeToAST(array, &factory);
    
    try testing.expectEqual(NodeType.array, node.node_type);
    try testing.expectEqual(@as(usize, 3), node.children.len);
    
    for (node.children, 0..) |child, i| {
        try testing.expectEqual(NodeType.number_literal, child.node_type);
        var buf: [10]u8 = undefined;
        const expected = try std.fmt.bufPrint(&buf, "{}", .{array[i]});
        try testing.expectEqualStrings(expected, child.text);
    }
}
