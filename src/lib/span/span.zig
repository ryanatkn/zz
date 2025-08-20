const std = @import("std");

/// Text span representation for the stream-first architecture
/// Simple u32 start/end for clarity, with PackedSpan for optimization
pub const Span = struct {
    start: u32,
    end: u32,

    /// Create a new span
    pub fn init(start: u32, end: u32) Span {
        return .{ .start = start, .end = end };
    }

    /// Create a point span (zero-length at position)
    pub fn point(pos: u32) Span {
        return .{ .start = pos, .end = pos };
    }

    /// Create an empty span at origin
    pub fn empty() Span {
        return .{ .start = 0, .end = 0 };
    }

    /// Get the length of the span
    pub inline fn len(self: Span) u32 {
        if (self.end < self.start) return 0;
        return self.end - self.start;
    }

    /// Check if span is empty
    pub inline fn isEmpty(self: Span) bool {
        return self.start >= self.end;
    }

    /// Check if span contains a position
    pub inline fn contains(self: Span, pos: u32) bool {
        return pos >= self.start and pos < self.end;
    }

    /// Check if span overlaps with another
    pub inline fn overlaps(self: Span, other: Span) bool {
        return self.start < other.end and other.start < self.end;
    }

    /// Merge two spans into their union
    pub fn merge(self: Span, other: Span) Span {
        return .{
            .start = @min(self.start, other.start),
            .end = @max(self.end, other.end),
        };
    }

    /// Get intersection of two spans
    pub fn intersect(self: Span, other: Span) ?Span {
        const start = @max(self.start, other.start);
        const end = @min(self.end, other.end);
        if (start >= end) return null;
        return Span.init(start, end);
    }

    /// Check if this span contains another span entirely
    pub fn containsSpan(self: Span, other: Span) bool {
        return self.start <= other.start and self.end >= other.end;
    }

    /// Get text slice from source
    pub fn slice(self: Span, source: []const u8) []const u8 {
        const start = @min(self.start, @as(u32, @intCast(source.len)));
        const end = @min(self.end, @as(u32, @intCast(source.len)));
        return source[start..end];
    }

    /// Format for debugging
    pub fn format(
        self: Span,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("[{d}..{d}]", .{ self.start, self.end });
    }
};

// Size assertion for performance guarantees
comptime {
    std.debug.assert(@sizeOf(Span) == 8);
}
