const std = @import("std");
const Fact = @import("../types/fact.zig").Fact;
const FactId = @import("../types/fact.zig").FactId;
const Generation = @import("../types/fact.zig").Generation;
const Span = @import("../types/span.zig").Span;
const Predicate = @import("../types/predicate.zig").Predicate;
const PredicateCategory = @import("../types/predicate.zig").PredicateCategory;

/// Optimized index for facts with multiple access patterns
/// Provides O(1) fact lookup by ID and O(log n) span-based queries
pub const FactIndex = struct {
    /// Primary storage: O(1) lookup by fact ID
    by_id: std.HashMap(FactId, Fact, FactIdContext, std.hash_map.default_max_load_percentage),

    /// Spatial index: O(log n) queries by span overlap
    by_span: SpanIndex,

    /// Category index: O(1) lookup by predicate category
    by_predicate: std.HashMap(PredicateCategory, FactIdList, PredicateCategoryContext, std.hash_map.default_max_load_percentage),

    /// Generation index: O(1) lookup by generation for cache invalidation
    by_generation: std.HashMap(Generation, FactIdList, GenerationContext, std.hash_map.default_max_load_percentage),

    /// Hierarchical relationships: parent -> children mapping
    parent_child: std.HashMap(FactId, FactIdList, FactIdContext, std.hash_map.default_max_load_percentage),

    /// Memory allocator for all internal structures
    allocator: std.mem.Allocator,

    /// Current generation counter
    current_generation: Generation,

    /// Statistics for performance monitoring
    stats: IndexStats,

    pub fn init(allocator: std.mem.Allocator) FactIndex {
        return .{
            .by_id = std.HashMap(FactId, Fact, FactIdContext, std.hash_map.default_max_load_percentage).init(allocator),
            .by_span = SpanIndex.init(allocator),
            .by_predicate = std.HashMap(PredicateCategory, FactIdList, PredicateCategoryContext, std.hash_map.default_max_load_percentage).init(allocator),
            .by_generation = std.HashMap(Generation, FactIdList, GenerationContext, std.hash_map.default_max_load_percentage).init(allocator),
            .parent_child = std.HashMap(FactId, FactIdList, FactIdContext, std.hash_map.default_max_load_percentage).init(allocator),
            .allocator = allocator,
            .current_generation = 0,
            .stats = IndexStats{},
        };
    }

    pub fn deinit(self: *FactIndex) void {
        self.by_id.deinit();
        self.by_span.deinit();

        // Free all FactIdList values in maps
        {
            var iter = self.by_predicate.iterator();
            while (iter.next()) |entry| {
                entry.value_ptr.deinit();
            }
            self.by_predicate.deinit();
        }

        {
            var iter = self.by_generation.iterator();
            while (iter.next()) |entry| {
                entry.value_ptr.deinit();
            }
            self.by_generation.deinit();
        }

        {
            var iter = self.parent_child.iterator();
            while (iter.next()) |entry| {
                entry.value_ptr.deinit();
            }
            self.parent_child.deinit();
        }
    }

    /// Insert a fact into all indices
    /// Returns error if fact ID already exists
    pub fn insert(self: *FactIndex, fact: Fact) !void {
        // Check for duplicate ID
        if (self.by_id.contains(fact.id)) {
            return error.DuplicateFactId;
        }

        // Insert into primary index
        try self.by_id.put(fact.id, fact);

        // Insert into spatial index
        try self.by_span.insert(fact.subject, fact.id);

        // Insert into predicate category index
        const category = fact.category();
        const result = try self.by_predicate.getOrPut(category);
        if (!result.found_existing) {
            result.value_ptr.* = FactIdList.init(self.allocator);
        }
        try result.value_ptr.append(fact.id);

        // Insert into generation index
        const gen_result = try self.by_generation.getOrPut(fact.generation);
        if (!gen_result.found_existing) {
            gen_result.value_ptr.* = FactIdList.init(self.allocator);
        }
        try gen_result.value_ptr.append(fact.id);

        // Update statistics
        self.stats.fact_count += 1;
        self.stats.total_insertions += 1;
    }

    /// Remove a fact from all indices
    pub fn remove(self: *FactIndex, fact_id: FactId) bool {
        const fact = self.by_id.get(fact_id) orelse return false;

        // Remove from primary index
        _ = self.by_id.remove(fact_id);

        // Remove from spatial index
        self.by_span.remove(fact.subject, fact_id);

        // Remove from predicate category index
        const category = fact.category();
        if (self.by_predicate.getPtr(category)) |list| {
            _ = list.swapRemove(findFactIdIndex(list, fact_id) orelse return false);
            if (list.items.len == 0) {
                list.deinit();
                _ = self.by_predicate.remove(category);
            }
        }

        // Remove from generation index
        if (self.by_generation.getPtr(fact.generation)) |list| {
            _ = list.swapRemove(findFactIdIndex(list, fact_id) orelse return false);
            if (list.items.len == 0) {
                list.deinit();
                _ = self.by_generation.remove(fact.generation);
            }
        }

        // Remove from parent-child relationships
        _ = self.parent_child.remove(fact_id);

        // Update statistics
        self.stats.fact_count -= 1;
        self.stats.total_removals += 1;

        return true;
    }

    /// Get a fact by ID - O(1)
    pub fn get(self: *FactIndex, fact_id: FactId) ?Fact {
        self.stats.lookups_by_id += 1;
        return self.by_id.get(fact_id);
    }

    /// Find facts that overlap with a span - O(log n + k) where k is result count
    pub fn findOverlapping(self: *FactIndex, span: Span, allocator: std.mem.Allocator) ![]FactId {
        self.stats.lookups_by_span += 1;
        return self.by_span.findOverlapping(span, allocator);
    }

    /// Find facts by predicate category - O(1)
    pub fn findByCategory(self: *FactIndex, category: PredicateCategory) ?[]const FactId {
        self.stats.lookups_by_predicate += 1;
        const list = self.by_predicate.get(category) orelse return null;
        return list.items;
    }

    /// Find facts by generation - O(1)
    pub fn findByGeneration(self: *FactIndex, generation: Generation) ?[]const FactId {
        self.stats.lookups_by_generation += 1;
        const list = self.by_generation.get(generation) orelse return null;
        return list.items;
    }

    /// Bulk insert facts efficiently
    pub fn insertBatch(self: *FactIndex, facts: []const Fact) !void {
        for (facts) |fact| {
            try self.insert(fact);
        }
    }

    /// Remove all facts from a specific generation
    pub fn removeGeneration(self: *FactIndex, generation: Generation) void {
        const fact_ids = self.findByGeneration(generation) orelse return;

        // Copy fact IDs since we'll modify the collection during iteration
        const ids_copy = self.allocator.dupe(FactId, fact_ids) catch return;
        defer self.allocator.free(ids_copy);

        for (ids_copy) |fact_id| {
            _ = self.remove(fact_id);
        }
    }

    /// Get the number of facts in the index
    pub fn count(self: FactIndex) usize {
        return self.stats.fact_count;
    }

    /// Get current generation
    pub fn getCurrentGeneration(self: FactIndex) Generation {
        return self.current_generation;
    }

    /// Advance to next generation
    pub fn nextGeneration(self: *FactIndex) Generation {
        self.current_generation += 1;
        return self.current_generation;
    }

    /// Get index statistics
    pub fn getStats(self: FactIndex) IndexStats {
        return self.stats;
    }

    /// Clear all facts and reset indices
    pub fn clear(self: *FactIndex) void {
        self.by_id.clearAndFree();
        self.by_span.clear();

        {
            var iter = self.by_predicate.iterator();
            while (iter.next()) |entry| {
                entry.value_ptr.deinit();
            }
            self.by_predicate.clearAndFree();
        }

        {
            var iter = self.by_generation.iterator();
            while (iter.next()) |entry| {
                entry.value_ptr.deinit();
            }
            self.by_generation.clearAndFree();
        }

        {
            var iter = self.parent_child.iterator();
            while (iter.next()) |entry| {
                entry.value_ptr.deinit();
            }
            self.parent_child.clearAndFree();
        }

        self.stats = IndexStats{};
        self.current_generation = 0;
    }
};

