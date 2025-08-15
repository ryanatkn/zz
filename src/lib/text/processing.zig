const std = @import("std");
const collections = @import("../core/collections.zig");

/// String processing utilities to consolidate 10+ repeated splitScalar patterns
/// Provides common text processing operations with consistent error handling

/// Process lines with state context
pub fn processLinesWithState(
    comptime StateType: type,
    content: []const u8,
    state: StateType,
    processor: *const fn (StateType, []const u8) void,
) void {
    var iter = std.mem.splitScalar(u8, content, '\n');
    while (iter.next()) |line| {
        processor(state, line);
    }
}

/// Process lines with simple callback
pub fn processLines(content: []const u8, processor: *const fn ([]const u8) void) void {
    var iter = std.mem.splitScalar(u8, content, '\n');
    while (iter.next()) |line| {
        processor(line);
    }
}

/// Split content by delimiter and trim whitespace from each part
pub fn splitAndTrim(
    allocator: std.mem.Allocator,
    content: []const u8,
    delimiter: u8,
) ![][]const u8 {
    var parts = collections.List([]const u8).init(allocator);
    defer parts.deinit();

    var iter = std.mem.splitScalar(u8, content, delimiter);
    while (iter.next()) |part| {
        const trimmed = std.mem.trim(u8, part, " \t\n\r");
        if (trimmed.len > 0) {
            const owned = try allocator.dupe(u8, trimmed);
            try parts.append(owned);
        }
    }

    return parts.toOwnedSlice();
}

/// Split content by delimiter without trimming
pub fn split(
    allocator: std.mem.Allocator,
    content: []const u8,
    delimiter: u8,
) ![][]const u8 {
    var parts = collections.List([]const u8).init(allocator);
    defer parts.deinit();

    var iter = std.mem.splitScalar(u8, content, delimiter);
    while (iter.next()) |part| {
        const owned = try allocator.dupe(u8, part);
        try parts.append(owned);
    }

    return parts.toOwnedSlice();
}

/// Join strings with separator (enhanced version of collections.joinStrings)
pub fn joinWithSeparator(
    allocator: std.mem.Allocator,
    items: []const []const u8,
    separator: []const u8,
) ![]u8 {
    return collections.joinStrings(allocator, items, separator);
}

/// Process lines and collect results that match predicate
pub fn filterLines(
    allocator: std.mem.Allocator,
    content: []const u8,
    predicate: *const fn ([]const u8) bool,
) ![][]const u8 {
    var results = collections.List([]const u8).init(allocator);
    defer results.deinit();

    var iter = std.mem.splitScalar(u8, content, '\n');
    while (iter.next()) |line| {
        if (predicate(line)) {
            const owned = try allocator.dupe(u8, line);
            try results.append(owned);
        }
    }

    return results.toOwnedSlice();
}

/// Transform lines with a mapping function
pub fn mapLines(
    allocator: std.mem.Allocator,
    content: []const u8,
    mapper: *const fn (std.mem.Allocator, []const u8) anyerror![]const u8,
) ![][]const u8 {
    var results = collections.List([]const u8).init(allocator);
    defer results.deinit();

    var iter = std.mem.splitScalar(u8, content, '\n');
    while (iter.next()) |line| {
        const mapped = try mapper(allocator, line);
        try results.append(mapped);
    }

    return results.toOwnedSlice();
}

/// Count lines in content
pub fn countLines(content: []const u8) usize {
    var count: usize = 0;
    var iter = std.mem.splitScalar(u8, content, '\n');
    while (iter.next()) |_| {
        count += 1;
    }
    return count;
}

/// Count non-empty lines in content
pub fn countNonEmptyLines(content: []const u8) usize {
    var count: usize = 0;
    var iter = std.mem.splitScalar(u8, content, '\n');
    while (iter.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len > 0) {
            count += 1;
        }
    }
    return count;
}

/// Extract lines that contain a specific substring
pub fn linesContaining(
    allocator: std.mem.Allocator,
    content: []const u8,
    substring: []const u8,
) ![][]const u8 {
    const predicate = struct {
        search: []const u8,
        
        fn contains(self: @This(), line: []const u8) bool {
            return std.mem.indexOf(u8, line, self.search) != null;
        }
    }{ .search = substring };

    var results = collections.List([]const u8).init(allocator);
    defer results.deinit();

    var iter = std.mem.splitScalar(u8, content, '\n');
    while (iter.next()) |line| {
        if (predicate.contains(line)) {
            const owned = try allocator.dupe(u8, line);
            try results.append(owned);
        }
    }

    return results.toOwnedSlice();
}

