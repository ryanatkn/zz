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

/// Parse ZON content to a specific type (updated for streaming)
pub fn parseFromSlice(comptime T: type, allocator: std.mem.Allocator, content: []const u8) !T {
    const ZonParser = @import("parser.zig").ZonParser;

    // Use streaming parser directly (3-arg pattern)
    var parser = try ZonParser.init(allocator, content, .{});
    defer parser.deinit();

    var ast = parser.parse() catch |err| {
        // If parsing fails, bubble up the error
        return err;
    };
    defer ast.deinit();

    // Convert AST to target type
    if (ast.root) |root| {
        return try convertAstToType(T, allocator, root);
    } else {
        // No valid AST root - this indicates parsing failed
        return error.InvalidZonContent;
    }
}

/// Convert ZON AST node to target type
fn convertAstToType(comptime T: type, allocator: std.mem.Allocator, node: *const Node) !T {
    const type_info = @typeInfo(T);

    switch (type_info) {
        // @"struct" is the actual Zig built-in enum variant from @typeInfo()
        // The @"" syntax is required because 'struct' is a keyword
        .@"struct" => |struct_info| {
            var result: T = undefined;

            // Initialize all fields to their zero values
            inline for (struct_info.fields) |field| {
                @field(result, field.name) = getFieldZeroValue(field.type);
            }

            if (node.* != .object) {
                // If we expect a struct but get something else, handle special cases
                if (node.* == .root) {
                    return try convertAstToType(T, allocator, node.root.value);
                }
                // For other non-object types, this is a type mismatch error
                return error.InvalidZonContent;
            }

            const object_node = node.object;

            // For each field in the target struct
            inline for (struct_info.fields) |field| {
                // Find matching field in ZON object
                for (object_node.fields) |ast_field| {
                    if (ast_field == .field) {
                        const field_node = ast_field.field;

                        // Get field name from either field_name or identifier nodes
                        const field_name = switch (field_node.name.*) {
                            .field_name => |fn_node| blk: {
                                var name = fn_node.name;
                                // First remove leading dot if present
                                if (name.len > 1 and name[0] == '.') {
                                    name = name[1..];
                                }
                                // Then handle quoted field names like @"tree-sitter"
                                if (name.len >= 3 and name[0] == '@' and name[1] == '"' and name[name.len - 1] == '"') {
                                    break :blk name[2 .. name.len - 1]; // Remove @" and "
                                } else {
                                    break :blk name;
                                }
                            },
                            .identifier => |id_node| blk: {
                                var name = id_node.name;
                                // First remove leading dot if present
                                if (name.len > 1 and name[0] == '.') {
                                    name = name[1..];
                                }
                                // Then handle quoted identifiers like @"tree-sitter"
                                if (name.len >= 3 and name[0] == '@' and name[1] == '"' and name[name.len - 1] == '"') {
                                    break :blk name[2 .. name.len - 1]; // Remove @" and "
                                } else {
                                    break :blk name;
                                }
                            },
                            else => continue, // Skip if neither field_name nor identifier
                        };

                        if (std.mem.eql(u8, field_name, field.name)) {
                            // Found matching field, convert value
                            @field(result, field.name) = try convertValueToFieldType(field.type, allocator, field_node.value);
                            break;
                        }
                    }
                }
            }

            return result;
        },
        else => {
            // For non-struct types, try to convert directly
            return try convertValueToFieldType(T, allocator, node);
        },
    }
}

/// Get appropriate zero value for a field type
fn getFieldZeroValue(comptime FieldType: type) FieldType {
    const type_info = @typeInfo(FieldType);
    switch (type_info) {
        .optional => return null,
        .pointer => |ptr_info| {
            if (ptr_info.size == .slice) {
                return &[_]ptr_info.child{};
            }
            return undefined; // This will need special handling
        },
        else => return std.mem.zeroes(FieldType),
    }
}