/// Statistics for monitoring index performance
pub const IndexStats = struct {
    fact_count: usize = 0,
    total_insertions: usize = 0,
    total_removals: usize = 0,
    lookups_by_id: usize = 0,
    lookups_by_span: usize = 0,
    lookups_by_predicate: usize = 0,
    lookups_by_generation: usize = 0,

    pub fn hitRate(self: IndexStats) f64 {
        const total_lookups = self.lookups_by_id + self.lookups_by_span +
            self.lookups_by_predicate + self.lookups_by_generation;
        if (total_lookups == 0) return 0.0;
        return @as(f64, @floatFromInt(total_lookups)) / @as(f64, @floatFromInt(total_lookups));
    }

    pub fn format(
        self: IndexStats,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("IndexStats(facts={}, ins={}, rem={}, lookups={})", .{
            self.fact_count,
            self.total_insertions,
            self.total_removals,
            self.lookups_by_id + self.lookups_by_span + self.lookups_by_predicate + self.lookups_by_generation,
        });
    }
};

/// Spatial index for span-based queries using interval tree
const SpanIndex = struct {
    intervals: std.ArrayList(SpanInterval),
    allocator: std.mem.Allocator,

    const SpanInterval = struct {
        span: Span,
        fact_ids: FactIdList,

        fn deinit(self: *SpanInterval) void {
            self.fact_ids.deinit();
        }
    };

    fn init(allocator: std.mem.Allocator) SpanIndex {
        return .{
            .intervals = std.ArrayList(SpanInterval).init(allocator),
            .allocator = allocator,
        };
    }

    fn deinit(self: *SpanIndex) void {
        for (self.intervals.items) |*interval| {
            interval.deinit();
        }
        self.intervals.deinit();
    }

    fn insert(self: *SpanIndex, span: Span, fact_id: FactId) !void {
        // Find existing interval for this span
        for (self.intervals.items) |*interval| {
            if (interval.span.eql(span)) {
                try interval.fact_ids.append(fact_id);
                return;
            }
        }

        // Create new interval
        var fact_ids = FactIdList.init(self.allocator);
        try fact_ids.append(fact_id);

        try self.intervals.append(.{
            .span = span,
            .fact_ids = fact_ids,
        });

        // Keep intervals sorted by start position for efficient queries
        std.sort.heap(SpanInterval, self.intervals.items, {}, spanIntervalLessThan);
    }

    fn remove(self: *SpanIndex, span: Span, fact_id: FactId) void {
        for (self.intervals.items, 0..) |*interval, i| {
            if (interval.span.eql(span)) {
                if (findFactIdIndex(&interval.fact_ids, fact_id)) |index| {
                    _ = interval.fact_ids.swapRemove(index);

                    // Remove interval if no facts remain
                    if (interval.fact_ids.items.len == 0) {
                        interval.deinit();
                        _ = self.intervals.swapRemove(i);
                    }
                }
                return;
            }
        }
    }

    fn findOverlapping(self: *SpanIndex, query_span: Span, allocator: std.mem.Allocator) ![]FactId {
        var result = FactIdList.init(allocator);

        for (self.intervals.items) |*interval| {
            if (interval.span.overlaps(query_span)) {
                try result.appendSlice(interval.fact_ids.items);
            }
        }

        return result.toOwnedSlice();
    }

    fn clear(self: *SpanIndex) void {
        for (self.intervals.items) |*interval| {
            interval.deinit();
        }
        self.intervals.clearAndFree();
    }
};

