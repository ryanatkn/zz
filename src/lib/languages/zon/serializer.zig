const std = @import("std");

/// Convert Zig structs back to ZON format
/// This module handles serialization of Zig values into properly formatted ZON strings
pub const ZonSerializer = struct {
    allocator: std.mem.Allocator,
    options: SerializeOptions,
    writer: std.ArrayList(u8).Writer,
    buffer: std.ArrayList(u8),
    
    const Self = @This();
    
    pub const SerializeOptions = struct {
        /// Number of spaces for each indentation level
        indent_size: u8 = 4,
        /// Whether to use tabs instead of spaces
        use_tabs: bool = false,
        /// Whether to format output with newlines and indentation
        pretty: bool = true,
        /// Whether to sort struct fields alphabetically
        sort_fields: bool = false,
        /// Whether to include trailing commas
        trailing_comma: bool = true,
        /// Maximum line width before breaking
        line_width: u32 = 100,
        /// Whether to use single quotes for strings
        use_single_quotes: bool = false,
    };
    
    pub fn init(allocator: std.mem.Allocator, options: SerializeOptions) ZonSerializer {
        var buffer = std.ArrayList(u8).init(allocator);
        return .{
            .allocator = allocator,
            .options = options,
            .writer = buffer.writer(),
            .buffer = buffer,
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.buffer.deinit();
    }
    
    /// Serialize any value to ZON string
    pub fn toString(self: *Self, value: anytype) ![]const u8 {
        self.buffer.clearRetainingCapacity();
        try self.writeValue(@TypeOf(value), value, 0);
        return self.buffer.toOwnedSlice();
    }
    
    /// Write a value at the given indentation depth
    fn writeValue(self: *Self, comptime T: type, value: T, depth: u32) !void {
        const type_info = @typeInfo(T);
        
        switch (type_info) {
            .@"struct" => try self.writeStruct(T, value, depth),
            .pointer => try self.writePointer(T, value, depth),
            .optional => try self.writeOptional(T, value, depth),
            .array => try self.writeArray(T, value, depth),
            .@"enum" => try self.writeEnum(T, value, depth),
            .@"union" => try self.writeUnion(T, value, depth),
            .bool => try self.writeBool(value),
            .int => try self.writeInt(T, value),
            .float => try self.writeFloat(T, value),
            .void => try self.writer.writeAll("{}"),
            .null => try self.writer.writeAll("null"),
            else => return error.UnsupportedType,
        }
    }
    
    /// Write a struct value
    fn writeStruct(self: *Self, comptime T: type, value: T, depth: u32) !void {
        const type_info = @typeInfo(T);
        const fields = type_info.@"struct".fields;
        
        // Check if struct is empty
        if (fields.len == 0) {
            try self.writer.writeAll(".{}");
            return;
        }
        
        // Determine if we should use single-line format
        const use_multiline = self.options.pretty and (fields.len > 2 or self.shouldUseMultiline(T, value));
        
        try self.writer.writeAll(".{");
        
        if (use_multiline) {
            try self.writer.writeByte('\n');
        } else if (fields.len > 0) {
            try self.writer.writeByte(' ');
        }
        
        // Optionally sort fields
        if (self.options.sort_fields) {
            // TODO: Implement field sorting
            inline for (fields, 0..) |field, i| {
                try self.writeField(T, field, @field(value, field.name), depth + 1, use_multiline);
                if (i < fields.len - 1 or self.options.trailing_comma) {
                    try self.writer.writeByte(',');
                }
                if (use_multiline) {
                    try self.writer.writeByte('\n');
                } else if (i < fields.len - 1) {
                    try self.writer.writeByte(' ');
                }
            }
        } else {
            inline for (fields, 0..) |field, i| {
                try self.writeField(T, field, @field(value, field.name), depth + 1, use_multiline);
                if (i < fields.len - 1 or (self.options.trailing_comma and use_multiline)) {
                    try self.writer.writeByte(',');
                }
                if (use_multiline) {
                    try self.writer.writeByte('\n');
                } else if (i < fields.len - 1) {
                    try self.writer.writeByte(' ');
                }
            }
        }
        
        if (use_multiline) {
            try self.writeIndent(depth);
        } else if (fields.len > 0) {
            try self.writer.writeByte(' ');
        }
        
        try self.writer.writeByte('}');
    }
    
    /// Write a single struct field
    fn writeField(self: *Self, comptime T: type, comptime field: std.builtin.Type.StructField, value: field.type, depth: u32, multiline: bool) !void {
        _ = T;
        
        if (multiline) {
            try self.writeIndent(depth);
        }
        
        // Write field name
        try self.writer.writeByte('.');
        
        // Check if field name needs quoting (reserved keywords or special characters)
        if (needsQuoting(field.name)) {
            try self.writer.writeAll("@\"");
            try self.writer.writeAll(field.name);
            try self.writer.writeByte('"');
        } else {
            try self.writer.writeAll(field.name);
        }
        
        try self.writer.writeAll(" = ");
        
        // Write field value
        try self.writeValue(field.type, value, depth);
    }
    
    /// Write a pointer value (mainly strings and slices)
    fn writePointer(self: *Self, comptime T: type, value: T, depth: u32) !void {
        const type_info = @typeInfo(T);
        
        if (type_info.pointer.size == .slice) {
            if (type_info.pointer.child == u8) {
                // String
                try self.writeString(value);
            } else {
                // Array slice
                try self.writeSlice(type_info.pointer.child, value, depth);
            }
        } else if (type_info.pointer.size == .one) {
            // Single pointer - dereference and write
            try self.writeValue(type_info.pointer.child, value.*, depth);
        } else {
            return error.UnsupportedPointerType;
        }
    }
    
    /// Write an optional value
    fn writeOptional(self: *Self, comptime T: type, value: T, depth: u32) !void {
        const type_info = @typeInfo(T);
        
        if (value) |v| {
            try self.writeValue(type_info.optional.child, v, depth);
        } else {
            try self.writer.writeAll("null");
        }
    }
    
    /// Write an array value
    fn writeArray(self: *Self, comptime T: type, value: T, depth: u32) !void {
        const type_info = @typeInfo(T);
        const len = type_info.array.len;
        
        if (len == 0) {
            try self.writer.writeAll(".{}");
            return;
        }
        
        const use_multiline = self.options.pretty and (len > 3 or self.shouldArrayUseMultiline(T, value));
        
        try self.writer.writeAll(".{");
        
        if (use_multiline) {
            try self.writer.writeByte('\n');
        } else if (len > 0) {
            try self.writer.writeByte(' ');
        }
        
        for (value, 0..) |item, i| {
            if (use_multiline) {
                try self.writeIndent(depth + 1);
            }
            
            try self.writeValue(@TypeOf(item), item, depth + 1);
            
            if (i < len - 1 or (self.options.trailing_comma and use_multiline)) {
                try self.writer.writeByte(',');
            }
            
            if (use_multiline) {
                try self.writer.writeByte('\n');
            } else if (i < len - 1) {
                try self.writer.writeByte(' ');
            }
        }
        
        if (use_multiline) {
            try self.writeIndent(depth);
        } else if (len > 0) {
            try self.writer.writeByte(' ');
        }
        
        try self.writer.writeByte('}');
    }
    
    /// Write a slice value
    fn writeSlice(self: *Self, comptime Child: type, value: []const Child, depth: u32) !void {
        if (value.len == 0) {
            try self.writer.writeAll(".{}");
            return;
        }
        
        const use_multiline = self.options.pretty and (value.len > 3);
        
        try self.writer.writeAll(".{");
        
        if (use_multiline) {
            try self.writer.writeByte('\n');
        } else if (value.len > 0) {
            try self.writer.writeByte(' ');
        }
        
        for (value, 0..) |item, i| {
            if (use_multiline) {
                try self.writeIndent(depth + 1);
            }
            
            try self.writeValue(Child, item, depth + 1);
            
            if (i < value.len - 1 or (self.options.trailing_comma and use_multiline)) {
                try self.writer.writeByte(',');
            }
            
            if (use_multiline) {
                try self.writer.writeByte('\n');
            } else if (i < value.len - 1) {
                try self.writer.writeByte(' ');
            }
        }
        
        if (use_multiline) {
            try self.writeIndent(depth);
        } else if (value.len > 0) {
            try self.writer.writeByte(' ');
        }
        
        try self.writer.writeByte('}');
    }
    
    /// Write an enum value
    fn writeEnum(self: *Self, comptime T: type, value: T, depth: u32) !void {
        _ = depth;
        
        try self.writer.writeByte('.');
        try self.writer.writeAll(@tagName(value));
    }
    
    /// Write a union value
    fn writeUnion(self: *Self, comptime T: type, value: T, depth: u32) !void {
        const type_info = @typeInfo(T);
        
        inline for (type_info.@"union".fields) |field| {
            if (std.mem.eql(u8, @tagName(value), field.name)) {
                try self.writer.writeByte('.');
                try self.writer.writeAll(field.name);
                
                if (field.type != void) {
                    try self.writer.writeAll(" = ");
                    try self.writeValue(field.type, @field(value, field.name), depth);
                }
                
                return;
            }
        }
    }
    
    /// Write a boolean value
    fn writeBool(self: *Self, value: bool) !void {
        try self.writer.writeAll(if (value) "true" else "false");
    }
    
    /// Write an integer value
    fn writeInt(self: *Self, comptime T: type, value: T) !void {
        // Special handling for common bases
        if (value == 0) {
            try self.writer.writeByte('0');
        } else {
            try std.fmt.format(self.writer, "{}", .{value});
        }
    }
    
    /// Write a floating point value
    fn writeFloat(self: *Self, comptime T: type, value: T) !void {
        // Handle special values
        if (std.math.isNan(value)) {
            try self.writer.writeAll("nan");
        } else if (std.math.isInf(value)) {
            if (value < 0) {
                try self.writer.writeAll("-inf");
            } else {
                try self.writer.writeAll("inf");
            }
        } else {
            try std.fmt.format(self.writer, "{d}", .{value});
        }
    }
    
    /// Write a string value with proper escaping
    fn writeString(self: *Self, value: []const u8) !void {
        const quote = if (self.options.use_single_quotes) '\'' else '"';
        
        try self.writer.writeByte(quote);
        
        for (value) |c| {
            switch (c) {
                '\n' => try self.writer.writeAll("\\n"),
                '\r' => try self.writer.writeAll("\\r"),
                '\t' => try self.writer.writeAll("\\t"),
                '\\' => try self.writer.writeAll("\\\\"),
                '"' => {
                    if (!self.options.use_single_quotes) {
                        try self.writer.writeAll("\\\"");
                    } else {
                        try self.writer.writeByte(c);
                    }
                },
                '\'' => {
                    if (self.options.use_single_quotes) {
                        try self.writer.writeAll("\\'");
                    } else {
                        try self.writer.writeByte(c);
                    }
                },
                0x20...0x7E => try self.writer.writeByte(c),
                else => {
                    // Escape non-printable characters
                    try std.fmt.format(self.writer, "\\x{x:0>2}", .{c});
                },
            }
        }
        
        try self.writer.writeByte(quote);
    }
    
    /// Write indentation
    fn writeIndent(self: *Self, depth: u32) !void {
        if (!self.options.pretty) return;
        
        const indent_char = if (self.options.use_tabs) '\t' else ' ';
        const indent_count = if (self.options.use_tabs) depth else depth * self.options.indent_size;
        
        for (0..indent_count) |_| {
            try self.writer.writeByte(indent_char);
        }
    }
    
    /// Determine if a struct should use multiline format
    fn shouldUseMultiline(self: *Self, comptime T: type, value: T) bool {
        _ = self;
        _ = value;
        
        const type_info = @typeInfo(T);
        const fields = type_info.@"struct".fields;
        
        // Use multiline if any field is complex
        inline for (fields) |field| {
            const field_type_info = @typeInfo(field.type);
            switch (field_type_info) {
                .@"struct", .array, .pointer => return true,
                else => {},
            }
        }
        
        return false;
    }
    
    /// Determine if an array should use multiline format
    fn shouldArrayUseMultiline(self: *Self, comptime T: type, value: T) bool {
        _ = self;
        _ = value;
        
        const type_info = @typeInfo(T);
        const child_type_info = @typeInfo(type_info.array.child);
        
        // Use multiline for complex element types
        switch (child_type_info) {
            .@"struct", .array, .pointer => return true,
            else => return false,
        }
    }
};

/// Check if a field name needs quoting
fn needsQuoting(name: []const u8) bool {
    // ZON reserved keywords and special cases
    const reserved = [_][]const u8{
        "align", "allowzero", "and", "anyframe", "anytype", "asm",
        "async", "await", "break", "catch", "comptime", "const",
        "continue", "defer", "else", "enum", "errdefer", "error",
        "export", "extern", "false", "fn", "for", "if", "inline",
        "noalias", "nosuspend", "null", "or", "orelse", "packed",
        "pub", "resume", "return", "linksection", "struct", "suspend",
        "switch", "test", "threadlocal", "true", "try", "undefined",
        "union", "unreachable", "usingnamespace", "var", "volatile",
        "while",
    };
    
    for (reserved) |keyword| {
        if (std.mem.eql(u8, name, keyword)) {
            return true;
        }
    }
    
    // Check for special characters
    for (name) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '_') {
            return true;
        }
    }
    
    // Check if starts with number
    if (name.len > 0 and std.ascii.isDigit(name[0])) {
        return true;
    }
    
    return false;
}

