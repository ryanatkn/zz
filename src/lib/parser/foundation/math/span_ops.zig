const std = @import("std");
const Span = @import("../types/span.zig").Span;

/// Advanced span operations for complex text manipulation
/// Optimized for performance in stratified parser operations
pub const SpanOps = struct {
    
    /// Find the minimal span that contains all given spans
    pub fn unionOf(spans: []const Span) Span {
        if (spans.len == 0) return Span.empty();
        
        var result = spans[0];
        for (spans[1..]) |span| {
            result = result.merge(span);
        }
        return result;
    }
    
    /// Find the intersection of multiple spans
    /// Returns empty span if no intersection exists
    pub fn intersection(spans: []const Span) Span {
        if (spans.len == 0) return Span.empty();
        
        var result = spans[0];
        for (spans[1..]) |span| {
            result = result.intersect(span);
            if (result.isEmpty()) break;
        }
        return result;
    }
    
    /// Split a span at specific positions
    /// Returns an array of spans representing the split regions
    pub fn split(span: Span, positions: []const usize, allocator: std.mem.Allocator) ![]Span {
        if (positions.len == 0) {
            const result = try allocator.alloc(Span, 1);
            result[0] = span;
            return result;
        }
        
        // Sort positions to ensure correct order
        const sorted_positions = try allocator.dupe(usize, positions);
        defer allocator.free(sorted_positions);
        std.sort.heap(usize, sorted_positions, {}, lessThan);
        
        var result = std.ArrayList(Span).init(allocator);
        defer result.deinit();
        
        var current_start = span.start;
        
        for (sorted_positions) |pos| {
            // Skip positions outside the span
            if (pos <= span.start or pos >= span.end) continue;
            
            // Add span from current start to this position
            if (current_start < pos) {
                try result.append(Span.init(current_start, pos));
            }
            current_start = pos;
        }
        
        // Add final span if there's remaining content
        if (current_start < span.end) {
            try result.append(Span.init(current_start, span.end));
        }
        
        return result.toOwnedSlice();
    }
    
    /// Find gaps between spans in a sorted array
    /// Returns spans representing the gaps
    pub fn findGaps(spans: []const Span, container: Span, allocator: std.mem.Allocator) ![]Span {
        if (spans.len == 0) {
            const result = try allocator.alloc(Span, 1);
            result[0] = container;
            return result;
        }
        
        var result = std.ArrayList(Span).init(allocator);
        defer result.deinit();
        
        var current_pos = container.start;
        
        for (spans) |span| {
            // Skip spans outside container
            if (span.end <= container.start or span.start >= container.end) continue;
            
            // Clamp span to container
            const clamped_start = @max(span.start, container.start);
            const clamped_end = @min(span.end, container.end);
            
            // Add gap before this span
            if (current_pos < clamped_start) {
                try result.append(Span.init(current_pos, clamped_start));
            }
            
            current_pos = @max(current_pos, clamped_end);
        }
        
        // Add final gap
        if (current_pos < container.end) {
            try result.append(Span.init(current_pos, container.end));
        }
        
        return result.toOwnedSlice();
    }
    
    /// Merge overlapping spans in a sorted array
    /// Returns a new array with overlapping spans merged
    pub fn mergeOverlapping(spans: []const Span, allocator: std.mem.Allocator) ![]Span {
        if (spans.len <= 1) return allocator.dupe(Span, spans);
        
        // Sort spans by start position
        const sorted_spans = try allocator.dupe(Span, spans);
        defer allocator.free(sorted_spans);
        std.sort.heap(Span, sorted_spans, {}, spanLessThan);
        
        var result = std.ArrayList(Span).init(allocator);
        defer result.deinit();
        
        var current = sorted_spans[0];
        
        for (sorted_spans[1..]) |span| {
            if (current.overlaps(span) or current.isAdjacent(span)) {
                // Merge with current span
                current = current.merge(span);
            } else {
                // Add current span and start new one
                try result.append(current);
                current = span;
            }
        }
        
        // Add final span
        try result.append(current);
        
        return result.toOwnedSlice();
    }
    
    /// Remove spans from a container span
    /// Returns array of remaining spans after removal
    pub fn subtract(container: Span, to_remove: []const Span, allocator: std.mem.Allocator) ![]Span {
        if (to_remove.len == 0) {
            const result = try allocator.alloc(Span, 1);
            result[0] = container;
            return result;
        }
        
        // Start with the container span
        var remaining = std.ArrayList(Span).init(allocator);
        defer remaining.deinit();
        try remaining.append(container);
        
        // Remove each span one by one
        for (to_remove) |remove_span| {
            var new_remaining = std.ArrayList(Span).init(allocator);
            defer new_remaining.deinit();
            
            for (remaining.items) |current_span| {
                const parts = try subtractSingle(current_span, remove_span, allocator);
                defer allocator.free(parts);
                
                for (parts) |part| {
                    try new_remaining.append(part);
                }
            }
            
            // Replace remaining with new_remaining
            remaining.clearAndFree();
            try remaining.appendSlice(new_remaining.items);
        }
        
        return remaining.toOwnedSlice();
    }
    
    /// Helper function to subtract a single span from another
    fn subtractSingle(span: Span, to_remove: Span, allocator: std.mem.Allocator) ![]Span {
        if (!span.overlaps(to_remove)) {
            // No overlap, return original span
            const result = try allocator.alloc(Span, 1);
            result[0] = span;
            return result;
        }
        
        var result = std.ArrayList(Span).init(allocator);
        defer result.deinit();
        
        // Add part before the removed span
        if (span.start < to_remove.start) {
            const before_end = @min(to_remove.start, span.end);
            try result.append(Span.init(span.start, before_end));
        }
        
        // Add part after the removed span
        if (span.end > to_remove.end) {
            const after_start = @max(to_remove.end, span.start);
            try result.append(Span.init(after_start, span.end));
        }
        
        return result.toOwnedSlice();
    }
    
    /// Expand spans by a given amount in both directions
    pub fn expand(spans: []const Span, amount: usize, allocator: std.mem.Allocator) ![]Span {
        var result = try allocator.alloc(Span, spans.len);
        
        for (spans, 0..) |span, i| {
            const new_start = if (span.start >= amount) span.start - amount else 0;
            const new_end = span.end + amount;
            result[i] = Span.init(new_start, new_end);
        }
        
        return result;
    }
    
    /// Contract spans by a given amount from both directions
    pub fn contract(spans: []const Span, amount: usize, allocator: std.mem.Allocator) ![]Span {
        var result = std.ArrayList(Span).init(allocator);
        defer result.deinit();
        
        for (spans) |span| {
            if (span.len() <= amount * 2) {
                // Span too small to contract, skip or make empty
                continue;
            }
            
            const new_start = span.start + amount;
            const new_end = span.end - amount;
            
            if (new_start < new_end) {
                try result.append(Span.init(new_start, new_end));
            }
        }
        
        return result.toOwnedSlice();
    }
    
    /// Filter spans by a predicate function
    pub fn filter(
        spans: []const Span,
        predicate: fn(span: Span) bool,
        allocator: std.mem.Allocator,
    ) ![]Span {
        var result = std.ArrayList(Span).init(allocator);
        defer result.deinit();
        
        for (spans) |span| {
            if (predicate(span)) {
                try result.append(span);
            }
        }
        
        return result.toOwnedSlice();
    }
    
    /// Map spans through a transformation function
    pub fn map(
        spans: []const Span,
        transform: fn(span: Span) Span,
        allocator: std.mem.Allocator,
    ) ![]Span {
        var result = try allocator.alloc(Span, spans.len);
        
        for (spans, 0..) |span, i| {
            result[i] = transform(span);
        }
        
        return result;
    }
    
    /// Find the closest span to a given position
    pub fn findClosest(spans: []const Span, position: usize) ?Span {
        if (spans.len == 0) return null;
        
        var closest = spans[0];
        var min_distance = distanceToPosition(closest, position);
        
        for (spans[1..]) |span| {
            const distance = distanceToPosition(span, position);
            if (distance < min_distance) {
                min_distance = distance;
                closest = span;
            }
        }
        
        return closest;
    }
    
    /// Calculate distance from a span to a position
    fn distanceToPosition(span: Span, position: usize) usize {
        if (span.contains(position)) return 0;
        if (position < span.start) return span.start - position;
        return position - span.end;
    }
    
    /// Sort spans by start position
    pub fn sortByStart(spans: []Span) void {
        std.sort.heap(Span, spans, {}, spanLessThan);
    }
    
    /// Sort spans by length (shortest first)
    pub fn sortByLength(spans: []Span) void {
        std.sort.heap(Span, spans, {}, spanLengthLessThan);
    }
};

