const std = @import("std");
const Span = @import("../foundation/types/span.zig").Span;

/// Zero-copy buffer management for efficient token generation
///
/// The Buffer provides:
/// - Memory-mapped file support
/// - Zero-copy text slicing
/// - Incremental edit application
/// - UTF-8 validation and handling
///
/// Performance target: Zero allocations for token text slices
pub const Buffer = struct {
    /// Source content (either owned or memory-mapped)
    content: []const u8,

    /// Whether we own the content memory
    owns_content: bool,

    /// Original file path (for memory mapping)
    file_path: ?[]const u8,

    /// Memory allocator
    allocator: std.mem.Allocator,

    /// Buffer statistics
    stats: BufferStats,

    /// Edit generation counter
    generation: u32,

    pub fn init(allocator: std.mem.Allocator) Buffer {
        return Buffer{
            .content = "",
            .owns_content = false,
            .file_path = null,
            .allocator = allocator,
            .stats = BufferStats{},
            .generation = 0,
        };
    }

    pub fn deinit(self: *Buffer) void {
        if (self.owns_content) {
            self.allocator.free(self.content);
        }
        if (self.file_path) |path| {
            self.allocator.free(path);
        }
    }

    /// Set content from string (takes ownership)
    pub fn setContent(self: *Buffer, content: []const u8) !void {
        if (self.owns_content) {
            self.allocator.free(self.content);
        }

        // Copy the content so we own it
        self.content = try self.allocator.dupe(u8, content);
        self.owns_content = true;
        self.generation += 1;
        self.stats.content_sets += 1;
    }

    /// Set content from file path (memory-mapped if possible)
    pub fn setContentFromFile(self: *Buffer, file_path: []const u8) !void {
        if (self.owns_content) {
            self.allocator.free(self.content);
            self.owns_content = false;
        }

        // Try to memory-map the file for large files
        const file = try std.fs.cwd().openFile(file_path, .{});
        defer file.close();

        const file_size = try file.getEndPos();

        // For small files, just read into memory
        // For large files (>1MB), consider memory mapping
        if (file_size < 1024 * 1024) {
            self.content = try file.readToEndAlloc(self.allocator, file_size);
            self.owns_content = true;
        } else {
            // Memory mapping would go here
            // For now, fall back to reading
            self.content = try file.readToEndAlloc(self.allocator, file_size);
            self.owns_content = true;
        }

        // Store file path
        if (self.file_path) |old_path| {
            self.allocator.free(old_path);
        }
        self.file_path = try self.allocator.dupe(u8, file_path);

        self.generation += 1;
        self.stats.file_loads += 1;
    }

    /// Get the current content
    pub fn getContent(self: Buffer) []const u8 {
        return self.content;
    }

    /// Get a slice of the content (zero-copy)
    pub fn getSlice(self: Buffer, span: Span) []const u8 {
        if (span.end > self.content.len) {
            return self.content[span.start..];
        }
        return self.content[span.start..span.end];
    }

    /// Get content length
    pub fn getLength(self: Buffer) usize {
        return self.content.len;
    }

    /// Apply an edit to the buffer
    pub fn applyEdit(self: *Buffer, range: Span, new_text: []const u8) !void {
        const timer = std.time.nanoTimestamp();
        defer {
            const elapsed: u64 = @intCast(std.time.nanoTimestamp() - timer);
            self.stats.total_edit_time_ns += elapsed;
            self.stats.edits_applied += 1;
        }

        if (range.start > self.content.len or range.end > self.content.len) {
            return error.InvalidRange;
        }

        const old_content = self.content;
        const new_len = old_content.len - range.len() + new_text.len;

        // Allocate new buffer
        var new_content = try self.allocator.alloc(u8, new_len);

        // Copy parts: [before_edit] + [new_text] + [after_edit]
        const before_len = range.start;
        const after_start = range.end;
        const after_len = old_content.len - after_start;

        // Copy before edit
        if (before_len > 0) {
            @memcpy(new_content[0..before_len], old_content[0..before_len]);
        }

        // Copy new text
        if (new_text.len > 0) {
            @memcpy(new_content[before_len .. before_len + new_text.len], new_text);
        }

        // Copy after edit
        if (after_len > 0) {
            @memcpy(new_content[before_len + new_text.len ..], old_content[after_start..]);
        }

        // Replace content
        if (self.owns_content) {
            self.allocator.free(self.content);
        }
        self.content = new_content;
        self.owns_content = true;
        self.generation += 1;
    }

    /// Apply multiple edits efficiently
    pub fn applyEdits(self: *Buffer, edits: []const Edit) !void {
        // Sort edits by position (descending) to avoid position shifts
        const sorted_edits = try self.allocator.dupe(Edit, edits);
        defer self.allocator.free(sorted_edits);

        const SortContext = struct {
            fn lessThan(context: void, a: Edit, b: Edit) bool {
                _ = context;
                return a.range.start > b.range.start; // Descending order
            }
        };

        std.sort.insertion(Edit, sorted_edits, {}, SortContext.lessThan);

        // Apply edits in reverse order
        for (sorted_edits) |edit| {
            try self.applyEdit(edit.range, edit.new_text);
        }
    }

    /// Create a view into the buffer
    pub fn createView(self: Buffer, span: Span) BufferView {
        const safe_span = self.clampSpan(span);
        return BufferView{
            .buffer = &self,
            .span = safe_span,
            .content = self.getSlice(safe_span),
        };
    }

    /// Find line starts for coordinate conversion
    pub fn findLineStarts(self: Buffer, allocator: std.mem.Allocator) ![]usize {
        var line_starts = std.ArrayList(usize).init(allocator);
        errdefer line_starts.deinit();

        try line_starts.append(0); // First line starts at 0

        for (self.content, 0..) |ch, i| {
            if (ch == '\n') {
                try line_starts.append(i + 1);
            }
        }

        return line_starts.toOwnedSlice();
    }

    /// Convert position to line/column
    pub fn positionToLineColumn(self: Buffer, position: usize, line_starts: []const usize) struct { line: usize, column: usize } {
        _ = self;
        // Binary search for line
        var line: usize = 0;
        for (line_starts, 0..) |start, i| {
            if (start > position) {
                break;
            }
            line = i;
        }

        const line_start = if (line < line_starts.len) line_starts[line] else 0;
        const column = position - line_start;

        return .{ .line = line, .column = column };
    }

    /// Validate UTF-8 content
    pub fn validateUTF8(self: Buffer) bool {
        return std.unicode.utf8ValidateSlice(self.content);
    }

    /// Get buffer statistics
    pub fn getStats(self: Buffer) BufferStats {
        return self.stats;
    }

    /// Reset statistics
    pub fn resetStats(self: *Buffer) void {
        self.stats = BufferStats{};
    }

    /// Get current generation
    pub fn getGeneration(self: Buffer) u32 {
        return self.generation;
    }

    /// Check if buffer has unsaved changes
    pub fn hasUnsavedChanges(self: Buffer) bool {
        return self.generation > 0 and self.file_path != null;
    }

    // ========================================================================
    // Private Implementation
    // ========================================================================

    /// Clamp span to buffer bounds
    fn clampSpan(self: Buffer, span: Span) Span {
        const start = @min(span.start, self.content.len);
        const end = @min(span.end, self.content.len);
        return Span.init(start, @max(start, end));
    }
};

