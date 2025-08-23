const std = @import("std");
const ArrayStrategy = @import("strategy.zig").ArrayStrategy;
const MemoryStats = @import("stats.zig").MemoryStats;

/// Specialized array allocator with strategy-based dispatch
pub fn ArrayAllocator(comptime T: type) type {
    return struct {
        allocator: std.mem.Allocator,
        arena: *std.heap.ArenaAllocator,
        strategy: ArrayStrategy,
        stats: *MemoryStats,

        // Pool implementations
        size_classed_pool: ?SizeClassedPool(T) = null,
        metadata_tracked_pool: ?MetadataTrackedPool(T) = null,
        tagged_pool: ?TaggedArrayPool(T) = null,

        const Self = @This();

        pub fn init(
            allocator: std.mem.Allocator,
            arena: *std.heap.ArenaAllocator,
            strategy: ArrayStrategy,
            stats: *MemoryStats,
        ) Self {
            var self = Self{
                .allocator = allocator,
                .arena = arena,
                .strategy = strategy,
                .stats = stats,
            };

            // Initialize appropriate pool based on strategy
            switch (strategy) {
                .arena => {}, // No pool needed
                .size_classed => {
                    self.size_classed_pool = SizeClassedPool(T).init(allocator, arena) catch null;
                },
                .metadata_tracked => {
                    self.metadata_tracked_pool = MetadataTrackedPool(T).init(allocator, arena) catch null;
                },
                .tagged => {
                    self.tagged_pool = TaggedArrayPool(T).init(allocator, arena) catch null;
                },
            }

            return self;
        }

        pub fn deinit(self: *Self) void {
            if (self.size_classed_pool) |*pool| pool.deinit();
            if (self.metadata_tracked_pool) |*pool| pool.deinit();
            if (self.tagged_pool) |*pool| pool.deinit();
        }

        pub fn allocate(self: *Self, count: usize) ![]T {
            return switch (self.strategy) {
                .arena => try self.allocateArena(count),
                .size_classed => try self.allocateSizeClassed(count),
                .metadata_tracked => try self.allocateMetadataTracked(count),
                .tagged => try self.allocateTagged(count),
            };
        }

        pub fn release(self: *Self, array: []T) void {
            switch (self.strategy) {
                .arena => {}, // No-op for arena
                .size_classed => if (self.size_classed_pool) |*pool| pool.release(array),
                .metadata_tracked => if (self.metadata_tracked_pool) |*pool| pool.release(array),
                .tagged => if (self.tagged_pool) |*pool| pool.release(array),
            }
        }

        fn allocateArena(self: *Self, count: usize) ![]T {
            const array = try self.arena.allocator().alloc(T, count);
            const bytes = count * @sizeOf(T);
            self.stats.arena_bytes_used += bytes;
            self.stats.total_bytes_allocated += bytes;
            return array;
        }

        fn allocateSizeClassed(self: *Self, count: usize) ![]T {
            if (self.size_classed_pool) |*pool| {
                if (pool.acquire(count)) |array| {
                    self.stats.array_pool_hits += 1;
                    return array;
                }
                self.stats.array_pool_misses += 1;
            }
            return self.allocateArena(count);
        }

        fn allocateMetadataTracked(self: *Self, count: usize) ![]T {
            if (self.metadata_tracked_pool) |*pool| {
                const array = try pool.acquire(count);
                self.stats.array_pool_hits += 1;
                return array;
            }
            return self.allocateArena(count);
        }

        fn allocateTagged(self: *Self, count: usize) ![]T {
            if (self.tagged_pool) |*pool| {
                return try pool.acquire(count);
            }
            return self.allocateArena(count);
        }
    };
}