fn lessThan(context: void, a: usize, b: usize) bool {
    _ = context;
    return a < b;
}

fn spanLessThan(context: void, a: Span, b: Span) bool {
    _ = context;
    return a.order(b) == .lt;
}

fn spanLengthLessThan(context: void, a: Span, b: Span) bool {
    _ = context;
    return a.len() < b.len();
}

// Utility functions for common predicates
pub fn isNonEmpty(span: Span) bool {
    return !span.isEmpty();
}

pub fn isLongerThan5(span: Span) bool {
    return span.len() > 5;
}

pub fn isLongerThan3(span: Span) bool {
    return span.len() > 3;
}

// Tests
const testing = std.testing;

test "SpanOps unionOf" {
    const spans = [_]Span{
        Span.init(10, 20),
        Span.init(15, 30),
        Span.init(5, 12),
    };
    
    const result = SpanOps.unionOf(&spans);
    try testing.expectEqual(@as(usize, 5), result.start);
    try testing.expectEqual(@as(usize, 30), result.end);
}

test "SpanOps intersection" {
    const spans = [_]Span{
        Span.init(10, 30),
        Span.init(15, 25),
        Span.init(12, 22),
    };
    
    const result = SpanOps.intersection(&spans);
    try testing.expectEqual(@as(usize, 15), result.start);
    try testing.expectEqual(@as(usize, 22), result.end);
    
    // Test no intersection
    const no_intersection = [_]Span{
        Span.init(10, 20),
        Span.init(25, 35),
    };
    
    const empty_result = SpanOps.intersection(&no_intersection);
    try testing.expect(empty_result.isEmpty());
}

