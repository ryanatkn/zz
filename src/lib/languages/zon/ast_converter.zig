const common = @import("common.zig");
const std = common.std;
const Node = common.Node;
const utils = common.utils;

/// Convert ZON AST to Zig types
/// This module handles the transformation from our parsed AST representation
/// to native Zig structs, with proper memory management and type conversion.
pub const AstConverter = struct {
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) AstConverter {
        return .{ .allocator = allocator };
    }

    /// Convert an AST node to the specified type T
    pub fn toStruct(self: *Self, comptime T: type, node: Node) !T {
        return try self.convertNode(T, node);
    }

    /// Core conversion dispatcher based on type
    fn convertNode(self: *Self, comptime T: type, node: Node) !T {
        const type_info = @typeInfo(T);

        return switch (type_info) {
            .@"struct" => try self.convertStruct(T, node),
            .pointer => try self.convertPointer(T, node),
            .optional => try self.convertOptional(T, node),
            .array => try self.convertArray(T, node),
            .@"enum" => try self.convertEnum(T, node),
            .bool => try self.convertBool(node),
            .int => try self.convertInt(T, node),
            .float => try self.convertFloat(T, node),
            else => error.UnsupportedType,
        };
    }

    /// Convert AST to struct type
    fn convertStruct(self: *Self, comptime T: type, node: Node) !T {
        const type_info = @typeInfo(T);
        var result: T = undefined;

        // Initialize all fields with defaults
        inline for (type_info.@"struct".fields) |field| {
            @field(result, field.name) = try self.getFieldDefault(field.type);
        }

        // Find the object node (could be root, wrapped in dot expression, or nested)
        const object_node = self.findObjectNode(node) orelse return error.InvalidZonSyntax;

        // Process each field assignment in the object
        for (object_node.children) |child| {
            if (utils.isFieldAssignment(child)) {
                try self.processFieldAssignment(T, &result, child);
            }
        }

        return result;
    }

    /// Process a field assignment node and update the struct
    fn processFieldAssignment(self: *Self, comptime T: type, result: *T, node: Node) !void {
        if (!utils.hasMinimumChildren(node, 2)) return;

        const field_data = utils.processFieldAssignment(node) orelse return;
        const field_name = field_data.field_name;
        const value_node = field_data.value_node;

        // Find the field in the struct and set its value
        const type_info = @typeInfo(T);
        inline for (type_info.@"struct".fields) |field| {
            if (std.mem.eql(u8, field.name, field_name)) {
                const value = try self.convertNode(field.type, value_node);
                @field(result.*, field.name) = value;
                return;
            }
        }

        // Field not found - this is okay for optional/unknown fields
        // TODO: Add option to error on unknown fields
    }

    /// Convert pointer types (mainly strings and slices)
    fn convertPointer(self: *Self, comptime T: type, node: Node) !T {
        const type_info = @typeInfo(T);

        if (type_info.pointer.size == .slice) {
            const child_type = type_info.pointer.child;

            if (child_type == u8) {
                // String type
                return try self.extractString(node);
            } else {
                // Other slice types (e.g., []const []const u8)
                return try self.convertSlice(T, node);
            }
        }

        return error.UnsupportedType;
    }

    /// Convert slice types
    fn convertSlice(self: *Self, comptime T: type, node: Node) !T {
        const type_info = @typeInfo(T);
        const child_type = type_info.pointer.child;

        // Find the array node (could be object with .{} syntax or array with .[])
        const array_node = self.findArrayNode(node) orelse {
            // Empty slice
            return try self.allocator.alloc(child_type, 0);
        };

        // Handle empty array
        if (utils.isEmptyNode(array_node)) {
            return try self.allocator.alloc(child_type, 0);
        }

        // Allocate slice
        var result = try self.allocator.alloc(child_type, array_node.children.len);
        errdefer self.allocator.free(result);

        // Convert each element
        for (array_node.children, 0..) |child, i| {
            // Special handling for nested slices
            if (@typeInfo(child_type) == .pointer and @typeInfo(child_type).pointer.size == .slice) {
                // This is a nested slice (e.g., []const u8 in []const []const u8)
                result[i] = try self.convertNode(child_type, child);
            } else {
                result[i] = try self.convertNode(child_type, child);
            }
        }

        return result;
    }

    /// Convert optional types
    fn convertOptional(self: *Self, comptime T: type, node: Node) !T {
        const type_info = @typeInfo(T);

        // Check for null literal
        if (std.mem.eql(u8, node.rule_name, "null_literal") or
            std.mem.eql(u8, node.text, "null"))
        {
            return null;
        }

        // Convert the underlying type
        const child_type = type_info.optional.child;
        return try self.convertNode(child_type, node);
    }

    /// Convert array types
    fn convertArray(self: *Self, comptime T: type, node: Node) !T {
        const type_info = @typeInfo(T);

        // For arrays, we need to know the size at compile time
        const array_len = type_info.array.len;
        const child_type = type_info.array.child;

        // Find the array node (could be root or nested)
        const array_node = self.findArrayNode(node) orelse {
            // Empty array
            var result: T = undefined;
            var i: usize = 0;
            while (i < array_len) : (i += 1) {
                result[i] = try self.getFieldDefault(child_type);
            }
            return result;
        };

        // Check if we have enough elements
        if (array_node.children.len != array_len) {
            return error.ArraySizeMismatch;
        }

        // Convert each element
        var result: T = undefined;
        for (array_node.children, 0..) |child, i| {
            result[i] = try self.convertNode(child_type, child);
        }

        return result;
    }

    /// Convert enum types
    fn convertEnum(self: *Self, comptime T: type, node: Node) !T {
        _ = self;
        const type_info = @typeInfo(T);

        // Handle dot notation (.field_name)
        var enum_text = node.text;
        if (enum_text.len > 0 and enum_text[0] == '.') {
            enum_text = enum_text[1..];
        }

        // Find matching enum field
        inline for (type_info.@"enum".fields) |field| {
            if (std.mem.eql(u8, field.name, enum_text)) {
                return @enumFromInt(field.value);
            }
        }

        return error.InvalidEnumTag;
    }

    /// Convert boolean values
    fn convertBool(self: *Self, node: Node) !bool {
        _ = self;
        if (std.mem.eql(u8, node.text, "true")) return true;
        if (std.mem.eql(u8, node.text, "false")) return false;
        return error.InvalidZonSyntax;
    }

    /// Convert integer values
    fn convertInt(self: *Self, comptime T: type, node: Node) !T {
        _ = self;

        // Handle different number formats (0x, 0b, 0o)
        const text = node.text;
        const base: u8 = if (std.mem.startsWith(u8, text, "0x"))
            16
        else if (std.mem.startsWith(u8, text, "0b"))
            2
        else if (std.mem.startsWith(u8, text, "0o"))
            8
        else
            10;

        return std.fmt.parseInt(T, text, base) catch error.InvalidZonSyntax;
    }

    /// Convert floating point values
    fn convertFloat(self: *Self, comptime T: type, node: Node) !T {
        _ = self;
        return std.fmt.parseFloat(T, node.text) catch error.InvalidZonSyntax;
    }

    /// Extract string from string literal node
    fn extractString(self: *Self, node: Node) ![]const u8 {
        if (!std.mem.eql(u8, node.rule_name, "string_literal")) {
            return error.InvalidZonSyntax;
        }

        var text = node.text;

        // Check for multiline string (starts with \\)
        if (text.len >= 2 and text[0] == '\\' and text[1] == '\\') {
            return try self.processMultilineString(text);
        }

        // Remove surrounding quotes if present
        if (text.len >= 2) {
            if ((text[0] == '"' and text[text.len - 1] == '"') or
                (text[0] == '\'' and text[text.len - 1] == '\''))
            {
                text = text[1 .. text.len - 1];
            }
        }

        // Handle escape sequences
        return try self.processEscapeSequences(text);
    }

    /// Process multiline string (ZON's \\ syntax)
    fn processMultilineString(self: *Self, text: []const u8) ![]const u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        defer result.deinit();

        var lines = std.mem.tokenizeScalar(u8, text, '\n');
        var first_line = true;

        while (lines.next()) |line| {
            var trimmed = line;

            // Skip the \\ prefix on each line
            if (trimmed.len >= 2 and trimmed[0] == '\\' and trimmed[1] == '\\') {
                trimmed = trimmed[2..];
                // Skip any spaces after \\
                while (trimmed.len > 0 and trimmed[0] == ' ') {
                    trimmed = trimmed[1..];
                }
            }

            // Add line content (joining with space if not first line)
            if (!first_line and result.items.len > 0) {
                // In ZON, multiline strings join lines with a single space
                try result.append(' ');
            }

            // Process escape sequences in the line content
            const processed = try self.processEscapeSequences(trimmed);
            defer self.allocator.free(processed);
            try result.appendSlice(processed);

            first_line = false;
        }

        return result.toOwnedSlice();
    }

    /// Process escape sequences in a string
    fn processEscapeSequences(self: *Self, text: []const u8) ![]const u8 {
        // Quick check if there are any escape sequences
        if (std.mem.indexOf(u8, text, "\\") == null) {
            return try self.allocator.dupe(u8, text);
        }

        var result = std.ArrayList(u8).init(self.allocator);
        defer result.deinit();

        var i: usize = 0;
        while (i < text.len) {
            if (text[i] == '\\' and i + 1 < text.len) {
                const next = text[i + 1];
                switch (next) {
                    'n' => {
                        try result.append('\n');
                        i += 2;
                    },
                    't' => {
                        try result.append('\t');
                        i += 2;
                    },
                    'r' => {
                        try result.append('\r');
                        i += 2;
                    },
                    '\\' => {
                        try result.append('\\');
                        i += 2;
                    },
                    '"' => {
                        try result.append('"');
                        i += 2;
                    },
                    '\'' => {
                        try result.append('\'');
                        i += 2;
                    },
                    'u' => {
                        // Unicode escape sequence \u{XXXX}
                        if (i + 3 < text.len and text[i + 2] == '{') {
                            // Find closing }
                            if (std.mem.indexOf(u8, text[i + 3 ..], "}")) |end_pos| {
                                const hex_str = text[i + 3 .. i + 3 + end_pos];
                                if (hex_str.len <= 6) { // Unicode max is 0x10FFFF
                                    const codepoint = std.fmt.parseInt(u21, hex_str, 16) catch {
                                        // Invalid hex, keep as-is
                                        try result.append('\\');
                                        try result.append('u');
                                        i += 2;
                                        continue;
                                    };

                                    // Encode the codepoint as UTF-8
                                    var buf: [4]u8 = undefined;
                                    const len = std.unicode.utf8Encode(codepoint, &buf) catch {
                                        // Invalid codepoint, keep as-is
                                        try result.append('\\');
                                        try result.append('u');
                                        i += 2;
                                        continue;
                                    };
                                    try result.appendSlice(buf[0..len]);
                                    i += 3 + end_pos + 1; // Skip \u{...}
                                } else {
                                    // Too long for Unicode, keep as-is
                                    try result.append('\\');
                                    try result.append('u');
                                    i += 2;
                                }
                            } else {
                                // No closing }, keep as-is
                                try result.append('\\');
                                try result.append('u');
                                i += 2;
                            }
                        } else {
                            // Not a valid Unicode escape, keep as-is
                            try result.append('\\');
                            try result.append('u');
                            i += 2;
                        }
                    },
                    'x' => {
                        // Hex escape sequence \xXX
                        if (i + 3 < text.len) {
                            const hex_str = text[i + 2 .. i + 4];
                            const byte = std.fmt.parseInt(u8, hex_str, 16) catch {
                                // Invalid hex, keep as-is
                                try result.append('\\');
                                try result.append('x');
                                i += 2;
                                continue;
                            };
                            try result.append(byte);
                            i += 4; // Skip \xXX
                        } else {
                            // Not enough chars, keep as-is
                            try result.append('\\');
                            try result.append('x');
                            i += 2;
                        }
                    },
                    else => {
                        // Unknown escape sequence, keep the backslash
                        try result.append('\\');
                        try result.append(next);
                        i += 2;
                    },
                }
            } else {
                try result.append(text[i]);
                i += 1;
            }
        }

        return result.toOwnedSlice();
    }

    /// Find an object node within the AST
    fn findObjectNode(self: *Self, node: Node) ?Node {
        // Direct object node
        if (std.mem.eql(u8, node.rule_name, "object")) {
            return node;
        }

        // Handle various wrapper patterns
        if (std.mem.eql(u8, node.rule_name, "dot_expression") or
            std.mem.eql(u8, node.rule_name, "expression") or
            std.mem.eql(u8, node.rule_name, "value") or
            std.mem.eql(u8, node.rule_name, "program") or
            std.mem.eql(u8, node.rule_name, "root"))
        {
            // Look for object in children
            for (node.children) |child| {
                if (std.mem.eql(u8, child.rule_name, "object")) {
                    return child;
                }
                // Recursively search in children
                if (self.findObjectNode(child)) |obj| {
                    return obj;
                }
            }
        }

        // For assignment patterns, check the value side
        if (utils.isFieldAssignment(node)) {
            if (utils.hasMinimumChildren(node, 2)) {
                const value_node = utils.getFieldValue(node) orelse return null;
                return self.findObjectNode(value_node);
            }
        }

        // Check all children as last resort
        for (node.children) |child| {
            if (self.findObjectNode(child)) |obj| {
                return obj;
            }
        }

        return null;
    }

    /// Find an array node within the AST
    fn findArrayNode(self: *Self, node: Node) ?Node {
        // Direct array node
        if (std.mem.eql(u8, node.rule_name, "array")) {
            return node;
        }

        // Anonymous array literal .{} can be represented as object
        // When used for arrays, objects are treated as arrays
        if (std.mem.eql(u8, node.rule_name, "object")) {
            // Check if this is being used as an array
            // In ZON, .{} can represent both objects and arrays
            return node;
        }

        // Handle various wrapper patterns
        if (std.mem.eql(u8, node.rule_name, "dot_expression") or
            std.mem.eql(u8, node.rule_name, "expression") or
            std.mem.eql(u8, node.rule_name, "value") or
            std.mem.eql(u8, node.rule_name, "program") or
            std.mem.eql(u8, node.rule_name, "root"))
        {
            // Look for array in children
            for (node.children) |child| {
                if (std.mem.eql(u8, child.rule_name, "array") or
                    std.mem.eql(u8, child.rule_name, "object"))
                {
                    return child;
                }
                // Recursively search in children
                if (self.findArrayNode(child)) |arr| {
                    return arr;
                }
            }
        }

        // For assignment patterns, check the value side
        if (utils.isFieldAssignment(node)) {
            if (utils.hasMinimumChildren(node, 2)) {
                const value_node = utils.getFieldValue(node) orelse return null;
                return self.findArrayNode(value_node);
            }
        }

        // Check all children as last resort
        for (node.children) |child| {
            if (self.findArrayNode(child)) |arr| {
                return arr;
            }
        }

        return null;
    }

    /// Get default value for a field type
    fn getFieldDefault(self: *Self, comptime FieldType: type) !FieldType {
        _ = self;
        const field_info = @typeInfo(FieldType);

        return switch (field_info) {
            .optional => null,
            .bool => false,
            .int => 0,
            .float => 0.0,
            .pointer => blk: {
                if (field_info.pointer.size == .slice) {
                    if (field_info.pointer.child == u8) {
                        // String slice: []const u8
                        break :blk @as(FieldType, "");
                    } else {
                        // Array slice: []const T  
                        break :blk @as(FieldType, &[_]field_info.pointer.child{});
                    }
                }
                break :blk error.UnsupportedType;
            },
            .@"struct" => std.mem.zeroes(FieldType),
            .@"enum" => @enumFromInt(0),
            else => error.UnsupportedType,
        };
    }
};

