const std = @import("std");
const io = @import("io.zig");

/// Core ZON (Zig Object Notation) parsing utilities
/// Centralizes all ZON operations with proper error handling and memory management
pub const ZonCore = struct {
    /// Parse ZON content from a slice into the specified type
    /// Handles null-termination automatically
    pub fn parseFromSlice(
        comptime T: type,
        allocator: std.mem.Allocator,
        content: []const u8,
    ) !T {
        // Add null terminator for ZON parsing - ZON requires null-terminated strings
        const null_terminated = try allocator.dupeZ(u8, content);
        defer allocator.free(null_terminated);

        // Parse using Zig's built-in ZON parser
        return std.zon.parse.fromSlice(T, allocator, null_terminated, null, .{});
    }

    /// Parse ZON content from a file into the specified type
    pub fn parseFromFile(
        comptime T: type,
        allocator: std.mem.Allocator,
        file_path: []const u8,
        max_size: usize,
    ) !T {
        const content = try io.readFile(allocator, file_path, max_size);
        defer allocator.free(content);

        return parseFromSlice(T, allocator, content);
    }

    /// Free parsed ZON data
    pub fn free(allocator: std.mem.Allocator, parsed: anytype) void {
        std.zon.parse.free(allocator, parsed);
    }

    /// Parse ZON content with default fallback on any error
    pub fn parseFromSliceWithDefault(
        comptime T: type,
        allocator: std.mem.Allocator,
        content: []const u8,
        default_value: T,
    ) T {
        return parseFromSlice(T, allocator, content) catch default_value;
    }

    /// Parse ZON content from file with default fallback on any error
    pub fn parseFromFileWithDefault(
        comptime T: type,
        allocator: std.mem.Allocator,
        file_path: []const u8,
        max_size: usize,
        default_value: T,
    ) T {
        return parseFromFile(T, allocator, file_path, max_size) catch default_value;
    }
};

/// Dynamic ZON parsing utilities for handling unknown field names at compile time
/// Useful for parsing configurations where field names are determined at runtime
pub const DynamicZonParser = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) DynamicZonParser {
        return DynamicZonParser{ .allocator = allocator };
    }

    /// Parse ZON content using std.json.Value as intermediate to discover fields
    /// Then convert to proper types - useful for dynamic dependency names
    pub fn parseToJsonValue(self: DynamicZonParser, content: []const u8) !std.json.Value {
        // Convert ZON to JSON-compatible format for field discovery
        // ZON is similar to JSON but with different syntax
        var json_content = std.ArrayList(u8).init(self.allocator);
        defer json_content.deinit();

        try self.convertZonToJson(content, &json_content);

        // Parse as JSON to get dynamic field access
        var json_parser = std.json.Parser.init(self.allocator, .alloc_always);
        defer json_parser.deinit();

        const json_tree = try json_parser.parse(json_content.items);
        return json_tree.root;
    }

    /// Convert ZON syntax to JSON syntax for dynamic parsing
    /// This is a simplified converter - handles basic cases
    fn convertZonToJson(self: DynamicZonParser, zon_content: []const u8, json_out: *std.ArrayList(u8)) !void {
        _ = self;
        var i: usize = 0;
        while (i < zon_content.len) {
            const c = zon_content[i];
            switch (c) {
                // Convert ZON struct syntax to JSON object syntax
                '.' => {
                    if (i + 1 < zon_content.len and zon_content[i + 1] == '{') {
                        try json_out.append('{');
                        i += 1; // Skip the '{'
                    } else if (i + 1 < zon_content.len and zon_content[i + 1] == '@') {
                        // Handle .@"field" syntax - convert to "field"
                        i += 2; // Skip .@
                        if (i < zon_content.len and zon_content[i] == '"') {
                            // Copy the quoted field name directly
                            try json_out.append('"');
                            i += 1; // Skip opening quote
                            while (i < zon_content.len and zon_content[i] != '"') {
                                try json_out.append(zon_content[i]);
                                i += 1;
                            }
                            if (i < zon_content.len) {
                                try json_out.append('"'); // Closing quote
                            }
                        }
                    } else {
                        // Regular field like .field_name
                        try json_out.append('"');
                        i += 1; // Skip the '.'
                        while (i < zon_content.len and (std.ascii.isAlphanumeric(zon_content[i]) or zon_content[i] == '_')) {
                            try json_out.append(zon_content[i]);
                            i += 1;
                        }
                        try json_out.append('"');
                        i -= 1; // Back up one since the loop will increment
                    }
                },
                else => try json_out.append(c),
            }
            i += 1;
        }
    }
};