test "SpanOps split" {
    const span = Span.init(10, 30);
    const positions = [_]usize{ 15, 25 };
    
    const result = try SpanOps.split(span, &positions, testing.allocator);
    defer testing.allocator.free(result);
    
    try testing.expectEqual(@as(usize, 3), result.len);
    try testing.expect(result[0].eql(Span.init(10, 15)));
    try testing.expect(result[1].eql(Span.init(15, 25)));
    try testing.expect(result[2].eql(Span.init(25, 30)));
}

test "SpanOps findGaps" {
    const spans = [_]Span{
        Span.init(10, 15),
        Span.init(20, 25),
        Span.init(30, 35),
    };
    const container = Span.init(5, 40);
    
    const gaps = try SpanOps.findGaps(&spans, container, testing.allocator);
    defer testing.allocator.free(gaps);
    
    try testing.expectEqual(@as(usize, 4), gaps.len);
    try testing.expect(gaps[0].eql(Span.init(5, 10)));   // Before first span
    try testing.expect(gaps[1].eql(Span.init(15, 20)));  // Between first and second
    try testing.expect(gaps[2].eql(Span.init(25, 30)));  // Between second and third
    try testing.expect(gaps[3].eql(Span.init(35, 40)));  // After last span
}

test "SpanOps mergeOverlapping" {
    const spans = [_]Span{
        Span.init(10, 20),
        Span.init(15, 25),  // Overlaps with first
        Span.init(30, 40),  // Separate
        Span.init(35, 45),  // Overlaps with third
    };
    
    const merged = try SpanOps.mergeOverlapping(&spans, testing.allocator);
    defer testing.allocator.free(merged);
    
    try testing.expectEqual(@as(usize, 2), merged.len);
    try testing.expect(merged[0].eql(Span.init(10, 25)));
    try testing.expect(merged[1].eql(Span.init(30, 45)));
}

