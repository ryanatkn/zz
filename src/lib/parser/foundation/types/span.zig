const std = @import("std");

/// Text position and range management for stratified parser
/// Optimized for frequent comparisons and span operations (<10ns target)
/// Used throughout the fact stream system for position tracking
pub const Span = struct {
    start: usize,
    end: usize,

    /// Create a new span with start and end positions
    pub fn init(start: usize, end: usize) Span {
        return .{
            .start = start,
            .end = end,
        };
    }

    /// Create a span at a single position (start == end)
    pub fn point(position: usize) Span {
        return .{
            .start = position,
            .end = position,
        };
    }

    /// Create an empty span at position 0
    pub fn empty() Span {
        return .{
            .start = 0,
            .end = 0,
        };
    }

    /// Get the length of the span
    pub fn len(self: Span) usize {
        if (self.end < self.start) return 0;
        return self.end - self.start;
    }

    /// Check if the span is empty (zero length)
    pub fn isEmpty(self: Span) bool {
        return self.start >= self.end;
    }

    /// Check if this span contains a position
    pub fn contains(self: Span, pos: usize) bool {
        return pos >= self.start and pos < self.end;
    }

    /// Check if this span contains another span entirely
    pub fn containsSpan(self: Span, other: Span) bool {
        return self.start <= other.start and other.end <= self.end;
    }

    /// Check if this span overlaps with another span
    pub fn overlaps(self: Span, other: Span) bool {
        return self.start < other.end and other.start < self.end;
    }

    /// Check if this span is adjacent to another span (touching but not overlapping)
    pub fn isAdjacent(self: Span, other: Span) bool {
        return self.end == other.start or other.end == self.start;
    }

    /// Check if this span comes before another span (no overlap or adjacency)
    pub fn isBefore(self: Span, other: Span) bool {
        return self.end <= other.start;
    }

    /// Check if this span comes after another span (no overlap or adjacency)
    pub fn isAfter(self: Span, other: Span) bool {
        return self.start >= other.end;
    }

    /// Merge this span with another span to create the smallest span containing both
    pub fn merge(self: Span, other: Span) Span {
        if (self.isEmpty()) return other;
        if (other.isEmpty()) return self;

        return .{
            .start = @min(self.start, other.start),
            .end = @max(self.end, other.end),
        };
    }

    /// Get the intersection of this span with another span
    /// Returns empty span if no intersection
    pub fn intersect(self: Span, other: Span) Span {
        const start = @max(self.start, other.start);
        const end = @min(self.end, other.end);

        if (start >= end) {
            return empty();
        }

        return .{
            .start = start,
            .end = end,
        };
    }

    /// Extend this span to include a position
    pub fn extend(self: Span, pos: usize) Span {
        if (self.isEmpty()) {
            return point(pos);
        }

        return .{
            .start = @min(self.start, pos),
            .end = @max(self.end, pos + 1),
        };
    }

    /// Extend this span to include another span
    pub fn extendSpan(self: Span, other: Span) Span {
        return self.merge(other);
    }

    /// Shift this span by an offset (both start and end)
    pub fn shift(self: Span, offset: isize) Span {
        if (offset >= 0) {
            const pos_offset: usize = @intCast(offset);
            return .{
                .start = self.start + pos_offset,
                .end = self.end + pos_offset,
            };
        } else {
            const neg_offset: usize = @intCast(-offset);
            const new_start = if (self.start >= neg_offset) self.start - neg_offset else 0;
            const new_end = if (self.end >= neg_offset) self.end - neg_offset else 0;
            return .{
                .start = new_start,
                .end = new_end,
            };
        }
    }

    /// Get text from input using this span
    pub fn getText(self: Span, input: []const u8) []const u8 {
        if (self.isEmpty() or self.start >= input.len) {
            return "";
        }

        const actual_end = @min(self.end, input.len);
        if (self.start >= actual_end) {
            return "";
        }

        return input[self.start..actual_end];
    }

    /// Compare spans for ordering (useful for BTree)
    pub fn order(self: Span, other: Span) std.math.Order {
        // First compare by start position
        if (self.start < other.start) return .lt;
        if (self.start > other.start) return .gt;

        // If start positions are equal, compare by end position
        if (self.end < other.end) return .lt;
        if (self.end > other.end) return .gt;

        return .eq;
    }

    /// Check if two spans are equal
    pub fn eql(self: Span, other: Span) bool {
        return self.start == other.start and self.end == other.end;
    }

    /// Calculate a hash for this span (for HashMap usage)
    pub fn hash(self: Span) u64 {
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(std.mem.asBytes(&self.start));
        hasher.update(std.mem.asBytes(&self.end));
        return hasher.final();
    }

    /// Format the span for debugging
    pub fn format(
        self: Span,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("Span({d}..{d})", .{ self.start, self.end });
    }
};

// Tests
const testing = std.testing;

test "Span creation and basic properties" {
    const span = Span.init(10, 20);
    try testing.expectEqual(@as(usize, 10), span.start);
    try testing.expectEqual(@as(usize, 20), span.end);
    try testing.expectEqual(@as(usize, 10), span.len());
    try testing.expect(!span.isEmpty());
}

test "Span point and empty" {
    const point_span = Span.point(15);
    try testing.expectEqual(@as(usize, 15), point_span.start);
    try testing.expectEqual(@as(usize, 15), point_span.end);
    try testing.expectEqual(@as(usize, 0), point_span.len());
    try testing.expect(point_span.isEmpty());

    const empty_span = Span.empty();
    try testing.expectEqual(@as(usize, 0), empty_span.start);
    try testing.expectEqual(@as(usize, 0), empty_span.end);
    try testing.expect(empty_span.isEmpty());
}