/// Convenience function to stringify a value with default options
pub fn stringify(allocator: std.mem.Allocator, value: anytype) ![]const u8 {
    var serializer = ZonSerializer.init(allocator, .{});
    defer serializer.deinit();
    return try serializer.toString(value);
}

/// Convenience function to stringify a value with custom options
pub fn stringifyWithOptions(allocator: std.mem.Allocator, value: anytype, options: ZonSerializer.SerializeOptions) ![]const u8 {
    var serializer = ZonSerializer.init(allocator, options);
    defer serializer.deinit();
    return try serializer.toString(value);
}

// Tests
test "ZonSerializer - basic types" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    // Boolean
    try testing.expectEqualStrings("true", try stringify(allocator, true));
    try testing.expectEqualStrings("false", try stringify(allocator, false));
    
    // Integers
    try testing.expectEqualStrings("42", try stringify(allocator, @as(i32, 42)));
    try testing.expectEqualStrings("0", try stringify(allocator, @as(u8, 0)));
    
    // Floats
    try testing.expectEqualStrings("3.14", try stringify(allocator, @as(f32, 3.14)));
    
    // Strings
    try testing.expectEqualStrings("\"hello\"", try stringify(allocator, "hello"));
    try testing.expectEqualStrings("\"hello\\nworld\"", try stringify(allocator, "hello\nworld"));
}

