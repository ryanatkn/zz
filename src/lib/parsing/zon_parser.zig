const std = @import("std");
const io = @import("../core/io.zig");

/// Utility for parsing ZON (Zig Object Notation) files
pub const ZonParser = struct {
    /// Parse ZON content from a slice into the specified type
    pub fn parseFromSlice(
        comptime T: type,
        allocator: std.mem.Allocator,
        content: []const u8,
    ) !T {
        // Add null terminator for ZON parsing
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

    /// Parse ZON content with error handling that returns a default value on parse failure
    pub fn parseFromSliceWithDefault(
        comptime T: type,
        allocator: std.mem.Allocator,
        content: []const u8,
        default_value: T,
    ) T {
        // Add null terminator for ZON parsing
        const null_terminated = allocator.dupeZ(u8, content) catch return default_value;
        defer allocator.free(null_terminated);

        // Try to parse with better error handling
        const result = std.zon.parse.fromSlice(T, allocator, null_terminated, null, .{}) catch {
            // On any parse error, return the default value
            return default_value;
        };

        return result;
    }

    /// Parse ZON content from file with error handling that returns a default value on any failure
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

test "ZON parser basic functionality" {
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

    const parsed = try ZonParser.parseFromSlice(TestStruct, testing.allocator, test_content);
    defer ZonParser.free(testing.allocator, parsed);

    try testing.expectEqualStrings("test", parsed.name);
    try testing.expectEqual(@as(u32, 42), parsed.count);
    try testing.expectEqual(false, parsed.enabled);
}

test "ZON parser with default values" {
    const testing = std.testing;

    const TestStruct = struct {
        name: []const u8 = "default",
        count: u32 = 0,
    };

    // Invalid ZON content
    const invalid_content = "{ invalid zon }";

    const default_value = TestStruct{};
    const parsed = ZonParser.parseFromSliceWithDefault(TestStruct, testing.allocator, invalid_content, default_value);

    try testing.expectEqualStrings("default", parsed.name);
    try testing.expectEqual(@as(u32, 0), parsed.count);
}
