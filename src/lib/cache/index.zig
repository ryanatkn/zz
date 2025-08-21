/// QueryIndex - Fast fact indexing for queries
///
/// TODO: B-tree indices for range queries
/// TODO: Bloom filters for existence checks
/// TODO: Parallel index construction
/// TODO: Incremental index updates
const std = @import("std");
const Fact = @import("../fact/mod.zig").Fact;
const FactId = @import("../fact/mod.zig").FactId;
const FactStore = @import("../fact/mod.zig").FactStore;
const Predicate = @import("../fact/mod.zig").Predicate;
const PackedSpan = @import("../span/mod.zig").PackedSpan;

/// Query index for fast fact lookups
pub const QueryIndex = struct {
    allocator: std.mem.Allocator,

    /// Index facts by predicate
    by_predicate: std.AutoHashMap(Predicate, std.ArrayList(FactId)),

    /// Index facts by span
    by_span: std.AutoHashMap(PackedSpan, std.ArrayList(FactId)),

    /// Index facts by confidence range (buckets of 0.1)
    /// TODO: Make bucket size configurable
    by_confidence: [11]std.ArrayList(FactId), // 0.0-0.1, 0.1-0.2, ..., 1.0

    /// Reference to the fact store
    store: *FactStore,

    /// Statistics
    stats: IndexStats = .{},

    pub const IndexStats = struct {
        total_facts: usize = 0,
        predicate_buckets: usize = 0,
        span_buckets: usize = 0,
        confidence_distribution: [11]usize = .{0} ** 11,
        build_time_ns: i64 = 0,
        last_update_ns: i64 = 0,
    };

    /// Initialize a new query index
    pub fn init(allocator: std.mem.Allocator, store: *FactStore) QueryIndex {
        var index = QueryIndex{
            .allocator = allocator,
            .by_predicate = std.AutoHashMap(Predicate, std.ArrayList(FactId)).init(allocator),
            .by_span = std.AutoHashMap(PackedSpan, std.ArrayList(FactId)).init(allocator),
            .by_confidence = undefined,
            .store = store,
        };

        // Initialize confidence buckets
        for (&index.by_confidence) |*bucket| {
            bucket.* = std.ArrayList(FactId).init(allocator);
        }

        return index;
    }

    /// Clean up resources
    pub fn deinit(self: *QueryIndex) void {
        // Clean up predicate index
        var pred_iter = self.by_predicate.iterator();
        while (pred_iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.by_predicate.deinit();

        // Clean up span index
        var span_iter = self.by_span.iterator();
        while (span_iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.by_span.deinit();

        // Clean up confidence buckets
        for (&self.by_confidence) |*bucket| {
            bucket.deinit();
        }
    }

    /// Build index from fact store
    pub fn build(self: *QueryIndex) !void {
        const start_time = std.time.nanoTimestamp();
        defer {
            self.stats.build_time_ns = @intCast(std.time.nanoTimestamp() - start_time);
        }

        // Clear existing indices
        self.clear();

        // Index all facts
        const facts = self.store.getAll();
        for (facts, 0..) |fact, i| {
            const id = @as(FactId, @intCast(i));
            try self.update(fact, id);
        }

        self.stats.total_facts = facts.len;
        self.stats.predicate_buckets = self.by_predicate.count();
        self.stats.span_buckets = self.by_span.count();
    }

    /// Update index with a new fact
    pub fn update(self: *QueryIndex, fact: Fact, id: FactId) !void {
        self.stats.last_update_ns = @intCast(std.time.nanoTimestamp());

        // Update predicate index
        const pred_result = try self.by_predicate.getOrPut(fact.predicate);
        if (!pred_result.found_existing) {
            pred_result.value_ptr.* = std.ArrayList(FactId).init(self.allocator);
        }
        try pred_result.value_ptr.append(id);

        // Update span index
        const span_result = try self.by_span.getOrPut(fact.subject);
        if (!span_result.found_existing) {
            span_result.value_ptr.* = std.ArrayList(FactId).init(self.allocator);
        }
        try span_result.value_ptr.append(id);

        // Update confidence index
        const bucket_idx = confidenceToBucket(fact.confidence);
        try self.by_confidence[bucket_idx].append(id);
        self.stats.confidence_distribution[bucket_idx] += 1;

        self.stats.total_facts += 1;
    }

    /// Query facts by predicate
    pub fn queryByPredicate(self: *QueryIndex, predicate: Predicate) []FactId {
        if (self.by_predicate.get(predicate)) |list| {
            return list.items;
        }
        return &.{};
    }

    /// Query facts by span
    pub fn queryBySpan(self: *QueryIndex, span: PackedSpan) []FactId {
        if (self.by_span.get(span)) |list| {
            return list.items;
        }
        return &.{};
    }

    /// Query facts by confidence range
    pub fn queryByConfidence(self: *QueryIndex, min: f16, max: f16) ![]FactId {
        // TODO: The bucket calculation should consider that confidence values
        // exactly on bucket boundaries may need special handling
        const min_bucket = confidenceToBucket(min);
        const max_bucket = confidenceToBucket(max);

        // Count total facts in range
        var total: usize = 0;
        for (min_bucket..max_bucket + 1) |i| {
            // Check each fact in bucket to see if it's actually in range
            // This is needed because bucket boundaries may not align exactly
            for (self.by_confidence[i].items) |fact_id| {
                const fact = self.store.get(fact_id) orelse continue;
                if (fact.confidence >= min and fact.confidence <= max) {
                    total += 1;
                }
            }
        }

        // Collect all fact IDs
        var result = try self.allocator.alloc(FactId, total);
        var offset: usize = 0;

        for (min_bucket..max_bucket + 1) |i| {
            for (self.by_confidence[i].items) |fact_id| {
                const fact = self.store.get(fact_id) orelse continue;
                if (fact.confidence >= min and fact.confidence <= max) {
                    result[offset] = fact_id;
                    offset += 1;
                }
            }
        }

        return result;
    }

    /// Query with multiple criteria (intersection)
    /// TODO: Optimize with bitmap operations
    pub fn queryComplex(
        self: *QueryIndex,
        predicate: ?Predicate,
        span: ?PackedSpan,
        min_confidence: ?f16,
    ) ![]FactId {
        var sets = std.ArrayList([]FactId).init(self.allocator);
        defer sets.deinit();

        if (predicate) |p| {
            try sets.append(self.queryByPredicate(p));
        }

        if (span) |s| {
            try sets.append(self.queryBySpan(s));
        }

        if (min_confidence) |min| {
            const confidence_facts = try self.queryByConfidence(min, 1.0);
            try sets.append(confidence_facts);
        }

        if (sets.items.len == 0) {
            return &.{};
        }

        // Find intersection of all sets
        // TODO: Use more efficient set intersection algorithm
        return self.intersectSets(sets.items);
    }

    /// Clear all indices
    pub fn clear(self: *QueryIndex) void {
        // Clear predicate index
        var pred_iter = self.by_predicate.iterator();
        while (pred_iter.next()) |entry| {
            entry.value_ptr.clearRetainingCapacity();
        }

        // Clear span index
        var span_iter = self.by_span.iterator();
        while (span_iter.next()) |entry| {
            entry.value_ptr.clearRetainingCapacity();
        }

        // Clear confidence buckets
        for (&self.by_confidence) |*bucket| {
            bucket.clearRetainingCapacity();
        }

        // Clear stats
        self.stats = .{};
    }

    /// Get index statistics
    pub fn getStats(self: *const QueryIndex) IndexStats {
        return self.stats;
    }

    /// Convert confidence to bucket index
    fn confidenceToBucket(confidence: f16) usize {
        const bucket = @as(usize, @intFromFloat(confidence * 10.0));
        return @min(bucket, 10);
    }

    /// Find intersection of multiple fact ID sets
    fn intersectSets(self: *QueryIndex, sets: [][]FactId) ![]FactId {
        if (sets.len == 0) return &.{};
        if (sets.len == 1) return sets[0];

        // TODO: Sort sets by size and start with smallest
        // TODO: Use hash set for O(1) lookups

        var result = std.ArrayList(FactId).init(self.allocator);

        // Check each ID in first set against all other sets
        for (sets[0]) |id| {
            var in_all = true;
            for (sets[1..]) |set| {
                var found = false;
                for (set) |other_id| {
                    if (id == other_id) {
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    in_all = false;
                    break;
                }
            }
            if (in_all) {
                try result.append(id);
            }
        }

        return result.toOwnedSlice();
    }
};

test "QueryIndex basic operations" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const Builder = @import("../fact/mod.zig").Builder;

    var store = FactStore.init(allocator);
    defer store.deinit();

    // Add some facts to store
    const span1: PackedSpan = 0x0000000100000010;
    const span2: PackedSpan = 0x0000001000000020;

    const fact1 = try Builder.new()
        .withSubject(span1)
        .withPredicate(.is_string)
        .withConfidence(0.9)
        .build();
    _ = try store.append(fact1);

    const fact2 = try Builder.new()
        .withSubject(span1)
        .withPredicate(.has_text)
        .withConfidence(0.8)
        .build();
    _ = try store.append(fact2);

    const fact3 = try Builder.new()
        .withSubject(span2)
        .withPredicate(.is_string)
        .withConfidence(0.7)
        .build();
    _ = try store.append(fact3);

    // Build index
    var index = QueryIndex.init(allocator, &store);
    defer index.deinit();

    try index.build();

    // Test queries
    const by_pred = index.queryByPredicate(.is_string);
    try testing.expectEqual(@as(usize, 2), by_pred.len);

    const by_span = index.queryBySpan(span1);
    try testing.expectEqual(@as(usize, 2), by_span.len);

    const by_confidence = try index.queryByConfidence(0.75, 1.0);
    defer allocator.free(by_confidence);
    try testing.expectEqual(@as(usize, 2), by_confidence.len);

    // Test complex query
    const complex = try index.queryComplex(.is_string, span1, 0.8);
    defer allocator.free(complex);
    try testing.expectEqual(@as(usize, 1), complex.len);

    // Check stats
    const stats = index.getStats();
    try testing.expectEqual(@as(usize, 3), stats.total_facts);
    try testing.expectEqual(@as(usize, 2), stats.predicate_buckets);
    try testing.expectEqual(@as(usize, 2), stats.span_buckets);

    // TODO: Test incremental updates
    // TODO: Test edge cases
    // TODO: Test performance with large datasets
}