/// A view into a buffer for zero-copy operations
pub const BufferView = struct {
    /// Reference to the parent buffer
    buffer: *const Buffer,

    /// Span this view covers
    span: Span,

    /// Direct slice into buffer content
    content: []const u8,

    /// Get the content of this view
    pub fn getContent(self: BufferView) []const u8 {
        return self.content;
    }

    /// Get length of this view
    pub fn getLength(self: BufferView) usize {
        return self.content.len;
    }

    /// Get a subview
    pub fn subview(self: BufferView, relative_span: Span) BufferView {
        const absolute_start = self.span.start + relative_span.start;
        const absolute_end = self.span.start + relative_span.end;
        const absolute_span = Span.init(absolute_start, @min(absolute_end, self.span.end));

        return self.buffer.createView(absolute_span);
    }

    /// Convert relative position to absolute
    pub fn toAbsolutePosition(self: BufferView, relative_pos: usize) usize {
        return self.span.start + relative_pos;
    }

    /// Convert absolute position to relative
    pub fn toRelativePosition(self: BufferView, absolute_pos: usize) ?usize {
        if (absolute_pos < self.span.start or absolute_pos >= self.span.end) {
            return null;
        }
        return absolute_pos - self.span.start;
    }
};

/// Edit operation for buffer modification
pub const Edit = struct {
    /// Range to replace
    range: Span,

    /// New text to insert
    new_text: []const u8,

    pub fn init(range: Span, new_text: []const u8) Edit {
        return .{
            .range = range,
            .new_text = new_text,
        };
    }

    /// Create an insertion edit
    pub fn insertion(position: usize, text: []const u8) Edit {
        return .{
            .range = Span.point(position),
            .new_text = text,
        };
    }

    /// Create a deletion edit
    pub fn deletion(range: Span) Edit {
        return .{
            .range = range,
            .new_text = "",
        };
    }

    /// Create a replacement edit
    pub fn replacement(range: Span, new_text: []const u8) Edit {
        return .{
            .range = range,
            .new_text = new_text,
        };
    }

    /// Check if this is an insertion
    pub fn isInsertion(self: Edit) bool {
        return self.range.len() == 0 and self.new_text.len > 0;
    }

    /// Check if this is a deletion
    pub fn isDeletion(self: Edit) bool {
        return self.range.len() > 0 and self.new_text.len == 0;
    }

    /// Check if this is a replacement
    pub fn isReplacement(self: Edit) bool {
        return self.range.len() > 0 and self.new_text.len > 0;
    }
};

