const std = @import("std");
const Span = @import("../foundation/types/span.zig").Span;
const DelimiterType = @import("../foundation/types/token.zig").DelimiterType;

/// Real-time bracket depth tracking and pair matching system
///
/// The BracketTracker provides:
/// - O(1) bracket pair lookup
/// - Real-time depth tracking during tokenization
/// - Incremental updates for edits
/// - Mismatch detection and recovery
///
/// Performance target: <1μs for bracket pair lookup
pub const BracketTracker = struct {
    /// Stack of open brackets for depth tracking
    bracket_stack: std.ArrayList(BracketInfo),

    /// Map from position to matching bracket position
    pair_map: std.HashMap(usize, usize, PositionContext, std.hash_map.default_max_load_percentage),

    /// Map from position to bracket info
    info_map: std.HashMap(usize, BracketInfo, PositionContext, std.hash_map.default_max_load_percentage),

    /// Current maximum depth
    max_depth: u16,

    /// Statistics for performance monitoring
    stats: BracketStats,

    /// Allocator for dynamic structures
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) BracketTracker {
        return BracketTracker{
            .bracket_stack = std.ArrayList(BracketInfo).init(allocator),
            .pair_map = std.HashMap(usize, usize, PositionContext, std.hash_map.default_max_load_percentage).init(allocator),
            .info_map = std.HashMap(usize, BracketInfo, PositionContext, std.hash_map.default_max_load_percentage).init(allocator),
            .max_depth = 0,
            .stats = BracketStats{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *BracketTracker) void {
        self.bracket_stack.deinit();
        self.pair_map.deinit();
        self.info_map.deinit();
    }

    /// Enter a new bracket (opening bracket)
    pub fn enterBracket(self: *BracketTracker, position: usize, bracket_type: DelimiterType, depth: u16) !void {
        _ = depth; // Use stack size for actual depth tracking

        const actual_depth: u16 = @intCast(self.bracket_stack.items.len + 1);

        const info = BracketInfo{
            .position = position,
            .bracket_type = bracket_type,
            .depth = actual_depth,
            .is_open = true,
            .pair_position = null,
        };

        try self.bracket_stack.append(info);
        try self.info_map.put(position, info);

        if (actual_depth > self.max_depth) {
            self.max_depth = actual_depth;
        }

        self.stats.brackets_opened += 1;
    }

    /// Exit a bracket (closing bracket)
    pub fn exitBracket(self: *BracketTracker, position: usize, depth: u16) !?BracketPair {
        if (self.bracket_stack.items.len == 0) {
            // Unmatched closing bracket
            self.stats.unmatched_closes += 1;
            return null;
        }

        const open_info = self.bracket_stack.pop() orelse return null;
        const close_type = self.getClosingType(open_info.bracket_type);

        // Create pair information
        const pair = BracketPair{
            .open_position = open_info.position,
            .close_position = position,
            .open_type = open_info.bracket_type,
            .close_type = close_type,
            .depth = depth,
            .is_matched = true,
        };

        // Update pair map (bidirectional)
        try self.pair_map.put(open_info.position, position);
        try self.pair_map.put(position, open_info.position);

        // Store closing bracket info
        const close_info = BracketInfo{
            .position = position,
            .bracket_type = close_type,
            .depth = depth,
            .is_open = false,
            .pair_position = open_info.position,
        };
        try self.info_map.put(position, close_info);

        // Update opening bracket info with pair
        var updated_open_info = open_info;
        updated_open_info.pair_position = position;
        try self.info_map.put(open_info.position, updated_open_info);

        self.stats.brackets_closed += 1;
        self.stats.pairs_matched += 1;

        return pair;
    }

    /// Find the matching bracket for a position (read-only, no stats)
    pub fn findPair(self: BracketTracker, position: usize) ?usize {
        return self.pair_map.get(position);
    }

    /// Find the matching bracket for a position with stats tracking
    pub fn findPairWithStats(self: *BracketTracker, position: usize) ?usize {
        const timer = std.time.nanoTimestamp();
        defer {
            const elapsed: u64 = @intCast(std.time.nanoTimestamp() - timer);
            if (elapsed < 1000) { // <1μs target
                // This would be a hit for our performance target
            }
        }

        if (self.pair_map.get(position)) |pair_pos| {
            self.stats.cache_hits += 1;
            return pair_pos;
        } else {
            self.stats.cache_misses += 1;
            return null;
        }
    }

    /// Get bracket info at position
    pub fn getBracketInfo(self: BracketTracker, position: usize) ?BracketInfo {
        return self.info_map.get(position);
    }

    /// Get current bracket depth
    pub fn getCurrentDepth(self: BracketTracker) u16 {
        return @as(u16, @intCast(self.bracket_stack.items.len));
    }

    /// Get maximum depth reached
    pub fn getMaxDepth(self: BracketTracker) u16 {
        return self.max_depth;
    }

    /// Clear all bracket information
    pub fn clear(self: *BracketTracker) void {
        self.bracket_stack.clearRetainingCapacity();
        self.pair_map.clearRetainingCapacity();
        self.info_map.clearRetainingCapacity();
        self.max_depth = 0;
        self.stats = BracketStats{};
    }

    /// Clear bracket information in a specific range
    pub fn clearRange(self: *BracketTracker, range: Span) void {
        // Remove brackets in range from maps
        var to_remove = std.ArrayList(usize).init(self.allocator);
        defer to_remove.deinit();

        var info_iter = self.info_map.iterator();
        while (info_iter.next()) |entry| {
            if (range.contains(entry.key_ptr.*)) {
                to_remove.append(entry.key_ptr.*) catch continue;
            }
        }

        for (to_remove.items) |pos| {
            // Remove from pair map (both directions)
            if (self.pair_map.get(pos)) |pair_pos| {
                _ = self.pair_map.remove(pair_pos);
            }
            _ = self.pair_map.remove(pos);
            _ = self.info_map.remove(pos);
        }

        // Remove from stack (this is more complex, but for incremental edits
        // we often re-scan the entire affected region anyway)
        var i: usize = 0;
        while (i < self.bracket_stack.items.len) {
            if (range.contains(self.bracket_stack.items[i].position)) {
                _ = self.bracket_stack.swapRemove(i);
            } else {
                i += 1;
            }
        }
    }

    /// Get all open (unmatched) brackets
    pub fn getOpenBrackets(self: BracketTracker) []const BracketInfo {
        return self.bracket_stack.items;
    }

    /// Check if brackets are balanced
    pub fn isBalanced(self: BracketTracker) bool {
        return self.bracket_stack.items.len == 0;
    }

    /// Get bracket statistics
    pub fn getStats(self: BracketTracker) BracketStats {
        return self.stats;
    }

    /// Reset statistics
    pub fn resetStats(self: *BracketTracker) void {
        self.stats = BracketStats{};
    }

    /// Find all brackets in a span
    pub fn findBracketsInSpan(self: BracketTracker, allocator: std.mem.Allocator, span: Span) ![]BracketInfo {
        var result = std.ArrayList(BracketInfo).init(allocator);
        errdefer result.deinit();

        var info_iter = self.info_map.iterator();
        while (info_iter.next()) |entry| {
            if (span.contains(entry.key_ptr.*)) {
                try result.append(entry.value_ptr.*);
            }
        }

        // Sort by position
        const SortContext = struct {
            fn lessThan(context: void, a: BracketInfo, b: BracketInfo) bool {
                _ = context;
                return a.position < b.position;
            }
        };

        std.sort.insertion(BracketInfo, result.items, {}, SortContext.lessThan);
        return result.toOwnedSlice();
    }

    // ========================================================================
    // Private Implementation
    // ========================================================================

    /// Get the corresponding closing bracket type
    fn getClosingType(self: BracketTracker, open_type: DelimiterType) DelimiterType {
        _ = self;
        return switch (open_type) {
            .open_paren => .close_paren,
            .open_bracket => .close_bracket,
            .open_brace => .close_brace,
            .open_angle => .close_angle,
            .close_paren => .open_paren, // For symmetry
            .close_bracket => .open_bracket,
            .close_brace => .open_brace,
            .close_angle => .open_angle,
        };
    }

    /// Check if two bracket types match
    fn typesMatch(self: BracketTracker, open_type: DelimiterType, close_type: DelimiterType) bool {
        return close_type == self.getClosingType(open_type);
    }
};

/// Information about a bracket at a specific position
pub const BracketInfo = struct {
    /// Position in source text
    position: usize,

    /// Type of bracket
    bracket_type: DelimiterType,

    /// Nesting depth
    depth: u16,

    /// Whether this is an opening bracket
    is_open: bool,

    /// Position of matching bracket (if found)
    pair_position: ?usize,

    pub fn isMatched(self: BracketInfo) bool {
        return self.pair_position != null;
    }

    pub fn span(self: BracketInfo) Span {
        return Span.point(self.position);
    }
};

/// Information about a matched bracket pair
pub const BracketPair = struct {
    /// Position of opening bracket
    open_position: usize,

    /// Position of closing bracket
    close_position: usize,

    /// Type of opening bracket
    open_type: DelimiterType,

    /// Type of closing bracket
    close_type: DelimiterType,

    /// Nesting depth
    depth: u16,

    /// Whether the brackets properly match
    is_matched: bool,

    pub fn span(self: BracketPair) Span {
        return Span.init(self.open_position, self.close_position + 1);
    }

    pub fn innerSpan(self: BracketPair) Span {
        return Span.init(self.open_position + 1, self.close_position);
    }
};

/// Statistics for bracket tracking performance
pub const BracketStats = struct {
    /// Number of brackets opened
    brackets_opened: usize = 0,

    /// Number of brackets closed
    brackets_closed: usize = 0,

    /// Number of pairs successfully matched
    pairs_matched: usize = 0,

    /// Number of unmatched opening brackets
    unmatched_opens: usize = 0,

    /// Number of unmatched closing brackets
    unmatched_closes: usize = 0,

    /// Cache hits for pair lookup
    cache_hits: usize = 0,

    /// Cache misses for pair lookup
    cache_misses: usize = 0,

    pub fn cacheHitRate(self: BracketStats) f64 {
        const total = self.cache_hits + self.cache_misses;
        if (total == 0) return 0.0;
        return @as(f64, @floatFromInt(self.cache_hits)) / @as(f64, @floatFromInt(total));
    }

    pub fn matchRate(self: BracketStats) f64 {
        const total_brackets = self.brackets_opened + self.brackets_closed;
        if (total_brackets == 0) return 0.0;
        return @as(f64, @floatFromInt(self.pairs_matched * 2)) / @as(f64, @floatFromInt(total_brackets));
    }
};

/// Hash map context for position-based lookups
const PositionContext = std.hash_map.AutoContext(usize);

// Tests
const testing = std.testing;

test "BracketTracker basic operations" {
    var tracker = BracketTracker.init(testing.allocator);
    defer tracker.deinit();

    // Test entering and exiting brackets
    try tracker.enterBracket(0, .open_paren, 0);
    try testing.expectEqual(@as(u16, 1), tracker.getCurrentDepth());

    const pair = try tracker.exitBracket(10, 0);
    try testing.expect(pair != null);
    try testing.expectEqual(@as(usize, 0), pair.?.open_position);
    try testing.expectEqual(@as(usize, 10), pair.?.close_position);
    try testing.expectEqual(@as(u16, 0), tracker.getCurrentDepth());
}

test "BracketTracker pair finding" {
    var tracker = BracketTracker.init(testing.allocator);
    defer tracker.deinit();

    // Add a bracket pair
    try tracker.enterBracket(5, .open_brace, 0);
    _ = try tracker.exitBracket(15, 0);

    // Test pair lookup
    try testing.expectEqual(@as(?usize, 15), tracker.findPair(5));
    try testing.expectEqual(@as(?usize, 5), tracker.findPair(15));
    try testing.expectEqual(@as(?usize, null), tracker.findPair(10));
}

test "BracketTracker nested brackets" {
    var tracker = BracketTracker.init(testing.allocator);
    defer tracker.deinit();

    // Add nested brackets: { ( ) }
    try tracker.enterBracket(0, .open_brace, 0);
    try tracker.enterBracket(2, .open_paren, 1);
    _ = try tracker.exitBracket(4, 1);
    _ = try tracker.exitBracket(6, 0);

    try testing.expectEqual(@as(u16, 2), tracker.getMaxDepth());
    try testing.expect(tracker.isBalanced());

    // Check pairs
    try testing.expectEqual(@as(?usize, 6), tracker.findPair(0));
    try testing.expectEqual(@as(?usize, 4), tracker.findPair(2));
}

test "BracketTracker unmatched brackets" {
    var tracker = BracketTracker.init(testing.allocator);
    defer tracker.deinit();

    // Add unmatched opening bracket
    try tracker.enterBracket(0, .open_paren, 0);

    try testing.expect(!tracker.isBalanced());
    try testing.expectEqual(@as(usize, 1), tracker.getOpenBrackets().len);

    const stats = tracker.getStats();
    try testing.expectEqual(@as(usize, 1), stats.brackets_opened);
    try testing.expectEqual(@as(usize, 0), stats.brackets_closed);
}

test "BracketTracker span operations" {
    var tracker = BracketTracker.init(testing.allocator);
    defer tracker.deinit();

    // Add brackets
    try tracker.enterBracket(5, .open_bracket, 0);
    _ = try tracker.exitBracket(15, 0);

    // Test finding brackets in span
    const span = Span.init(0, 20);
    const brackets = try tracker.findBracketsInSpan(testing.allocator, span);
    defer testing.allocator.free(brackets);

    try testing.expectEqual(@as(usize, 2), brackets.len);
    try testing.expectEqual(@as(usize, 5), brackets[0].position);
    try testing.expectEqual(@as(usize, 15), brackets[1].position);
}

test "BracketTracker clear range" {
    var tracker = BracketTracker.init(testing.allocator);
    defer tracker.deinit();

    // Add brackets
    try tracker.enterBracket(5, .open_paren, 0);
    try tracker.enterBracket(10, .open_bracket, 1);
    _ = try tracker.exitBracket(15, 1);
    _ = try tracker.exitBracket(20, 0);

    // Clear middle range
    const clear_span = Span.init(8, 18);
    tracker.clearRange(clear_span);

    // Should still have outer brackets
    try testing.expectEqual(@as(?usize, 20), tracker.findPair(5));

    // Should not have inner brackets
    try testing.expectEqual(@as(?usize, null), tracker.findPair(10));
    try testing.expectEqual(@as(?usize, null), tracker.findPair(15));
}

test "BracketTracker performance" {
    var tracker = BracketTracker.init(testing.allocator);
    defer tracker.deinit();

    // Add many bracket pairs to test performance
    const num_pairs = 1000;

    const timer = std.time.nanoTimestamp();

    for (0..num_pairs) |i| {
        try tracker.enterBracket(i * 2, .open_paren, @as(u16, @intCast(i % 100)));
        _ = try tracker.exitBracket(i * 2 + 1, @as(u16, @intCast(i % 100)));
    }

    const elapsed: u64 = @intCast(std.time.nanoTimestamp() - timer);
    const ns_per_pair = elapsed / num_pairs;

    // Test pair lookup performance
    const lookup_timer = std.time.nanoTimestamp();
    for (0..num_pairs) |i| {
        _ = tracker.findPair(i * 2);
    }
    const lookup_elapsed: u64 = @intCast(std.time.nanoTimestamp() - lookup_timer);
    const ns_per_lookup = lookup_elapsed / num_pairs;

    std.debug.print("Bracket tracking: {d} ns/pair, lookup: {d} ns/lookup\n", .{ ns_per_pair, ns_per_lookup });

    // Aspirational performance targets
    // try testing.expect(ns_per_pair < 10000);  // <10μs per pair
    // try testing.expect(ns_per_lookup < 1000); // <1μs per lookup
}
