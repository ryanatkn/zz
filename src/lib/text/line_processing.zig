const std = @import("std");

/// Comprehensive line processing utilities for text extraction
/// Consolidates line_utils.zig + trim_utils.zig for better organization
/// Provides common patterns for iterating, filtering, and trimming lines

// =============================================================================
// Trimming Utilities (from trim_utils.zig)
// =============================================================================

/// Trim spaces and tabs (most common pattern)
pub fn trimWhitespace(text: []const u8) []const u8 {
    return std.mem.trim(u8, text, " \t");
}

/// Trim all whitespace including newlines
pub fn trimAll(text: []const u8) []const u8 {
    return std.mem.trim(u8, text, " \t\r\n");
}

/// Trim only leading whitespace
pub fn trimLeft(text: []const u8) []const u8 {
    return std.mem.trimLeft(u8, text, " \t");
}

/// Trim only trailing whitespace
pub fn trimRight(text: []const u8) []const u8 {
    return std.mem.trimRight(u8, text, " \t");
}

/// Check if line is empty after trimming
pub fn isBlank(text: []const u8) bool {
    return trimWhitespace(text).len == 0;
}

/// Trim and check if not empty
pub fn trimmedNotEmpty(text: []const u8) ?[]const u8 {
    const trimmed = trimWhitespace(text);
    return if (trimmed.len > 0) trimmed else null;
}

// =============================================================================
// Line Iteration Utilities (from line_utils.zig)
// =============================================================================

/// Iterator that yields trimmed lines
pub const TrimmedLineIterator = struct {
    lines: std.mem.SplitIterator(u8, .scalar),
    
    pub fn init(source: []const u8) TrimmedLineIterator {
        return .{
            .lines = std.mem.splitScalar(u8, source, '\n'),
        };
    }
    
    pub fn next(self: *TrimmedLineIterator) ?[]const u8 {
        while (self.lines.next()) |line| {
            const trimmed = trimWhitespace(line);
            // Return all lines, even empty ones (caller can filter)
            return trimmed;
        }
        return null;
    }
    
    pub fn nextNonEmpty(self: *TrimmedLineIterator) ?[]const u8 {
        while (self.next()) |trimmed| {
            if (trimmed.len > 0) return trimmed;
        }
        return null;
    }
};

/// Block tracking for multi-line constructs (TypeScript interfaces, etc.)
pub const BlockTracker = struct {
    depth: i32 = 0,
    in_block: bool = false,
    open_char: u8 = '{',
    close_char: u8 = '}',
    
    pub fn init() BlockTracker {
        return .{};
    }
    
    pub fn initWithChars(open: u8, close: u8) BlockTracker {
        return .{
            .open_char = open,
            .close_char = close,
        };
    }
    
    pub fn processLine(self: *BlockTracker, line: []const u8) void {
        for (line) |c| {
            if (c == self.open_char) {
                self.depth += 1;
                self.in_block = true;
            } else if (c == self.close_char) {
                self.depth -= 1;
                if (self.depth <= 0) {
                    self.depth = 0;
                    self.in_block = false;
                }
            }
        }
    }
    
    pub fn isInBlock(self: BlockTracker) bool {
        return self.in_block;
    }
    
    pub fn reset(self: *BlockTracker) void {
        self.depth = 0;
        self.in_block = false;
    }
};

// =============================================================================
// Line Extraction Utilities
// =============================================================================

/// Extract lines matching a prefix
pub fn extractLinesWithPrefix(
    source: []const u8,
    prefix: []const u8,
    result: *std.ArrayList(u8),
) !void {
    var iter = TrimmedLineIterator.init(source);
    while (iter.next()) |trimmed| {
        if (std.mem.startsWith(u8, trimmed, prefix)) {
            // Get the original line (not trimmed) for proper formatting
            const line_start = @intFromPtr(trimmed.ptr) - @intFromPtr(source.ptr);
            var end = line_start + trimmed.len;
            // Find the actual end of line including whitespace
            while (end < source.len and source[end] != '\n') : (end += 1) {}
            try result.appendSlice(source[line_start..end]);
            try result.append('\n');
        }
    }
}

/// Extract lines matching any of the given prefixes
pub fn extractLinesWithPrefixes(
    source: []const u8,
    prefixes: []const []const u8,
    result: *std.ArrayList(u8),
) !void {
    var lines = std.mem.splitScalar(u8, source, '\n');
    
    while (lines.next()) |line| {
        const trimmed = trimWhitespace(line);
        for (prefixes) |prefix| {
            if (std.mem.startsWith(u8, trimmed, prefix)) {
                try result.appendSlice(line);
                try result.append('\n');
                break;
            }
        }
    }
}

