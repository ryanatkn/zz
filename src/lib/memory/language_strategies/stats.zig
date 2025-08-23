const std = @import("std");

/// Comprehensive memory statistics for monitoring and optimization
pub const MemoryStats = struct {
    // Allocation counts
    nodes_allocated: usize = 0,
    arrays_allocated: usize = 0,
    strings_allocated: usize = 0,

    // Memory usage
    total_bytes_allocated: usize = 0,
    arena_bytes_used: usize = 0,
    pool_bytes_used: usize = 0,
    string_bytes_used: usize = 0,

    // Pool statistics
    node_pool_capacity: usize = 0,
    node_pool_hits: usize = 0, // Successful pool reuse
    node_pool_misses: usize = 0, // Had to allocate new
    array_pool_hits: usize = 0,
    array_pool_misses: usize = 0,

    // String interning statistics
    strings_interned: usize = 0,
    string_intern_hits: usize = 0,
    string_intern_bytes_saved: usize = 0,

    // Performance metrics
    allocation_time_ns: u64 = 0,
    deallocation_time_ns: u64 = 0,

    // Memory pressure indicators
    peak_memory_usage: usize = 0,
    allocation_failures: usize = 0,

    // Adaptive strategy metrics
    strategy_upgrades: usize = 0,
    strategy_downgrades: usize = 0,

    /// Calculate memory efficiency as a percentage
    pub fn efficiency(self: MemoryStats) f32 {
        if (self.total_bytes_allocated == 0) return 100.0;
        const wasted = self.total_bytes_allocated - self.arena_bytes_used - self.pool_bytes_used - self.string_bytes_used;
        return @as(f32, @floatFromInt(self.total_bytes_allocated - wasted)) / @as(f32, @floatFromInt(self.total_bytes_allocated)) * 100.0;
    }

    /// Calculate pool hit rate
    pub fn poolHitRate(self: MemoryStats) f32 {
        const total_pool_accesses = self.node_pool_hits + self.node_pool_misses + self.array_pool_hits + self.array_pool_misses;
        if (total_pool_accesses == 0) return 0.0;
        const total_hits = self.node_pool_hits + self.array_pool_hits;
        return @as(f32, @floatFromInt(total_hits)) / @as(f32, @floatFromInt(total_pool_accesses)) * 100.0;
    }

    /// Check if pooling would be beneficial based on patterns
    pub fn shouldUsePooling(self: MemoryStats) bool {
        // High allocation count suggests pooling would help
        if (self.nodes_allocated > 1000) return true;
        if (self.arrays_allocated > 100) return true;

        // Low pool hit rate suggests pooling not helping
        if (self.poolHitRate() < 20.0 and self.node_pool_capacity > 0) return false;

        return false;
    }

    /// Check if string interning would be beneficial
    pub fn shouldInternStrings(self: MemoryStats) bool {
        // High string count suggests interning might help
        if (self.strings_allocated > 500) return true;

        // Already beneficial if saving memory
        if (self.string_intern_bytes_saved > 10000) return true;

        return false;
    }

    /// Check for memory pressure
    pub fn hasMemoryPressure(self: MemoryStats) bool {
        return self.allocation_failures > 0 or
            self.peak_memory_usage > 100 * 1024 * 1024; // 100MB threshold
    }

    /// Get allocation rate (allocations per millisecond)
    pub fn allocationRate(self: MemoryStats) f32 {
        if (self.allocation_time_ns == 0) return 0.0;
        const total_allocations = self.nodes_allocated + self.arrays_allocated + self.strings_allocated;
        const time_ms = @as(f32, @floatFromInt(self.allocation_time_ns)) / 1_000_000.0;
        return @as(f32, @floatFromInt(total_allocations)) / time_ms;
    }

    /// Format stats for display
    pub fn format(self: MemoryStats, writer: anytype) !void {
        try writer.print("Memory Stats:\n", .{});
        try writer.print("  Allocations: {} nodes, {} arrays, {} strings\n", .{ self.nodes_allocated, self.arrays_allocated, self.strings_allocated });
        try writer.print("  Memory: {:.2} MB total, {:.2} MB peak\n", .{
            @as(f32, @floatFromInt(self.total_bytes_allocated)) / 1024.0 / 1024.0,
            @as(f32, @floatFromInt(self.peak_memory_usage)) / 1024.0 / 1024.0,
        });
        try writer.print("  Efficiency: {:.1}%\n", .{self.efficiency()});
        try writer.print("  Pool hit rate: {:.1}%\n", .{self.poolHitRate()});
        try writer.print("  Allocation rate: {:.0} allocs/ms\n", .{self.allocationRate()});

        if (self.string_intern_bytes_saved > 0) {
            try writer.print("  String interning saved: {:.2} KB\n", .{@as(f32, @floatFromInt(self.string_intern_bytes_saved)) / 1024.0});
        }

        if (self.strategy_upgrades > 0 or self.strategy_downgrades > 0) {
            try writer.print("  Strategy changes: {} upgrades, {} downgrades\n", .{ self.strategy_upgrades, self.strategy_downgrades });
        }

        if (self.hasMemoryPressure()) {
            try writer.print("  ⚠️  Memory pressure detected!\n", .{});
        }
    }

    /// Merge stats from another instance (for aggregation)
    pub fn merge(self: *MemoryStats, other: MemoryStats) void {
        self.nodes_allocated += other.nodes_allocated;
        self.arrays_allocated += other.arrays_allocated;
        self.strings_allocated += other.strings_allocated;

        self.total_bytes_allocated += other.total_bytes_allocated;
        self.arena_bytes_used += other.arena_bytes_used;
        self.pool_bytes_used += other.pool_bytes_used;
        self.string_bytes_used += other.string_bytes_used;

        self.node_pool_hits += other.node_pool_hits;
        self.node_pool_misses += other.node_pool_misses;
        self.array_pool_hits += other.array_pool_hits;
        self.array_pool_misses += other.array_pool_misses;

        self.strings_interned += other.strings_interned;
        self.string_intern_hits += other.string_intern_hits;
        self.string_intern_bytes_saved += other.string_intern_bytes_saved;

        self.allocation_time_ns += other.allocation_time_ns;
        self.deallocation_time_ns += other.deallocation_time_ns;

        self.peak_memory_usage = @max(self.peak_memory_usage, other.peak_memory_usage);
        self.allocation_failures += other.allocation_failures;

        self.strategy_upgrades += other.strategy_upgrades;
        self.strategy_downgrades += other.strategy_downgrades;
    }
};