/// Parse ZON content to a specific type (compatibility function)
/// This is the main entry point for config loading and other use cases
pub fn parseFromSlice(comptime T: type, allocator: std.mem.Allocator, content: []const u8) !T {
    const ZonLexer = @import("lexer.zig").ZonLexer;
    const ZonParser = @import("parser.zig").ZonParser;

    // Tokenize the input
    var lexer = ZonLexer.init(allocator, content, .{});
    defer lexer.deinit();

    const tokens = try lexer.tokenize();
    defer allocator.free(tokens);

    // Parse to AST
    var parser = ZonParser.init(allocator, tokens, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    // Check for critical parse errors
    const errors = parser.getErrors();
    for (errors) |err| {
        if (err.severity == .@"error") {
            // For now, be lenient with errors to support partial parsing
            // TODO: Make this configurable
            break;
        }
    }

    // Convert AST to struct
    var converter = AstConverter.init(allocator);
    return try converter.toStruct(T, ast.root);
}

/// Free allocated memory recursively
/// This function properly cleans up all allocations made during parsing
pub fn free(allocator: std.mem.Allocator, value: anytype) void {
    const T = @TypeOf(value);
    freeValue(T, allocator, value);
}

/// Internal recursive free implementation
fn freeValue(comptime T: type, allocator: std.mem.Allocator, value: T) void {
    const type_info = @typeInfo(T);

    switch (type_info) {
        .@"struct" => {
            // Free each field recursively
            inline for (type_info.@"struct".fields) |field| {
                const field_value = @field(value, field.name);
                freeValue(field.type, allocator, field_value);
            }
        },
        .pointer => {
            if (type_info.pointer.size == .slice) {
                // Free slices (strings and arrays)
                if (type_info.pointer.child == u8) {
                    // Don't free string literals (empty strings)
                    if (value.len > 0) {
                        allocator.free(value);
                    }
                } else {
                    // Free array elements first if they need it
                    for (value) |item| {
                        freeValue(@TypeOf(item), allocator, item);
                    }
                    allocator.free(value);
                }
            }
        },
        .optional => {
            if (value) |v| {
                freeValue(@TypeOf(v), allocator, v);
            }
        },
        else => {
            // Primitive types don't need freeing
        },
    }
}

// Future enhancements:
// - Better error messages with source locations
// - Support for unions
// - Handle circular references
// - Streaming parser for large files
// - Improve memory management for allocated texts