test "SpanOps subtract" {
    const container = Span.init(10, 50);
    const to_remove = [_]Span{
        Span.init(15, 20),
        Span.init(30, 35),
    };
    
    const remaining = try SpanOps.subtract(container, &to_remove, testing.allocator);
    defer testing.allocator.free(remaining);
    
    try testing.expectEqual(@as(usize, 3), remaining.len);
    try testing.expect(remaining[0].eql(Span.init(10, 15)));
    try testing.expect(remaining[1].eql(Span.init(20, 30)));
    try testing.expect(remaining[2].eql(Span.init(35, 50)));
}

test "SpanOps expand and contract" {
    const spans = [_]Span{
        Span.init(10, 20),
        Span.init(30, 40),
    };
    
    // Test expand
    const expanded = try SpanOps.expand(&spans, 5, testing.allocator);
    defer testing.allocator.free(expanded);
    
    try testing.expectEqual(@as(usize, 2), expanded.len);
    try testing.expect(expanded[0].eql(Span.init(5, 25)));
    try testing.expect(expanded[1].eql(Span.init(25, 45)));
    
    // Test contract
    const large_spans = [_]Span{
        Span.init(10, 30),  // 20 chars, contracts to 10 chars
        Span.init(40, 50),  // 10 chars, contracts to 0 chars (filtered out)
    };
    
    const contracted = try SpanOps.contract(&large_spans, 5, testing.allocator);
    defer testing.allocator.free(contracted);
    
    try testing.expectEqual(@as(usize, 1), contracted.len);
    try testing.expect(contracted[0].eql(Span.init(15, 25)));
}

test "SpanOps findClosest" {
    const spans = [_]Span{
        Span.init(10, 20),
        Span.init(30, 40),
        Span.init(50, 60),
    };
    
    // Position inside first span
    const closest1 = SpanOps.findClosest(&spans, 15);
    try testing.expect(closest1.?.eql(Span.init(10, 20)));
    
    // Position between first and second span
    const closest2 = SpanOps.findClosest(&spans, 25);
    try testing.expect(closest2.?.eql(Span.init(10, 20))); // Closer to first
    
    // Position equidistant from second and third spans (returns first found)
    const closest3 = SpanOps.findClosest(&spans, 45);
    try testing.expect(closest3.?.eql(Span.init(30, 40)));
}

test "SpanOps filter" {
    const spans = [_]Span{
        Span.init(10, 12),  // Length 2
        Span.init(20, 25),  // Length 5
        Span.init(30, 32),  // Length 2
        Span.init(40, 50),  // Length 10
    };
    
    // Filter spans longer than 3 characters
    const long_spans = try SpanOps.filter(&spans, isLongerThan3, testing.allocator);
    defer testing.allocator.free(long_spans);
    
    try testing.expectEqual(@as(usize, 2), long_spans.len);
    try testing.expect(long_spans[0].eql(Span.init(20, 25)));
    try testing.expect(long_spans[1].eql(Span.init(40, 50)));
}

test "SpanOps map" {
    const spans = [_]Span{
        Span.init(10, 20),
        Span.init(30, 40),
    };
    
    const shift_by_5 = struct {
        fn transform(span: Span) Span {
            return span.shift(5);
        }
    }.transform;
    
    const shifted = try SpanOps.map(&spans, shift_by_5, testing.allocator);
    defer testing.allocator.free(shifted);
    
    try testing.expectEqual(@as(usize, 2), shifted.len);
    try testing.expect(shifted[0].eql(Span.init(15, 25)));
    try testing.expect(shifted[1].eql(Span.init(35, 45)));
}

test "SpanOps sorting" {
    var spans = [_]Span{
        Span.init(30, 40),  // Start: 30, Length: 10
        Span.init(10, 15),  // Start: 10, Length: 5
        Span.init(20, 25),  // Start: 20, Length: 5
    };
    
    // Sort by start position
    SpanOps.sortByStart(&spans);
    try testing.expect(spans[0].eql(Span.init(10, 15)));
    try testing.expect(spans[1].eql(Span.init(20, 25)));
    try testing.expect(spans[2].eql(Span.init(30, 40)));
    
    // Sort by length
    SpanOps.sortByLength(&spans);
    try testing.expect(spans[0].eql(Span.init(10, 15))); // Length 5
    try testing.expect(spans[1].eql(Span.init(20, 25))); // Length 5
    try testing.expect(spans[2].eql(Span.init(30, 40))); // Length 10
}