test "ZonSerializer - structs" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    const Point = struct {
        x: i32,
        y: i32,
    };
    
    const point = Point{ .x = 10, .y = 20 };
    const result = try stringify(allocator, point);
    defer allocator.free(result);
    
    try testing.expectEqualStrings(".{ .x = 10, .y = 20 }", result);
}

test "ZonSerializer - arrays" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    const arr = [_]i32{ 1, 2, 3 };
    const result = try stringify(allocator, arr);
    defer allocator.free(result);
    
    try testing.expectEqualStrings(".{ 1, 2, 3 }", result);
}

test "ZonSerializer - enums" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    const Color = enum { red, green, blue };
    
    try testing.expectEqualStrings(".red", try stringify(allocator, Color.red));
    try testing.expectEqualStrings(".blue", try stringify(allocator, Color.blue));
}

test "ZonSerializer - optionals" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    const maybe_int: ?i32 = 42;
    const nothing: ?i32 = null;
    
    try testing.expectEqualStrings("42", try stringify(allocator, maybe_int));
    try testing.expectEqualStrings("null", try stringify(allocator, nothing));
}

test "ZonSerializer - nested structs" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    const Inner = struct {
        value: i32,
    };
    
    const Outer = struct {
        name: []const u8,
        inner: Inner,
    };
    
    const data = Outer{
        .name = "test",
        .inner = Inner{ .value = 42 },
    };
    
    const result = try stringifyWithOptions(allocator, data, .{ .pretty = false });
    defer allocator.free(result);
    
    try testing.expectEqualStrings(".{ .name = \"test\", .inner = .{ .value = 42 } }", result);
}