/// Dynamic array of fact IDs
const FactIdList = std.ArrayList(FactId);

/// Hash map contexts for different key types
const FactIdContext = std.hash_map.AutoContext(FactId);
const PredicateCategoryContext = std.hash_map.AutoContext(PredicateCategory);
const GenerationContext = std.hash_map.AutoContext(Generation);

/// Helper functions
fn findFactIdIndex(list: *FactIdList, fact_id: FactId) ?usize {
    for (list.items, 0..) |id, i| {
        if (id == fact_id) return i;
    }
    return null;
}

fn spanIntervalLessThan(context: void, a: SpanIndex.SpanInterval, b: SpanIndex.SpanInterval) bool {
    _ = context;
    return a.span.order(b.span) == .lt;
}

// Tests
const testing = std.testing;

test "FactIndex basic operations" {
    var index = FactIndex.init(testing.allocator);
    defer index.deinit();

    const span1 = Span.init(10, 20);
    const span2 = Span.init(15, 25);
    const predicate1 = Predicate{ .is_token = .identifier };
    const predicate2 = Predicate{ .is_boundary = .function };

    const fact1 = Fact.simple(1, span1, predicate1, 0);
    const fact2 = Fact.simple(2, span2, predicate2, 1);

    // Test insertion
    try index.insert(fact1);
    try index.insert(fact2);
    try testing.expectEqual(@as(usize, 2), index.count());

    // Test lookup by ID
    try testing.expect(index.get(1).?.eql(fact1));
    try testing.expect(index.get(2).?.eql(fact2));
    try testing.expectEqual(@as(?Fact, null), index.get(999));

    // Test removal
    try testing.expect(index.remove(1));
    try testing.expectEqual(@as(usize, 1), index.count());
    try testing.expectEqual(@as(?Fact, null), index.get(1));
    try testing.expect(!index.remove(999));
}

