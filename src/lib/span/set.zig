const std = @import("std");
const Span = @import("span.zig").Span;

/// Collection of spans with normalization (merging overlapping spans)
/// Used for tracking multiple selections, highlights, etc.
pub const SpanSet = struct {
    spans: std.ArrayList(Span),
    normalized: bool,

    /// Initialize a new empty span set
    pub fn init(allocator: std.mem.Allocator) SpanSet {
        return .{
            .spans = std.ArrayList(Span).init(allocator),
            .normalized = true,
        };
    }

    /// Deinitialize and free memory
    pub fn deinit(self: *SpanSet) void {
        self.spans.deinit();
    }

    /// Add a span to the set
    pub fn add(self: *SpanSet, span: Span) !void {
        if (span.isEmpty()) return;
        try self.spans.append(span);
        self.normalized = false;
    }

    /// Add multiple spans at once
    pub fn addMany(self: *SpanSet, spans: []const Span) !void {
        for (spans) |span| {
            try self.add(span);
        }
    }

    /// Remove spans that overlap with the given span
    pub fn remove(self: *SpanSet, span: Span) void {
        var i: usize = 0;
        while (i < self.spans.items.len) {
            if (self.spans.items[i].overlaps(span)) {
                _ = self.spans.swapRemove(i);
            } else {
                i += 1;
            }
        }
    }

    /// Clear all spans
    pub fn clear(self: *SpanSet) void {
        self.spans.clearRetainingCapacity();
        self.normalized = true;
    }

    /// Get the number of spans (before normalization)
    pub fn count(self: SpanSet) usize {
        return self.spans.items.len;
    }

    /// Check if set is empty
    pub fn isEmpty(self: SpanSet) bool {
        return self.spans.items.len == 0;
    }

    /// Normalize the set by merging overlapping spans
    pub fn normalize(self: *SpanSet) void {
        if (self.normalized or self.spans.items.len < 2) {
            self.normalized = true;
            return;
        }

        // Sort spans by start position
        std.sort.insertion(Span, self.spans.items, {}, compareSpans);

        // Merge overlapping spans
        var write_idx: usize = 0;
        var current = self.spans.items[0];

        for (self.spans.items[1..]) |span| {
            if (current.end >= span.start) {
                // Overlapping or adjacent - merge
                current.end = @max(current.end, span.end);
            } else {
                // Non-overlapping - save current and move to next
                self.spans.items[write_idx] = current;
                write_idx += 1;
                current = span;
            }
        }

        // Save the last span
        self.spans.items[write_idx] = current;
        write_idx += 1;

        // Truncate to actual size
        self.spans.shrinkRetainingCapacity(write_idx);
        self.normalized = true;
    }

    /// Get normalized spans (merges overlapping)
    pub fn getNormalized(self: *SpanSet) []Span {
        self.normalize();
        return self.spans.items;
    }

    /// Check if a position is contained in any span
    pub fn contains(self: *SpanSet, pos: u32) bool {
        self.normalize();
        for (self.spans.items) |span| {
            if (span.contains(pos)) return true;
        }
        return false;
    }

    /// Check if a span overlaps with any span in the set
    pub fn overlaps(self: *SpanSet, span: Span) bool {
        for (self.spans.items) |s| {
            if (s.overlaps(span)) return true;
        }
        return false;
    }

    /// Get the union of all spans as a single span
    pub fn getUnion(self: *SpanSet) ?Span {
        if (self.spans.items.len == 0) return null;
        
        self.normalize();
        const first = self.spans.items[0];
        const last = self.spans.items[self.spans.items.len - 1];
        return Span.init(first.start, last.end);
    }

    /// Get total coverage (sum of all span lengths after normalization)
    pub fn getTotalCoverage(self: *SpanSet) u32 {
        self.normalize();
        var total: u32 = 0;
        for (self.spans.items) |span| {
            total += span.len();
        }
        return total;
    }

    fn compareSpans(_: void, a: Span, b: Span) bool {
        return a.start < b.start;
    }
};

// Tests
test "SpanSet normalization" {
    var set = SpanSet.init(std.testing.allocator);
    defer set.deinit();

    // Add overlapping spans
    try set.add(Span.init(0, 10));
    try set.add(Span.init(5, 15));
    try set.add(Span.init(20, 30));
    try set.add(Span.init(25, 35));

    const normalized = set.getNormalized();
    try std.testing.expectEqual(@as(usize, 2), normalized.len);
    try std.testing.expectEqual(Span.init(0, 15), normalized[0]);
    try std.testing.expectEqual(Span.init(20, 35), normalized[1]);
}

test "SpanSet operations" {
    var set = SpanSet.init(std.testing.allocator);
    defer set.deinit();

    try set.add(Span.init(10, 20));
    try set.add(Span.init(30, 40));

    try std.testing.expect(set.contains(15));
    try std.testing.expect(!set.contains(25));
    try std.testing.expect(set.contains(35));

    try std.testing.expectEqual(@as(u32, 20), set.getTotalCoverage());
}