/// Extract lines matching a prefix
pub fn linesWithPrefix(
    allocator: std.mem.Allocator,
    content: []const u8,
    prefix: []const u8,
) ![][]const u8 {
    const predicate = struct {
        prefix_str: []const u8,
        
        fn hasPrefix(self: @This(), line: []const u8) bool {
            return std.mem.startsWith(u8, line, self.prefix_str);
        }
    }{ .prefix_str = prefix };

    var results = collections.List([]const u8).init(allocator);
    defer results.deinit();

    var iter = std.mem.splitScalar(u8, content, '\n');
    while (iter.next()) |line| {
        if (predicate.hasPrefix(line)) {
            const owned = try allocator.dupe(u8, line);
            try results.append(owned);
        }
    }

    return results.toOwnedSlice();
}

/// Convenience function for parsing comma-separated values
pub fn parseCommaSeparated(
    allocator: std.mem.Allocator,
    content: []const u8,
) ![][]const u8 {
    return splitAndTrim(allocator, content, ',');
}

/// Convenience function for parsing space-separated values
pub fn parseSpaceSeparated(
    allocator: std.mem.Allocator,
    content: []const u8,
) ![][]const u8 {
    return splitAndTrim(allocator, content, ' ');
}

/// Free memory allocated by split functions
pub fn freeSplitResult(allocator: std.mem.Allocator, parts: [][]const u8) void {
    for (parts) |part| {
        allocator.free(part);
    }
    allocator.free(parts);
}

// Tests for text processing utilities
test "splitAndTrim basic functionality" {
    const testing = std.testing;
    
    const content = "hello , world , test ";
    const parts = try splitAndTrim(testing.allocator, content, ',');
    defer freeSplitResult(testing.allocator, parts);
    
    try testing.expectEqual(@as(usize, 3), parts.len);
    try testing.expectEqualStrings("hello", parts[0]);
    try testing.expectEqualStrings("world", parts[1]);
    try testing.expectEqualStrings("test", parts[2]);
}

test "processLines callback" {
    const testing = std.testing;
    
    var line_count: usize = 0;
    const counter = struct {
        count: *usize,
        
        fn countLine(self: @This(), line: []const u8) void {
            _ = line;
            self.count.* += 1;
        }
    }{ .count = &line_count };
    
    const content = "line1\nline2\nline3";
    processLinesWithState(@TypeOf(counter), content, counter, @TypeOf(counter).countLine);
    
    try testing.expectEqual(@as(usize, 3), line_count);
}

test "filterLines functionality" {
    const testing = std.testing;
    
    const predicate = struct {
        fn isNotEmpty(line: []const u8) bool {
            return std.mem.trim(u8, line, " \t").len > 0;
        }
    }.isNotEmpty;
    
    const content = "line1\n   \nline3\n\nline5";
    const results = try filterLines(testing.allocator, content, predicate);
    defer freeSplitResult(testing.allocator, results);
    
    try testing.expectEqual(@as(usize, 3), results.len);
    try testing.expectEqualStrings("line1", results[0]);
    try testing.expectEqualStrings("line3", results[1]);
    try testing.expectEqualStrings("line5", results[2]);
}

test "linesContaining functionality" {
    const testing = std.testing;
    
    const content = "function test()\nconst value = 42\nfunction helper()";
    const results = try linesContaining(testing.allocator, content, "function");
    defer freeSplitResult(testing.allocator, results);
    
    try testing.expectEqual(@as(usize, 2), results.len);
    try testing.expectEqualStrings("function test()", results[0]);
    try testing.expectEqualStrings("function helper()", results[1]);
}

test "countLines and countNonEmptyLines" {
    const testing = std.testing;
    
    const content = "line1\n\nline3\n   \nline5";
    
    try testing.expectEqual(@as(usize, 5), countLines(content));
    try testing.expectEqual(@as(usize, 3), countNonEmptyLines(content));
}

test "parseCommaSeparated convenience" {
    const testing = std.testing;
    
    const content = "apple, banana,cherry ,  date  ";
    const results = try parseCommaSeparated(testing.allocator, content);
    defer freeSplitResult(testing.allocator, results);
    
    try testing.expectEqual(@as(usize, 4), results.len);
    try testing.expectEqualStrings("apple", results[0]);
    try testing.expectEqualStrings("banana", results[1]);
    try testing.expectEqualStrings("cherry", results[2]);
    try testing.expectEqualStrings("date", results[3]);
}