/// Statistics for buffer operations
pub const BufferStats = struct {
    /// Number of times content was set
    content_sets: usize = 0,

    /// Number of files loaded
    file_loads: usize = 0,

    /// Number of edits applied
    edits_applied: usize = 0,

    /// Total time spent applying edits (nanoseconds)
    total_edit_time_ns: u64 = 0,

    /// Number of views created
    views_created: usize = 0,

    /// Peak memory usage
    peak_memory_usage: usize = 0,

    pub fn averageEditTimeNs(self: BufferStats) u64 {
        if (self.edits_applied == 0) return 0;
        return self.total_edit_time_ns / self.edits_applied;
    }

    pub fn averageEditTimeUs(self: BufferStats) f64 {
        const ns = self.averageEditTimeNs();
        return @as(f64, @floatFromInt(ns)) / 1000.0;
    }
};

// Tests
const testing = std.testing;

test "Buffer basic operations" {
    var buffer = Buffer.init(testing.allocator);
    defer buffer.deinit();

    const content = "hello world";
    try buffer.setContent(content);

    try testing.expectEqualStrings(content, buffer.getContent());
    try testing.expectEqual(@as(usize, content.len), buffer.getLength());
    try testing.expectEqual(@as(u32, 1), buffer.getGeneration());
}

test "Buffer slicing" {
    var buffer = Buffer.init(testing.allocator);
    defer buffer.deinit();

    const content = "hello world";
    try buffer.setContent(content);

    const span = Span.init(6, 11);
    const slice = buffer.getSlice(span);
    try testing.expectEqualStrings("world", slice);
}

test "Buffer editing" {
    var buffer = Buffer.init(testing.allocator);
    defer buffer.deinit();

    const content = "hello world";
    try buffer.setContent(content);

    // Replace "world" with "universe"
    const range = Span.init(6, 11);
    try buffer.applyEdit(range, "universe");

    try testing.expectEqualStrings("hello universe", buffer.getContent());
    try testing.expectEqual(@as(u32, 2), buffer.getGeneration());
}

test "Buffer view operations" {
    var buffer = Buffer.init(testing.allocator);
    defer buffer.deinit();

    const content = "hello world test";
    try buffer.setContent(content);

    // Create view of "world"
    const span = Span.init(6, 11);
    const view = buffer.createView(span);

    try testing.expectEqualStrings("world", view.getContent());
    try testing.expectEqual(@as(usize, 5), view.getLength());

    // Test position conversion
    try testing.expectEqual(@as(usize, 8), view.toAbsolutePosition(2));
    try testing.expectEqual(@as(?usize, 2), view.toRelativePosition(8));
}

test "Buffer line finding" {
    var buffer = Buffer.init(testing.allocator);
    defer buffer.deinit();

    const content = "line1\nline2\nline3";
    try buffer.setContent(content);

    const line_starts = try buffer.findLineStarts(testing.allocator);
    defer testing.allocator.free(line_starts);

    try testing.expectEqual(@as(usize, 3), line_starts.len);
    try testing.expectEqual(@as(usize, 0), line_starts[0]); // "line1"
    try testing.expectEqual(@as(usize, 6), line_starts[1]); // "line2"
    try testing.expectEqual(@as(usize, 12), line_starts[2]); // "line3"

    // Test position to line/column conversion
    const pos_info = buffer.positionToLineColumn(7, line_starts); // 'i' in "line2"
    try testing.expectEqual(@as(usize, 1), pos_info.line);
    try testing.expectEqual(@as(usize, 1), pos_info.column);
}

test "Buffer multiple edits" {
    var buffer = Buffer.init(testing.allocator);
    defer buffer.deinit();

    const content = "abc def ghi";
    try buffer.setContent(content);

    // Create multiple edits
    var edits = [_]Edit{
        Edit.replacement(Span.init(8, 11), "xyz"), // Replace "ghi" with "xyz"
        Edit.replacement(Span.init(4, 7), "123"), // Replace "def" with "123"
        Edit.replacement(Span.init(0, 3), "000"), // Replace "abc" with "000"
    };

    try buffer.applyEdits(&edits);
    try testing.expectEqualStrings("000 123 xyz", buffer.getContent());
}

test "Buffer UTF-8 validation" {
    var buffer = Buffer.init(testing.allocator);
    defer buffer.deinit();

    const valid_utf8 = "hello 🌍 world";
    try buffer.setContent(valid_utf8);
    try testing.expect(buffer.validateUTF8());

    // Test with ASCII
    const ascii = "hello world";
    try buffer.setContent(ascii);
    try testing.expect(buffer.validateUTF8());
}

test "Edit operations" {
    // Test edit constructors
    const insertion = Edit.insertion(5, "text");
    try testing.expect(insertion.isInsertion());
    try testing.expect(!insertion.isDeletion());
    try testing.expect(!insertion.isReplacement());

    const deletion = Edit.deletion(Span.init(0, 5));
    try testing.expect(!deletion.isInsertion());
    try testing.expect(deletion.isDeletion());
    try testing.expect(!deletion.isReplacement());

    const replacement = Edit.replacement(Span.init(0, 5), "new");
    try testing.expect(!replacement.isInsertion());
    try testing.expect(!replacement.isDeletion());
    try testing.expect(replacement.isReplacement());
}
