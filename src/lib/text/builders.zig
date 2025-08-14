const std = @import("std");

/// Text building utilities for efficient string construction
/// Consolidates append_utils.zig + result_builder.zig
/// Eliminates 100+ instances of repetitive appendSlice + append('\n') patterns

// =============================================================================
// Simple Append Functions (from append_utils.zig)
// =============================================================================

/// Append a line with automatic newline
pub fn appendLine(list: *std.ArrayList(u8), line: []const u8) !void {
    try list.appendSlice(line);
    try list.append('\n');
}

/// Append multiple lines
pub fn appendLines(list: *std.ArrayList(u8), lines: []const []const u8) !void {
    for (lines) |line| {
        try appendLine(list, line);
    }
}

/// Append with optional newline
pub fn appendMaybe(list: *std.ArrayList(u8), text: []const u8, add_newline: bool) !void {
    try list.appendSlice(text);
    if (add_newline) {
        try list.append('\n');
    }
}

/// Append text with indent
pub fn appendIndented(list: *std.ArrayList(u8), indent: usize, text: []const u8) !void {
    for (0..indent) |_| {
        try list.append(' ');
    }
    try list.appendSlice(text);
}

/// Append line with indent
pub fn appendIndentedLine(list: *std.ArrayList(u8), indent: usize, line: []const u8) !void {
    try appendIndented(list, indent, line);
    try list.append('\n');
}

// =============================================================================
// ResultBuilder - Advanced String Building (from result_builder.zig)
// =============================================================================

pub const ResultBuilder = struct {
    buffer: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) ResultBuilder {
        return .{
            .buffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn initCapacity(allocator: std.mem.Allocator, capacity: usize) !ResultBuilder {
        return .{
            .buffer = try std.ArrayList(u8).initCapacity(allocator, capacity),
        };
    }

    pub fn deinit(self: *ResultBuilder) void {
        self.buffer.deinit();
    }

    /// Append a line with automatic newline
    pub fn appendLine(self: *ResultBuilder, line: []const u8) !void {
        try self.buffer.appendSlice(line);
        try self.buffer.append('\n');
    }

    /// Append multiple lines
    pub fn appendLines(self: *ResultBuilder, lines: []const []const u8) !void {
        for (lines) |line| {
            try self.appendLine(line);
        }
    }

    /// Append raw text without newline
    pub fn append(self: *ResultBuilder, text: []const u8) !void {
        try self.buffer.appendSlice(text);
    }

    /// Append a single character
    pub fn appendChar(self: *ResultBuilder, char: u8) !void {
        try self.buffer.append(char);
    }

    /// Append formatted text
    pub fn appendFmt(self: *ResultBuilder, comptime fmt: []const u8, args: anytype) !void {
        const writer = self.buffer.writer();
        try std.fmt.format(writer, fmt, args);
    }

    /// Append formatted text with newline
    pub fn appendLineFmt(self: *ResultBuilder, comptime fmt: []const u8, args: anytype) !void {
        try self.appendFmt(fmt, args);
        try self.buffer.append('\n');
    }

    /// Append text with indentation
    pub fn appendIndented(self: *ResultBuilder, indent: usize, text: []const u8) !void {
        for (0..indent) |_| {
            try self.buffer.append(' ');
        }
        try self.buffer.appendSlice(text);
    }

    /// Append line with indentation
    pub fn appendIndentedLine(self: *ResultBuilder, indent: usize, line: []const u8) !void {
        try self.appendIndented(indent, line);
        try self.buffer.append('\n');
    }

    /// Get the underlying ArrayList for direct access
    pub fn list(self: *ResultBuilder) *std.ArrayList(u8) {
        return &self.buffer;
    }

    /// Get the current contents as a slice
    pub fn items(self: ResultBuilder) []const u8 {
        return self.buffer.items;
    }

    /// Convert to owned slice
    pub fn toOwnedSlice(self: *ResultBuilder) ![]u8 {
        return self.buffer.toOwnedSlice();
    }

    /// Clear the buffer
    pub fn clear(self: *ResultBuilder) void {
        self.buffer.clearRetainingCapacity();
    }

    /// Get current length
    pub fn len(self: ResultBuilder) usize {
        return self.buffer.items.len;
    }

    /// Check if empty
    pub fn isEmpty(self: ResultBuilder) bool {
        return self.buffer.items.len == 0;
    }
};

// =============================================================================
// Helper Functions
// =============================================================================

/// Create a result builder with estimated capacity
pub fn withCapacity(allocator: std.mem.Allocator, estimated_size: usize) !ResultBuilder {
    return ResultBuilder.initCapacity(allocator, estimated_size);
}

/// Helper to build results from an iterator
pub fn fromLines(
    allocator: std.mem.Allocator,
    lines: anytype,
    filter: ?*const fn ([]const u8) bool,
) !ResultBuilder {
    var builder = ResultBuilder.init(allocator);

    while (lines.next()) |line| {
        if (filter) |f| {
            if (f(line)) {
                try builder.appendLine(line);
            }
        } else {
            try builder.appendLine(line);
        }
    }

    return builder;
}

// =============================================================================
// Tests
// =============================================================================

test "appendLine basic" {
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();

    try appendLine(&list, "hello");
    try appendLine(&list, "world");

    try std.testing.expectEqualStrings("hello\nworld\n", list.items);
}

test "appendLines multiple" {
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();

    const lines = [_][]const u8{ "line1", "line2", "line3" };
    try appendLines(&list, &lines);

    try std.testing.expectEqualStrings("line1\nline2\nline3\n", list.items);
}

test "appendIndentedLine" {
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();

    try appendIndentedLine(&list, 4, "indented");
    try std.testing.expectEqualStrings("    indented\n", list.items);
}

test "ResultBuilder basic operations" {
    var builder = ResultBuilder.init(std.testing.allocator);
    defer builder.deinit();

    try builder.appendLine("line1");
    try builder.appendLine("line2");
    try builder.append("partial");

    const expected = "line1\nline2\npartial";
    try std.testing.expectEqualStrings(expected, builder.items());
}

test "ResultBuilder formatted output" {
    var builder = ResultBuilder.init(std.testing.allocator);
    defer builder.deinit();

    try builder.appendLineFmt("function {s}()", .{"test"});
    try builder.appendIndentedLine(4, "return 42;");
    try builder.appendLine("}");

    const expected = "function test()\n    return 42;\n}\n";
    try std.testing.expectEqualStrings(expected, builder.items());
}

test "ResultBuilder with capacity" {
    var builder = try withCapacity(std.testing.allocator, 1024);
    defer builder.deinit();

    try builder.appendLines(&[_][]const u8{
        "line1",
        "line2",
        "line3",
    });

    try std.testing.expectEqual(@as(usize, 18), builder.len());
}

test "ResultBuilder clear and reuse" {
    var builder = ResultBuilder.init(std.testing.allocator);
    defer builder.deinit();

    try builder.appendLine("first");
    try std.testing.expectEqual(@as(usize, 6), builder.len());

    builder.clear();
    try std.testing.expectEqual(@as(usize, 0), builder.len());
    try std.testing.expect(builder.isEmpty());

    try builder.appendLine("second");
    try std.testing.expectEqualStrings("second\n", builder.items());
}
