const std = @import("std");

/// Node allocation strategies
pub const NodeStrategy = enum {
    /// Simple arena allocation
    arena,
    /// Small object pool (16-256 nodes)
    small_pool,
    /// Large object pool (256+ nodes)
    large_pool,
    /// Tagged allocation with embedded metadata
    tagged,
};

/// Array allocation strategies
pub const ArrayStrategy = enum {
    /// Simple arena allocation
    arena,
    /// Size-classed pools (small/medium/large)
    size_classed,
    /// Metadata-tracked for precise memory management
    metadata_tracked,
    /// Tagged with embedded headers
    tagged,
};

/// String allocation strategies
pub const StringStrategy = enum {
    /// Arena allocation (temporary strings)
    arena,
    /// Persistent allocation (survives arena cleanup)
    persistent,
    /// String interning for deduplication
    interned,
};

/// Pool configuration
pub const PoolConfig = struct {
    initial_capacity: usize = 1024,
    max_capacity: usize = 65536,
    growth_factor: f32 = 2.0,
    enable_metrics: bool = false,
};

/// Metadata tracking configuration (from TODO_ARRAYPOOL_OPTIMIZATION.md)
pub const MetadataConfig = struct {
    track_allocations: bool = true,
    track_lifetime: bool = false,
    max_tracked: usize = 10000,
    enable_diagnostics: bool = false,
};

/// Tagged allocation configuration (from TODO_ARRAYPOOL_OPTIMIZATION.md)
pub const TaggedConfig = struct {
    magic_number: u32 = 0xDEADBEEF,
    alignment: usize = 16,
    enable_bounds_checking: bool = false,
    enable_double_free_detection: bool = false,
};

/// Adaptive strategy configuration
pub const AdaptiveConfig = struct {
    /// Number of allocations before considering upgrade
    sample_period: usize = 1000,
    /// Allocation rate threshold for upgrading (allocs/ms)
    upgrade_threshold: f32 = 10.0,
    /// Memory pressure threshold (bytes)
    memory_threshold: usize = 1024 * 1024,
    /// Enable automatic downgrade on low usage
    allow_downgrade: bool = false,
};

/// Composed memory strategy using tagged union
pub const MemoryStrategy = union(enum) {
    /// Simple arena-only allocation
    arena_only,

    /// Arena + object pooling with configuration
    pooled: PoolConfig,

    /// Hybrid strategy with different optimizations per allocation type
    hybrid: struct {
        nodes: NodeStrategy,
        arrays: ArrayStrategy,
        strings: StringStrategy,
    },

    /// Adaptive strategy that changes based on runtime patterns
    adaptive: struct {
        config: AdaptiveConfig,
        initial: *const MemoryStrategy,
        target: *const MemoryStrategy,
    },

    /// Advanced metadata-tracked allocation (2.5x faster from TODO)
    metadata_tracked: MetadataConfig,

    /// Advanced tagged allocation (3.0x faster from TODO)
    tagged_allocation: TaggedConfig,

    /// Custom strategy with user-provided allocator functions
    custom: struct {
        name: []const u8,
        allocate_node: *const fn (size: usize) anyerror!*anyopaque,
        allocate_array: *const fn (size: usize) anyerror![]anyopaque,
        allocate_string: *const fn (str: []const u8) anyerror![]const u8,
        free_node: ?*const fn (ptr: *anyopaque) void = null,
        free_array: ?*const fn (ptr: []anyopaque) void = null,
        free_string: ?*const fn (str: []const u8) void = null,
    },

    pub fn describe(self: MemoryStrategy) []const u8 {
        return switch (self) {
            .arena_only => "arena-only (simple, safe)",
            .pooled => "pooled (optimized for allocation churn)",
            .hybrid => "hybrid (composed strategies)",
            .adaptive => "adaptive (runtime optimization)",
            .metadata_tracked => "metadata-tracked (2.5x performance)",
            .tagged_allocation => "tagged (3.0x performance)",
            .custom => |c| c.name,
        };
    }

    /// Estimate memory overhead for this strategy
    pub fn estimateOverhead(self: MemoryStrategy) usize {
        return switch (self) {
            .arena_only => 0, // No overhead
            .pooled => |config| config.initial_capacity * @sizeOf(usize), // Pool arrays
            .hybrid => 1024, // Mixed pools
            .adaptive => 2048, // Tracking overhead
            .metadata_tracked => |config| config.max_tracked * @sizeOf(TrackedAllocation),
            .tagged_allocation => |config| config.alignment * 100, // Headers
            .custom => 0, // Unknown
        };
    }

    /// Check if strategy benefits from pre-warming
    pub fn shouldPrewarm(self: MemoryStrategy) bool {
        return switch (self) {
            .arena_only => false,
            .pooled => true,
            .hybrid => |h| h.nodes != .arena or h.arrays != .arena,
            .adaptive => false, // Starts simple
            .metadata_tracked => true,
            .tagged_allocation => true,
            .custom => false, // Unknown
        };
    }
};

// Internal type for metadata tracking
const TrackedAllocation = struct {
    ptr: usize,
    size: usize,
    timestamp: i64,
};
