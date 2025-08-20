const std = @import("std");
const Fact = @import("fact.zig").Fact;
const FactId = @import("fact.zig").FactId;
const Generation = @import("fact.zig").Generation;

/// Append-only fact storage with generation tracking
/// Designed for efficient streaming and incremental updates
pub const FactStore = struct {
    /// All facts stored sequentially
    facts: std.ArrayList(Fact),

    /// Current generation number
    generation: Generation,

    /// Next available fact ID
    next_id: FactId,

    /// Allocator for memory management
    allocator: std.mem.Allocator,

    /// Statistics for monitoring
    stats: FactStoreStats,

    /// Initialize a new fact store
    pub fn init(allocator: std.mem.Allocator) FactStore {
        return .{
            .facts = std.ArrayList(Fact).init(allocator),
            .generation = 0,
            .next_id = 1, // Start from 1, 0 is reserved for "no fact"
            .allocator = allocator,
            .stats = FactStoreStats{},
        };
    }

    /// Deinitialize and free memory
    pub fn deinit(self: *FactStore) void {
        self.facts.deinit();
    }

    /// Append a single fact to the store
    pub fn append(self: *FactStore, fact: Fact) !FactId {
        const id = self.next_id;
        var fact_with_id = fact;
        fact_with_id.id = id;

        try self.facts.append(fact_with_id);
        self.next_id += 1;
        self.stats.total_facts += 1;
        self.stats.facts_in_generation += 1;

        return id;
    }

    /// Append multiple facts in batch
    pub fn appendBatch(self: *FactStore, facts: []const Fact) ![]FactId {
        const ids = try self.allocator.alloc(FactId, facts.len);
        errdefer self.allocator.free(ids);

        for (facts, 0..) |fact, i| {
            ids[i] = try self.append(fact);
        }

        return ids;
    }

    /// Create and append a fact, returning its ID
    pub fn create(
        self: *FactStore,
        subject: anytype, // PackedSpan or will be packed
        predicate: anytype, // Predicate
        object: anytype, // Value
        confidence: f16,
    ) !FactId {
        const fact = Fact.init(
            0, // ID will be assigned
            subject,
            predicate,
            object,
            confidence,
        );
        return self.append(fact);
    }

    /// Get a fact by ID (returns null if not found)
    pub fn get(self: *FactStore, id: FactId) ?Fact {
        if (id == 0 or id > self.next_id - 1) return null;
        const index = id - 1; // IDs start at 1
        if (index >= self.facts.items.len) return null;
        return self.facts.items[index];
    }

    /// Get a slice of facts by ID range
    pub fn getRange(self: *FactStore, start_id: FactId, end_id: FactId) []const Fact {
        if (start_id == 0 or start_id > self.next_id - 1) return &[_]Fact{};
        if (end_id == 0 or end_id > self.next_id) return &[_]Fact{};
        if (start_id >= end_id) return &[_]Fact{};

        const start_index = start_id - 1;
        const end_index = @min(end_id - 1, self.facts.items.len);

        return self.facts.items[start_index..end_index];
    }

    /// Get all facts in the store
    pub fn getAll(self: *FactStore) []const Fact {
        return self.facts.items;
    }

    /// Get the current generation
    pub fn getGeneration(self: *FactStore) Generation {
        return self.generation;
    }

    /// Increment generation (marks a new epoch)
    pub fn nextGeneration(self: *FactStore) Generation {
        self.generation += 1;
        self.stats.facts_in_generation = 0;
        self.stats.generations += 1;
        return self.generation;
    }

    /// Get the number of facts in the store
    pub fn count(self: *FactStore) usize {
        return self.facts.items.len;
    }

    /// Check if store is empty
    pub fn isEmpty(self: *FactStore) bool {
        return self.facts.items.len == 0;
    }

    /// Clear all facts (but keep generation)
    pub fn clear(self: *FactStore) void {
        self.facts.clearRetainingCapacity();
        self.next_id = 1;
        self.stats.total_facts = 0;
        self.stats.facts_in_generation = 0;
    }

    /// Compact the store (remove facts below a certain confidence)
    pub fn compact(self: *FactStore, min_confidence: f16) void {
        var write_idx: usize = 0;
        for (self.facts.items) |fact| {
            if (fact.confidence >= min_confidence) {
                self.facts.items[write_idx] = fact;
                write_idx += 1;
            }
        }
        self.facts.shrinkRetainingCapacity(write_idx);
        self.stats.compactions += 1;
    }

    /// Reserve capacity for n additional facts
    pub fn ensureCapacity(self: *FactStore, additional: usize) !void {
        try self.facts.ensureUnusedCapacity(additional);
    }

    /// Get store statistics
    pub fn getStats(self: *FactStore) FactStoreStats {
        return self.stats;
    }

    /// Create an iterator over facts
    pub fn iterator(self: *FactStore) FactIterator {
        return FactIterator.init(self.facts.items);
    }

    // TODO: Add support for memory-mapped persistence
    // TODO: Add support for incremental snapshots
    // TODO: Add support for fact stream subscriptions
};

/// Statistics for monitoring fact store performance
pub const FactStoreStats = struct {
    total_facts: u64 = 0,
    facts_in_generation: u64 = 0,
    generations: u32 = 0,
    compactions: u32 = 0,
};

/// Iterator over facts in the store
pub const FactIterator = struct {
    facts: []const Fact,
    index: usize,

    pub fn init(facts: []const Fact) FactIterator {
        return .{
            .facts = facts,
            .index = 0,
        };
    }

    pub fn next(self: *FactIterator) ?Fact {
        if (self.index >= self.facts.len) return null;
        const fact = self.facts[self.index];
        self.index += 1;
        return fact;
    }

    pub fn peek(self: *FactIterator) ?Fact {
        if (self.index >= self.facts.len) return null;
        return self.facts[self.index];
    }

    pub fn skip(self: *FactIterator, n: usize) void {
        self.index = @min(self.index + n, self.facts.len);
    }

    pub fn reset(self: *FactIterator) void {
        self.index = 0;
    }
};