/// Convert AST node to specific field type
fn convertValueToFieldType(comptime FieldType: type, allocator: std.mem.Allocator, node: *const Node) !FieldType {
    const type_info = @typeInfo(FieldType);

    switch (type_info) {
        .optional => |optional_info| {
            // For optional types, check for null first
            if (node.* == .null) {
                return null;
            }
            // Otherwise convert the payload type
            const payload = try convertValueToFieldType(optional_info.child, allocator, node);
            return @as(FieldType, payload);
        },
        .int => {
            if (node.* == .number) {
                const num_str = node.number.raw;
                return try std.fmt.parseInt(FieldType, num_str, 10);
            }
            // Return zero for non-number types to maintain compatibility
            return 0;
        },
        .float => {
            if (node.* == .number) {
                const num_str = node.number.raw;
                return try std.fmt.parseFloat(FieldType, num_str);
            }
            // Return zero for non-number types to maintain compatibility
            return 0.0;
        },
        .bool => {
            if (node.* == .boolean) {
                return node.boolean.value;
            }
            // Return false for non-boolean types to maintain compatibility
            return false;
        },
        .pointer => |ptr_info| {
            if (ptr_info.size == .slice and ptr_info.child == u8) {
                // String type - need to allocate owned copy
                if (node.* == .string) {
                    return try allocator.dupe(u8, node.string.value);
                }
                // Special case: for identifier nodes, use the name
                if (node.* == .identifier) {
                    return try allocator.dupe(u8, node.identifier.name);
                }
                // Special case: for field_name nodes, extract the name
                if (node.* == .field_name) {
                    var field_name = node.field_name.name;
                    // First remove leading dot if present
                    if (field_name.len > 1 and field_name[0] == '.') {
                        field_name = field_name[1..];
                    }
                    // Then handle quoted field names like @"tree-sitter"
                    if (field_name.len >= 3 and field_name[0] == '@' and field_name[1] == '"' and field_name[field_name.len - 1] == '"') {
                        return try allocator.dupe(u8, field_name[2 .. field_name.len - 1]); // Remove @" and "
                    } else {
                        return try allocator.dupe(u8, field_name);
                    }
                }
                // Return empty string for incompatible types to maintain compatibility
                return try allocator.dupe(u8, "");
            } else if (ptr_info.size == .slice) {
                // Array type - handle []const []const u8 or []T
                if (node.* == .array) {
                    const array_node = node.array;
                    const result = try allocator.alloc(ptr_info.child, array_node.elements.len);
                    errdefer allocator.free(result);

                    for (array_node.elements, 0..) |element, i| {
                        result[i] = try convertValueToFieldType(ptr_info.child, allocator, &element);
                    }

                    return result;
                }
                // For objects that should be arrays (like ZON anonymous lists)
                if (node.* == .object and node.object.fields.len > 0) {
                    // Check if this looks like an anonymous list (all fields are positional)
                    var elements = std.ArrayList(ptr_info.child).init(allocator);
                    defer elements.deinit();

                    for (node.object.fields) |field| {
                        if (field == .field) {
                            const elem_result = convertValueToFieldType(ptr_info.child, allocator, field.field.value) catch continue;
                            try elements.append(elem_result);
                        } else {
                            // Direct element in anonymous list
                            const elem_result = convertValueToFieldType(ptr_info.child, allocator, &field) catch continue;
                            try elements.append(elem_result);
                        }
                    }

                    const result = try allocator.alloc(ptr_info.child, elements.items.len);
                    @memcpy(result, elements.items);
                    return result;
                }
                return try allocator.alloc(ptr_info.child, 0); // Empty array
            }
        },
        .@"struct" => {
            // Nested struct - recurse with better error handling
            return convertAstToType(FieldType, allocator, node) catch {
                // If conversion fails, return a zero-valued struct
                return getFieldZeroValue(FieldType);
            };
        },
        else => {
            // For other types (enums, unions, etc.), return zero value
            return getFieldZeroValue(FieldType);
        },
    }
}

/// Free parsed ZON data (compatibility function)
pub fn free(allocator: std.mem.Allocator, parsed_data: anytype) void {
    const T = @TypeOf(parsed_data);
    freeType(T, allocator, parsed_data);
}

/// Recursively free allocated memory in parsed data
fn freeType(comptime T: type, allocator: std.mem.Allocator, data: T) void {
    const type_info = @typeInfo(T);

    switch (type_info) {
        .@"struct" => |struct_info| {
            inline for (struct_info.fields) |field| {
                const field_value = @field(data, field.name);
                freeType(field.type, allocator, field_value);
            }
        },
        .optional => |optional_info| {
            if (data) |value| {
                freeType(optional_info.child, allocator, value);
            }
        },
        .pointer => |ptr_info| {
            if (ptr_info.size == .slice and ptr_info.child == u8) {
                // Free allocated string
                if (data.len > 0) {
                    allocator.free(data);
                }
            } else if (ptr_info.size == .slice) {
                // Free array elements first, then the array itself
                for (data) |element| {
                    freeType(ptr_info.child, allocator, element);
                }
                allocator.free(data);
            }
        },
        else => {
            // Other types don't need explicit freeing
        },
    }
}
