const std = @import("std");
const path_utils = @import("path.zig");

/// Clean collection utilities - no wrapper types, just stdlib aliases and helpers
/// Eliminates ManagedArrayList anti-pattern and provides simple, idiomatic Zig

// Direct stdlib aliases
pub const List = std.ArrayList;
pub const Map = std.HashMap;
pub const Set = std.AutoHashMap([]const u8, void);
pub const StringMap = std.StringHashMap;
pub const StringSet = std.StringHashMap(void);

/// Convert ArrayList to owned slice
pub fn toOwnedSlice(comptime T: type, list: *List(T)) ![]T {
    return list.toOwnedSlice();
}

/// Deduplicate slice elements (specialized for strings)
pub fn deduplicateStrings(allocator: std.mem.Allocator, items: []const []const u8) ![][]const u8 {
    var result = List([]const u8).init(allocator);
    defer result.deinit();

    var seen = StringSet.init(allocator);
    defer seen.deinit();

    for (items) |item| {
        const entry = try seen.getOrPut(item);
        if (!entry.found_existing) {
            try result.append(item);
        }
    }

    return result.toOwnedSlice();
}

/// Filter slice based on predicate
pub fn filter(
    comptime T: type,
    allocator: std.mem.Allocator,
    items: []const T,
    predicate: *const fn (T) bool,
) ![]T {
    var result = List(T).init(allocator);
    defer result.deinit();

    for (items) |item| {
        if (predicate(item)) {
            try result.append(item);
        }
    }

    return result.toOwnedSlice();
}

/// Map slice to new type
pub fn map(
    comptime T: type,
    comptime U: type,
    allocator: std.mem.Allocator,
    items: []const T,
    transform: *const fn (std.mem.Allocator, T) anyerror!U,
) ![]U {
    var result = List(U).init(allocator);
    defer result.deinit();

    for (items) |item| {
        const transformed = try transform(allocator, item);
        try result.append(transformed);
    }

    return result.toOwnedSlice();
}

/// Join string slice with separator
pub fn joinStrings(
    allocator: std.mem.Allocator,
    strings: []const []const u8,
    separator: []const u8,
) ![]u8 {
    if (strings.len == 0) return try allocator.dupe(u8, "");
    if (strings.len == 1) return try allocator.dupe(u8, strings[0]);

    // Calculate total length
    var total_len: usize = 0;
    for (strings, 0..) |str, i| {
        total_len += str.len;
        if (i < strings.len - 1) {
            total_len += separator.len;
        }
    }

    // Build result
    var result = try allocator.alloc(u8, total_len);
    var pos: usize = 0;

    for (strings, 0..) |str, i| {
        @memcpy(result[pos .. pos + str.len], str);
        pos += str.len;

        if (i < strings.len - 1) {
            @memcpy(result[pos .. pos + separator.len], separator);
            pos += separator.len;
        }
    }

    return result;
}

/// Check if slice contains item
pub fn contains(comptime T: type, slice: []const T, item: T) bool {
    for (slice) |element| {
        if (std.meta.eql(element, item)) {
            return true;
        }
    }
    return false;
}

/// Find index of item in slice
pub fn indexOf(comptime T: type, slice: []const T, item: T) ?usize {
    for (slice, 0..) |element, i| {
        if (std.meta.eql(element, item)) {
            return i;
        }
    }
    return null;
}

/// Safe pop - returns null instead of panicking on empty
pub fn popSafe(comptime T: type, list: *List(T)) ?T {
    if (list.items.len == 0) return null;
    return list.pop();
}

/// String list utilities
pub const StringList = struct {
    /// Create string list with initial capacity
    pub fn initWithCapacity(allocator: std.mem.Allocator, capacity: usize) !List([]const u8) {
        return List([]const u8).initCapacity(allocator, capacity);
    }

    /// Add string by duplication
    pub fn addDupe(list: *List([]const u8), allocator: std.mem.Allocator, str: []const u8) !void {
        const duped = try allocator.dupe(u8, str);
        try list.append(duped);
    }

    /// Add formatted string
    pub fn addFmt(
        list: *List([]const u8),
        allocator: std.mem.Allocator,
        comptime format: []const u8,
        args: anytype,
    ) !void {
        const formatted = try std.fmt.allocPrint(allocator, format, args);
        try list.append(formatted);
    }

    /// Free all strings in list
    pub fn freeStrings(list: *List([]const u8), allocator: std.mem.Allocator) void {
        for (list.items) |str| {
            allocator.free(str);
        }
        list.clearAndFree();
    }
};

/// Path list utilities
pub const PathList = struct {
    /// Add path by joining components
    pub fn addPath(
        list: *List([]const u8),
        allocator: std.mem.Allocator,
        dir: []const u8,
        name: []const u8,
    ) !void {
        const path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir, name });
        try list.append(path);
    }

    /// Add normalized path
    pub fn addNormalized(
        list: *List([]const u8),
        allocator: std.mem.Allocator,
        path: []const u8,
    ) !void {
        const normalized = try path_utils.normalizePath(allocator, path);
        try list.append(normalized);
    }
};

test "stdlib aliases work correctly" {
    const testing = std.testing;

    var list = List(i32).init(testing.allocator);
    defer list.deinit();

    try list.append(42);
    try testing.expect(list.items.len == 1);
    try testing.expect(list.items[0] == 42);
}

test "deduplicateStrings removes duplicates" {
    const testing = std.testing;

    const items = [_][]const u8{ "a", "b", "a", "c", "b" };
    const result = try deduplicateStrings(testing.allocator, &items);
    defer testing.allocator.free(result);

    try testing.expect(result.len == 3); // a, b, c
}

test "filter works correctly" {
    const testing = std.testing;

    const items = [_]i32{ 1, 2, 3, 4, 5 };
    const isEven = struct {
        fn func(x: i32) bool {
            return @rem(x, 2) == 0;
        }
    }.func;

    const result = try filter(i32, testing.allocator, &items, isEven);
    defer testing.allocator.free(result);

    try testing.expect(result.len == 2); // 2, 4
    try testing.expect(result[0] == 2);
    try testing.expect(result[1] == 4);
}

test "joinStrings works correctly" {
    const testing = std.testing;

    const strings = [_][]const u8{ "hello", "world", "test" };
    const result = try joinStrings(testing.allocator, &strings, ", ");
    defer testing.allocator.free(result);

    try testing.expectEqualStrings("hello, world, test", result);
}

test "StringList utilities" {
    const testing = std.testing;

    var list = try StringList.initWithCapacity(testing.allocator, 2);
    defer {
        StringList.freeStrings(&list, testing.allocator);
        list.deinit();
    }

    try StringList.addDupe(&list, testing.allocator, "hello");
    try StringList.addFmt(&list, testing.allocator, "world_{d}", .{42});

    try testing.expect(list.items.len == 2);
    try testing.expectEqualStrings("hello", list.items[0]);
    try testing.expectEqualStrings("world_42", list.items[1]);
}

test "popSafe doesn't panic on empty" {
    const testing = std.testing;

    var list = List(i32).init(testing.allocator);
    defer list.deinit();

    const result = popSafe(i32, &list);
    try testing.expect(result == null);

    try list.append(42);
    const result2 = popSafe(i32, &list);
    try testing.expect(result2.? == 42);
}