/// Extract lines containing a substring
pub fn extractLinesContaining(
    source: []const u8,
    substring: []const u8,
    result: *std.ArrayList(u8),
) !void {
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |line| {
        if (std.mem.indexOf(u8, line, substring) != null) {
            try result.appendSlice(line);
            try result.append('\n');
        }
    }
}

/// Extract a block starting from current line until block closes
pub fn extractBlock(
    source: []const u8,
    start_line: []const u8,
    result: *std.ArrayList(u8),
    tracker: *BlockTracker,
) !void {
    // Add the starting line
    try result.appendSlice(start_line);
    try result.append('\n');
    
    // Process the starting line for initial depth
    tracker.processLine(start_line);
    
    // If not in a block after processing start line, we're done
    if (!tracker.isInBlock()) return;
    
    // Find where to continue from in the source
    const start_ptr = @intFromPtr(start_line.ptr);
    const source_ptr = @intFromPtr(source.ptr);
    if (start_ptr < source_ptr) return; // Invalid pointer
    
    var offset = start_ptr - source_ptr + start_line.len;
    if (offset >= source.len) return;
    
    // Skip to next line
    if (offset < source.len and source[offset] == '\n') {
        offset += 1;
    }
    
    // Continue extracting lines until block closes
    const remaining = source[offset..];
    var lines = std.mem.splitScalar(u8, remaining, '\n');
    
    while (lines.next()) |line| {
        try result.appendSlice(line);
        try result.append('\n');
        
        tracker.processLine(line);
        if (!tracker.isInBlock()) break;
    }
}

/// Filter non-empty lines
pub fn filterNonEmpty(
    source: []const u8,
    result: *std.ArrayList(u8),
) !void {
    var lines = std.mem.splitScalar(u8, source, '\n');
    
    while (lines.next()) |line| {
        const trimmed = trimWhitespace(line);
        if (trimmed.len > 0) {
            try result.appendSlice(line);
            try result.append('\n');
        }
    }
}

/// Check if line matches pattern (for CSS selectors with brace)
pub fn extractBeforeBrace(line: []const u8) ?[]const u8 {
    if (std.mem.indexOf(u8, line, "{")) |brace_pos| {
        return trimWhitespace(line[0..brace_pos]);
    }
    return null;
}

// =============================================================================
// Tests
// =============================================================================

test "trimWhitespace basic" {
    try std.testing.expectEqualStrings("hello", trimWhitespace("  hello  "));
    try std.testing.expectEqualStrings("hello", trimWhitespace("\thello\t"));
    try std.testing.expectEqualStrings("hello world", trimWhitespace("  hello world  "));
}

test "trimAll includes newlines" {
    try std.testing.expectEqualStrings("hello", trimAll("\n  hello  \n"));
    try std.testing.expectEqualStrings("hello", trimAll("\r\n\thello\t\r\n"));
}

test "isBlank" {
    try std.testing.expect(isBlank(""));
    try std.testing.expect(isBlank("  "));
    try std.testing.expect(isBlank("\t"));
    try std.testing.expect(isBlank(" \t "));
    try std.testing.expect(!isBlank("a"));
    try std.testing.expect(!isBlank(" a "));
}

test "trimmedNotEmpty" {
    try std.testing.expect(trimmedNotEmpty("") == null);
    try std.testing.expect(trimmedNotEmpty("  ") == null);
    try std.testing.expectEqualStrings("hello", trimmedNotEmpty("  hello  ").?);
}

test "TrimmedLineIterator" {
    const source = "  line1  \n\t\tline2\t\n\n  line3";
    var iter = TrimmedLineIterator.init(source);
    
    try std.testing.expectEqualStrings("line1", iter.next().?);
    try std.testing.expectEqualStrings("line2", iter.next().?);
    try std.testing.expectEqualStrings("", iter.next().?); // empty line
    try std.testing.expectEqualStrings("line3", iter.next().?);
    try std.testing.expect(iter.next() == null);
}

test "BlockTracker" {
    var tracker = BlockTracker.init();
    
    tracker.processLine("interface Foo {");
    try std.testing.expect(tracker.isInBlock());
    try std.testing.expectEqual(@as(i32, 1), tracker.depth);
    
    tracker.processLine("  nested: { value: string }");
    try std.testing.expectEqual(@as(i32, 1), tracker.depth); // balanced
    
    tracker.processLine("}");
    try std.testing.expect(!tracker.isInBlock());
    try std.testing.expectEqual(@as(i32, 0), tracker.depth);
}

test "extractLinesWithPrefix" {
    const allocator = std.testing.allocator;
    const source = "pub fn test()\nfn private()\nconst value = 42\npub fn another()";
    
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();
    
    try extractLinesWithPrefix(source, "pub fn", &result);
    const output = try result.toOwnedSlice();
    defer allocator.free(output);
    
    try std.testing.expect(std.mem.indexOf(u8, output, "pub fn test()") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "pub fn another()") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "fn private()") == null);
}