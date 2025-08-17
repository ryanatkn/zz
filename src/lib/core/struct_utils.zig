const std = @import("std");

/// Generic helper for cloning structs with string fields
/// Automatically duplicates all string fields and slice fields
pub fn cloneStruct(comptime T: type, allocator: std.mem.Allocator, original: T) !T {
    var result: T = undefined;
    
    const fields = std.meta.fields(T);
    inline for (fields) |field| {
        const field_value = @field(original, field.name);
        
        switch (@typeInfo(field.type)) {
            .pointer => |ptr_info| {
                if (ptr_info.size == .slice) {
                    if (ptr_info.child == u8) {
                        // String field - duplicate it
                        @field(result, field.name) = try allocator.dupe(u8, field_value);
                    } else {
                        // Other slice - duplicate it
                        @field(result, field.name) = try allocator.dupe(ptr_info.child, field_value);
                    }
                } else {
                    // Other pointer types - copy as-is
                    @field(result, field.name) = field_value;
                }
            },
            .optional => |opt_info| {
                if (@typeInfo(opt_info.child) == .pointer) {
                    if (field_value) |value| {
                        const ptr_info = @typeInfo(opt_info.child).pointer;
                        if (ptr_info.size == .slice and ptr_info.child == u8) {
                            // Optional string - duplicate if present
                            @field(result, field.name) = try allocator.dupe(u8, value);
                        } else {
                            @field(result, field.name) = value;
                        }
                    } else {
                        @field(result, field.name) = null;
                    }
                } else {
                    @field(result, field.name) = field_value;
                }
            },
            else => {
                // Non-pointer fields - copy directly
                @field(result, field.name) = field_value;
            }
        }
    }
    
    return result;
}

/// Generic helper for freeing struct fields
/// Automatically frees all string fields and slice fields that were allocated
pub fn freeStruct(comptime T: type, allocator: std.mem.Allocator, value: T, owns_memory: bool) void {
    if (!owns_memory) return;
    
    const fields = std.meta.fields(T);
    inline for (fields) |field| {
        const field_value = @field(value, field.name);
        
        switch (@typeInfo(field.type)) {
            .pointer => |ptr_info| {
                if (ptr_info.size == .slice) {
                    if (ptr_info.child == u8) {
                        // String field - free it
                        allocator.free(field_value);
                    } else {
                        // Other slice - free it
                        allocator.free(field_value);
                    }
                }
            },
            .optional => |opt_info| {
                if (@typeInfo(opt_info.child) == .pointer) {
                    if (field_value) |value_inner| {
                        const ptr_info = @typeInfo(opt_info.child).pointer;
                        if (ptr_info.size == .slice and ptr_info.child == u8) {
                            // Optional string - free if present
                            allocator.free(value_inner);
                        }
                    }
                }
            },
            else => {
                // Non-pointer fields - nothing to free
            }
        }
    }
}

/// Helper to create a struct with all string literals marked as non-owning
pub fn createLiteralStruct(comptime T: type, allocator: std.mem.Allocator, data: anytype) T {
    _ = allocator;
    var result: T = undefined;
    
    const fields = std.meta.fields(T);
    inline for (fields) |field| {
        if (@hasField(@TypeOf(data), field.name)) {
            @field(result, field.name) = @field(data, field.name);
        } else {
            // Set default value
            @field(result, field.name) = @as(field.type, undefined);
        }
    }
    
    // If the struct has an owns_memory field, set it to false
    if (@hasField(T, "owns_memory")) {
        result.owns_memory = false;
    }
    
    return result;
}

test "cloneStruct basic functionality" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    const TestStruct = struct {
        name: []const u8,
        description: ?[]const u8,
        count: u32,
        owns_memory: bool = true,
    };
    
    const original = TestStruct{
        .name = "test",
        .description = "description",
        .count = 42,
        .owns_memory = false,
    };
    
    const cloned = try cloneStruct(TestStruct, allocator, original);
    defer freeStruct(TestStruct, allocator, cloned, true);
    
    try testing.expectEqualStrings("test", cloned.name);
    try testing.expectEqualStrings("description", cloned.description.?);
    try testing.expectEqual(@as(u32, 42), cloned.count);
    try testing.expectEqual(false, cloned.owns_memory);
}