/// ZON validation utilities
pub const ZonValidator = struct {
    /// Validate that required fields are present in parsed ZON
    pub fn validateRequiredFields(
        comptime T: type,
        parsed: T,
        required_fields: []const []const u8,
    ) !void {
        // Use compile-time reflection to check if fields exist
        const type_info = @typeInfo(T);
        if (type_info != .@"struct") {
            return error.NotAStruct;
        }

        for (required_fields) |field_name| {
            var found = false;
            inline for (type_info.@"struct".fields) |field| {
                if (std.mem.eql(u8, field.name, field_name)) {
                    found = true;
                    // Additional validation: check if optional field is null
                    if (@typeInfo(field.type) == .@"optional") {
                        const field_value = @field(parsed, field.name);
                        if (field_value == null) {
                            return error.RequiredFieldMissing;
                        }
                    }
                    break;
                }
            }
            if (!found) {
                return error.RequiredFieldMissing;
            }
        }
    }

    /// Generate helpful error message for ZON parse failures
    pub fn formatParseError(
        allocator: std.mem.Allocator,
        content: []const u8,
        err: anyerror,
    ) ![]u8 {
        // Basic error formatting - could be enhanced with line/column info
        const error_name = @errorName(err);
        
        // Count lines to give some context
        var line_count: usize = 1;
        for (content) |c| {
            if (c == '\n') line_count += 1;
        }

        return std.fmt.allocPrint(allocator,
            "ZON parse error: {s}\nContent has {d} lines\nFirst 100 chars: {s}",
            .{ error_name, line_count, content[0..@min(content.len, 100)] }
        );
    }
};

/// Arena-based ZON parsing for temporary usage (like tests)
/// All allocations are cleaned up when arena is deinitialized
pub const ArenaZonParser = struct {
    arena: std.heap.ArenaAllocator,

    pub fn init(backing_allocator: std.mem.Allocator) ArenaZonParser {
        return ArenaZonParser{
            .arena = std.heap.ArenaAllocator.init(backing_allocator),
        };
    }

    pub fn deinit(self: *ArenaZonParser) void {
        self.arena.deinit();
    }

    /// Parse ZON with arena allocator - no need for individual freeing
    pub fn parseFromSlice(self: *ArenaZonParser, comptime T: type, content: []const u8) !T {
        return ZonCore.parseFromSlice(T, self.arena.allocator(), content);
    }

    /// Parse with default fallback
    pub fn parseFromSliceWithDefault(self: *ArenaZonParser, comptime T: type, content: []const u8, default_value: T) T {
        return self.parseFromSlice(T, content) catch default_value;
    }
};

test "ZonCore basic functionality" {
    const testing = std.testing;

    const TestStruct = struct {
        name: []const u8,
        count: u32,
        enabled: bool = true,
    };

    const test_content =
        \\.{
        \\    .name = "test",
        \\    .count = 42,
        \\    .enabled = false,
        \\}
    ;

    const parsed = try ZonCore.parseFromSlice(TestStruct, testing.allocator, test_content);
    defer ZonCore.free(testing.allocator, parsed);

    try testing.expectEqualStrings("test", parsed.name);
    try testing.expectEqual(@as(u32, 42), parsed.count);
    try testing.expectEqual(false, parsed.enabled);
}

test "ZonCore with default values" {
    const testing = std.testing;

    const TestStruct = struct {
        name: []const u8 = "default",
        count: u32 = 0,
    };

    // Invalid ZON content
    const invalid_content = "{ invalid zon }";

    const default_value = TestStruct{};
    const parsed = ZonCore.parseFromSliceWithDefault(TestStruct, testing.allocator, invalid_content, default_value);

    try testing.expectEqualStrings("default", parsed.name);
    try testing.expectEqual(@as(u32, 0), parsed.count);
}

test "ArenaZonParser usage" {
    const testing = std.testing;

    const TestStruct = struct {
        name: []const u8,
        value: u32,
    };

    const test_content =
        \\.{
        \\    .name = "test",
        \\    .value = 42,
        \\}
    ;

    var arena_parser = ArenaZonParser.init(testing.allocator);
    defer arena_parser.deinit(); // Cleans up all allocations automatically

    const parsed = try arena_parser.parseFromSlice(TestStruct, test_content);
    try testing.expectEqualStrings("test", parsed.name);
    try testing.expectEqual(@as(u32, 42), parsed.value);

    // No need for individual freeing - arena cleans up everything
}

test "ZonValidator required fields" {
    const testing = std.testing;

    const TestStruct = struct {
        name: []const u8,
        count: ?u32 = null,
    };

    const valid_struct = TestStruct{
        .name = "test",
        .count = 42,
    };

    const invalid_struct = TestStruct{
        .name = "test",
        .count = null, // Missing required field
    };

    // Should pass validation
    try ZonValidator.validateRequiredFields(TestStruct, valid_struct, &.{"name"});

    // Should fail validation for missing optional field treated as required
    try testing.expectError(error.RequiredFieldMissing, 
        ZonValidator.validateRequiredFields(TestStruct, invalid_struct, &.{"count"}));
}