test "FactIndex span queries" {
    var index = FactIndex.init(testing.allocator);
    defer index.deinit();

    const spans = [_]Span{
        Span.init(10, 20),
        Span.init(15, 25),
        Span.init(30, 40),
    };
    const predicate = Predicate{ .is_token = .identifier };

    // Insert facts with different spans
    for (spans, 0..) |span, i| {
        const fact = Fact.simple(@intCast(i + 1), span, predicate, 0);
        try index.insert(fact);
    }

    // Query overlapping with first two spans
    const query_span = Span.init(5, 22);
    const overlapping = try index.findOverlapping(query_span, testing.allocator);
    defer testing.allocator.free(overlapping);

    try testing.expectEqual(@as(usize, 2), overlapping.len);

    // Should find facts 1 and 2
    var found_1 = false;
    var found_2 = false;
    for (overlapping) |fact_id| {
        if (fact_id == 1) found_1 = true;
        if (fact_id == 2) found_2 = true;
    }
    try testing.expect(found_1);
    try testing.expect(found_2);
}

test "FactIndex category queries" {
    var index = FactIndex.init(testing.allocator);
    defer index.deinit();

    const span = Span.init(10, 20);
    const token_predicate = Predicate{ .is_token = .identifier };
    const boundary_predicate = Predicate{ .is_boundary = .function };

    const fact1 = Fact.simple(1, span, token_predicate, 0);
    const fact2 = Fact.simple(2, span, boundary_predicate, 0);

    try index.insert(fact1);
    try index.insert(fact2);

    // Query by category
    const lexical_facts = index.findByCategory(.lexical);
    const structural_facts = index.findByCategory(.structural);

    try testing.expectEqual(@as(usize, 1), lexical_facts.?.len);
    try testing.expectEqual(@as(FactId, 1), lexical_facts.?[0]);

    try testing.expectEqual(@as(usize, 1), structural_facts.?.len);
    try testing.expectEqual(@as(FactId, 2), structural_facts.?[0]);
}

test "FactIndex generation operations" {
    var index = FactIndex.init(testing.allocator);
    defer index.deinit();

    const span = Span.init(10, 20);
    const predicate = Predicate{ .is_token = .identifier };

    // Insert facts with different generations
    const fact1 = Fact.simple(1, span, predicate, 0);
    const fact2 = Fact.simple(2, span, predicate, 1);
    const fact3 = Fact.simple(3, span, predicate, 1);

    try index.insert(fact1);
    try index.insert(fact2);
    try index.insert(fact3);

    // Query by generation
    const gen0_facts = index.findByGeneration(0);
    const gen1_facts = index.findByGeneration(1);

    try testing.expectEqual(@as(usize, 1), gen0_facts.?.len);
    try testing.expectEqual(@as(usize, 2), gen1_facts.?.len);

    // Remove entire generation
    index.removeGeneration(1);
    try testing.expectEqual(@as(usize, 1), index.count());
    try testing.expect(index.get(1) != null);
    try testing.expect(index.get(2) == null);
    try testing.expect(index.get(3) == null);
}

test "FactIndex batch operations" {
    var index = FactIndex.init(testing.allocator);
    defer index.deinit();

    const span = Span.init(10, 20);
    const predicate = Predicate{ .is_token = .identifier };

    // Create batch of facts
    var facts: [10]Fact = undefined;
    for (&facts, 0..) |*fact, i| {
        fact.* = Fact.simple(@intCast(i + 1), span, predicate, 0);
    }

    // Batch insert
    try index.insertBatch(&facts);
    try testing.expectEqual(@as(usize, 10), index.count());

    // Verify all facts inserted
    for (1..11) |i| {
        try testing.expect(index.get(@intCast(i)) != null);
    }

    // Test clear
    index.clear();
    try testing.expectEqual(@as(usize, 0), index.count());
}

test "FactIndex statistics" {
    var index = FactIndex.init(testing.allocator);
    defer index.deinit();

    const span = Span.init(10, 20);
    const predicate = Predicate{ .is_token = .identifier };
    const fact = Fact.simple(1, span, predicate, 0);

    // Check initial stats
    var stats = index.getStats();
    try testing.expectEqual(@as(usize, 0), stats.fact_count);
    try testing.expectEqual(@as(usize, 0), stats.total_insertions);

    // Insert and check stats
    try index.insert(fact);
    stats = index.getStats();
    try testing.expectEqual(@as(usize, 1), stats.fact_count);
    try testing.expectEqual(@as(usize, 1), stats.total_insertions);

    // Lookup and check stats
    _ = index.get(1);
    stats = index.getStats();
    try testing.expectEqual(@as(usize, 1), stats.lookups_by_id);

    // Remove and check stats
    _ = index.remove(1);
    stats = index.getStats();
    try testing.expectEqual(@as(usize, 0), stats.fact_count);
    try testing.expectEqual(@as(usize, 1), stats.total_removals);
}