test "Span contains" {
    const span = Span.init(10, 20);

    try testing.expect(span.contains(10));
    try testing.expect(span.contains(15));
    try testing.expect(span.contains(19));
    try testing.expect(!span.contains(9));
    try testing.expect(!span.contains(20));
    try testing.expect(!span.contains(25));
}

test "Span containsSpan" {
    const outer = Span.init(10, 30);
    const inner = Span.init(15, 25);
    const overlapping = Span.init(5, 15);
    const outside = Span.init(35, 40);

    try testing.expect(outer.containsSpan(inner));
    try testing.expect(outer.containsSpan(outer)); // Self-containment
    try testing.expect(!outer.containsSpan(overlapping));
    try testing.expect(!outer.containsSpan(outside));
}

test "Span overlaps" {
    const span1 = Span.init(10, 20);
    const span2 = Span.init(15, 25); // Overlaps
    const span3 = Span.init(20, 30); // Adjacent, no overlap
    const span4 = Span.init(5, 15); // Overlaps
    const span5 = Span.init(25, 35); // No overlap

    try testing.expect(span1.overlaps(span2));
    try testing.expect(span2.overlaps(span1)); // Symmetric
    try testing.expect(!span1.overlaps(span3));
    try testing.expect(span1.overlaps(span4));
    try testing.expect(!span1.overlaps(span5));
}

test "Span adjacency and ordering" {
    const span1 = Span.init(10, 20);
    const span2 = Span.init(20, 30); // Adjacent after
    const span3 = Span.init(5, 10); // Adjacent before
    const span4 = Span.init(15, 25); // Overlapping

    try testing.expect(span1.isAdjacent(span2));
    try testing.expect(span2.isAdjacent(span1)); // Symmetric
    try testing.expect(span1.isAdjacent(span3));
    try testing.expect(!span1.isAdjacent(span4));

    try testing.expect(span3.isBefore(span1));
    try testing.expect(!span1.isBefore(span3));
    try testing.expect(span1.isAfter(span3));
    try testing.expect(!span3.isAfter(span1));
}

test "Span merge" {
    const span1 = Span.init(10, 20);
    const span2 = Span.init(15, 25);
    const merged = span1.merge(span2);

    try testing.expectEqual(@as(usize, 10), merged.start);
    try testing.expectEqual(@as(usize, 25), merged.end);

    // Merge with empty
    const empty_span = Span.empty();
    const merged_empty = span1.merge(empty_span);
    try testing.expect(merged_empty.eql(span1));
}

test "Span intersect" {
    const span1 = Span.init(10, 20);
    const span2 = Span.init(15, 25);
    const intersection = span1.intersect(span2);

    try testing.expectEqual(@as(usize, 15), intersection.start);
    try testing.expectEqual(@as(usize, 20), intersection.end);

    // No intersection
    const span3 = Span.init(25, 35);
    const no_intersection = span1.intersect(span3);
    try testing.expect(no_intersection.isEmpty());
}

test "Span extend" {
    const span = Span.init(10, 20);

    // Extend beyond end
    const extended1 = span.extend(25);
    try testing.expectEqual(@as(usize, 10), extended1.start);
    try testing.expectEqual(@as(usize, 26), extended1.end);

    // Extend before start
    const extended2 = span.extend(5);
    try testing.expectEqual(@as(usize, 5), extended2.start);
    try testing.expectEqual(@as(usize, 20), extended2.end);

    // Extend within span (no change)
    const extended3 = span.extend(15);
    try testing.expectEqual(@as(usize, 10), extended3.start);
    try testing.expectEqual(@as(usize, 20), extended3.end);
}

test "Span shift" {
    const span = Span.init(10, 20);

    // Positive shift
    const shifted_pos = span.shift(5);
    try testing.expectEqual(@as(usize, 15), shifted_pos.start);
    try testing.expectEqual(@as(usize, 25), shifted_pos.end);

    // Negative shift
    const shifted_neg = span.shift(-3);
    try testing.expectEqual(@as(usize, 7), shifted_neg.start);
    try testing.expectEqual(@as(usize, 17), shifted_neg.end);

    // Negative shift beyond start (clamp to 0)
    const shifted_clamp = span.shift(-15);
    try testing.expectEqual(@as(usize, 0), shifted_clamp.start);
    try testing.expectEqual(@as(usize, 5), shifted_clamp.end);
}

test "Span getText" {
    const input = "Hello, world! This is a test.";
    const span = Span.init(7, 12); // "world"

    const text = span.getText(input);
    try testing.expectEqualStrings("world", text);

    // Empty span
    const empty_span = Span.empty();
    const empty_text = empty_span.getText(input);
    try testing.expectEqualStrings("", empty_text);

    // Span beyond input
    const beyond_span = Span.init(100, 110);
    const beyond_text = beyond_span.getText(input);
    try testing.expectEqualStrings("", beyond_text);
}

test "Span ordering and equality" {
    const span1 = Span.init(10, 20);
    const span2 = Span.init(10, 20);
    const span3 = Span.init(5, 15);
    const span4 = Span.init(10, 25);

    try testing.expect(span1.eql(span2));
    try testing.expect(!span1.eql(span3));

    try testing.expectEqual(std.math.Order.eq, span1.order(span2));
    try testing.expectEqual(std.math.Order.gt, span1.order(span3));
    try testing.expectEqual(std.math.Order.lt, span1.order(span4));
}

test "Span hash" {
    const span1 = Span.init(10, 20);
    const span2 = Span.init(10, 20);
    const span3 = Span.init(15, 25);

    // Same spans should have same hash
    try testing.expectEqual(span1.hash(), span2.hash());

    // Different spans should have different hashes (very likely)
    try testing.expect(span1.hash() != span3.hash());
}