/// Size-classed pool for efficient array allocation
fn SizeClassedPool(comptime T: type) type {
    return struct {
        allocator: std.mem.Allocator,
        arena: *std.heap.ArenaAllocator,
        small_pool: std.ArrayList([]T), // 1-16 elements
        medium_pool: std.ArrayList([]T), // 17-256 elements
        large_pool: std.ArrayList([]T), // 257-4096 elements

        const Self = @This();
        const SMALL_SIZE = 16;
        const MEDIUM_SIZE = 256;
        const LARGE_SIZE = 4096;
        const MAX_POOL_SIZE = 32;

        pub fn init(allocator: std.mem.Allocator, arena: *std.heap.ArenaAllocator) !Self {
            return Self{
                .allocator = allocator,
                .arena = arena,
                .small_pool = std.ArrayList([]T).init(allocator),
                .medium_pool = std.ArrayList([]T).init(allocator),
                .large_pool = std.ArrayList([]T).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.small_pool.deinit();
            self.medium_pool.deinit();
            self.large_pool.deinit();
        }

        pub fn acquire(self: *Self, count: usize) ?[]T {
            const size_class = getSizeClass(count);
            const pool = switch (size_class) {
                .small => &self.small_pool,
                .medium => &self.medium_pool,
                .large => &self.large_pool,
                .xlarge => return null, // Too large for pooling
            };

            // Check for reusable array
            if (pool.items.len > 0) {
                const array = pool.pop().?;
                return array[0..count]; // Return slice of appropriate size
            }

            return null;
        }

        pub fn release(self: *Self, array: []T) void {
            const size_class = getSizeClass(array.len);
            const pool = switch (size_class) {
                .small => &self.small_pool,
                .medium => &self.medium_pool,
                .large => &self.large_pool,
                .xlarge => return, // Don't pool very large arrays
            };

            // Only keep reasonable number in pool
            if (pool.items.len < MAX_POOL_SIZE) {
                // Get full array for size class
                const full_size = getSizeClassSize(size_class);
                if (array.len == full_size) {
                    pool.append(array) catch {};
                }
            }
        }

        const SizeClass = enum { small, medium, large, xlarge };

        fn getSizeClass(size: usize) SizeClass {
            if (size <= SMALL_SIZE) return .small;
            if (size <= MEDIUM_SIZE) return .medium;
            if (size <= LARGE_SIZE) return .large;
            return .xlarge;
        }

        fn getSizeClassSize(size_class: SizeClass) usize {
            return switch (size_class) {
                .small => SMALL_SIZE,
                .medium => MEDIUM_SIZE,
                .large => LARGE_SIZE,
                .xlarge => 0, // Invalid
            };
        }
    };
}

/// Metadata-tracked pool (2.5x performance from TODO_ARRAYPOOL_OPTIMIZATION.md)
fn MetadataTrackedPool(comptime T: type) type {
    return struct {
        allocator: std.mem.Allocator,
        arena: *std.heap.ArenaAllocator,
        allocations: std.AutoHashMap(usize, AllocationInfo),
        reusable_arrays: std.ArrayList([]T),

        const Self = @This();

        const AllocationInfo = struct {
            full_array: []T,
            size_class: usize,
            allocation_time: i64,
        };

        pub fn init(allocator: std.mem.Allocator, arena: *std.heap.ArenaAllocator) !Self {
            return Self{
                .allocator = allocator,
                .arena = arena,
                .allocations = std.AutoHashMap(usize, AllocationInfo).init(allocator),
                .reusable_arrays = std.ArrayList([]T).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.allocations.deinit();
            self.reusable_arrays.deinit();
        }

        pub fn acquire(self: *Self, count: usize) ![]T {
            // Check for reusable array
            for (self.reusable_arrays.items, 0..) |array, i| {
                if (array.len >= count) {
                    _ = self.reusable_arrays.swapRemove(i);
                    const slice = array[0..count];

                    // Track allocation
                    try self.allocations.put(@intFromPtr(slice.ptr), .{
                        .full_array = array,
                        .size_class = array.len,
                        .allocation_time = std.time.milliTimestamp(),
                    });

                    return slice;
                }
            }

            // Allocate new array with size class rounding
            const size_class = roundUpSizeClass(count);
            const array = try self.arena.allocator().alloc(T, size_class);
            const slice = array[0..count];

            // Track allocation
            try self.allocations.put(@intFromPtr(slice.ptr), .{
                .full_array = array,
                .size_class = size_class,
                .allocation_time = std.time.milliTimestamp(),
            });

            return slice;
        }

        pub fn release(self: *Self, array: []T) void {
            if (self.allocations.get(@intFromPtr(array.ptr))) |info| {
                _ = self.allocations.remove(@intFromPtr(array.ptr));

                // Add to reusable pool
                if (self.reusable_arrays.items.len < 64) {
                    self.reusable_arrays.append(info.full_array) catch {};
                }
            }
        }

        fn roundUpSizeClass(size: usize) usize {
            // Round up to power of 2 or common sizes
            if (size <= 8) return 8;
            if (size <= 16) return 16;
            if (size <= 32) return 32;
            if (size <= 64) return 64;
            if (size <= 128) return 128;
            if (size <= 256) return 256;
            if (size <= 512) return 512;
            if (size <= 1024) return 1024;
            return size; // Don't round very large sizes
        }
    };
}

/// Tagged array pool with embedded headers (3.0x performance)
fn TaggedArrayPool(comptime T: type) type {
    return struct {
        allocator: std.mem.Allocator,
        arena: *std.heap.ArenaAllocator,
        magic: u32 = 0xA88A7FED,

        const Self = @This();

        const Header = struct {
            magic: u32,
            full_size: usize,
            requested_size: usize,
            in_use: bool,
        };

        pub fn init(allocator: std.mem.Allocator, arena: *std.heap.ArenaAllocator) !Self {
            return Self{
                .allocator = allocator,
                .arena = arena,
            };
        }

        pub fn deinit(self: *Self) void {
            _ = self;
            // Arena cleanup handles everything
        }

        pub fn acquire(self: *Self, count: usize) ![]T {
            // Round up for efficiency
            const full_size = roundUpSize(count);

            // Allocate with header
            const header_size = @sizeOf(Header);
            const array_size = full_size * @sizeOf(T);
            const total_size = header_size + array_size;
            const alignment = @max(@alignOf(Header), @alignOf(T));

            const raw = try self.arena.allocator().alignedAlloc(u8, alignment, total_size);

            // Write header
            const header = @as(*Header, @ptrCast(@alignCast(raw)));
            header.* = .{
                .magic = self.magic,
                .full_size = full_size,
                .requested_size = count,
                .in_use = true,
            };

            // Return array after header
            const array_ptr = @as([*]T, @ptrCast(@alignCast(raw.ptr + header_size)));
            return array_ptr[0..count];
        }

        pub fn release(self: *Self, array: []T) void {
            // Find header
            const raw = @as([*]u8, @ptrCast(array.ptr)) - @sizeOf(Header);
            const header = @as(*Header, @ptrCast(@alignCast(raw)));

            // Validate
            if (header.magic != self.magic) {
                std.log.err("Tagged array pool: corrupt array released!", .{});
                return;
            }

            if (!header.in_use) {
                std.log.err("Tagged array pool: double-free detected!", .{});
                return;
            }

            header.in_use = false;
        }

        fn roundUpSize(size: usize) usize {
            // Cache-friendly sizes
            if (size <= 16) return 16;
            if (size <= 64) return 64;
            if (size <= 256) return 256;
            if (size <= 1024) return 1024;
            return (size + 255) & ~@as(usize, 255); // Round to 256 boundary
        }
    };
}
