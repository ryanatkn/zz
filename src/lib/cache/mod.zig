/// Cache module - High-performance fact caching for stream-first architecture
///
/// Replaces the old BoundaryCache with a more general FactCache that can
/// cache any facts, not just boundaries. Multi-indexed for fast lookups.
///
/// TODO: SIMD-accelerated fact lookups (Phase 4)
/// TODO: Compressed fact storage for large files (Phase 4)
/// TODO: Incremental cache updates for edits (Phase 3)
const std = @import("std");

// Export cache types
pub const FactCache = @import("fact_cache.zig").FactCache;
pub const CacheStats = @import("fact_cache.zig").CacheStats;
pub const LruList = @import("lru.zig").LruList;
pub const QueryIndex = @import("index.zig").QueryIndex;

// Re-export fact types for convenience
pub const Fact = @import("../fact/mod.zig").Fact;
pub const FactId = @import("../fact/mod.zig").FactId;
pub const Predicate = @import("../fact/mod.zig").Predicate;
pub const PackedSpan = @import("../span/mod.zig").PackedSpan;

test {
    _ = @import("test.zig");
    _ = @import("fact_cache.zig");
    _ = @import("lru.zig");
    _ = @import("index.zig");
}
