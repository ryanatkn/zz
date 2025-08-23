const std = @import("std");
const NodeStrategy = @import("strategy.zig").NodeStrategy;
const MemoryStats = @import("stats.zig").MemoryStats;

/// Specialized node allocator with strategy-based dispatch
pub fn NodeAllocator(comptime NodeType: type) type {
    return struct {
        allocator: std.mem.Allocator,
        arena: *std.heap.ArenaAllocator,
        strategy: NodeStrategy,
        stats: *MemoryStats,

        // Pool implementations
        small_pool: ?SmallNodePool(NodeType) = null,
        large_pool: ?LargeNodePool(NodeType) = null,
        tagged_pool: ?TaggedNodePool(NodeType) = null,

        const Self = @This();

        pub fn init(
            allocator: std.mem.Allocator,
            arena: *std.heap.ArenaAllocator,
            strategy: NodeStrategy,
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
                .small_pool => {
                    self.small_pool = SmallNodePool(NodeType).init(allocator, 256) catch null;
                    if (self.small_pool) |pool| {
                        stats.node_pool_capacity = pool.capacity;
                    }
                },
                .large_pool => {
                    self.large_pool = LargeNodePool(NodeType).init(allocator, 4096) catch null;
                    if (self.large_pool) |pool| {
                        stats.node_pool_capacity = pool.capacity;
                    }
                },
                .tagged => {
                    self.tagged_pool = TaggedNodePool(NodeType).init(allocator, arena) catch null;
                },
            }

            return self;
        }

        pub fn deinit(self: *Self) void {
            if (self.small_pool) |*pool| pool.deinit();
            if (self.large_pool) |*pool| pool.deinit();
            if (self.tagged_pool) |*pool| pool.deinit();
        }

        pub fn allocate(self: *Self) !*NodeType {
            return switch (self.strategy) {
                .arena => try self.allocateArena(),
                .small_pool => try self.allocateSmallPool(),
                .large_pool => try self.allocateLargePool(),
                .tagged => try self.allocateTagged(),
            };
        }

        pub fn release(self: *Self, node: *NodeType) void {
            switch (self.strategy) {
                .arena => {}, // No-op for arena
                .small_pool => if (self.small_pool) |*pool| pool.release(node),
                .large_pool => if (self.large_pool) |*pool| pool.release(node),
                .tagged => if (self.tagged_pool) |*pool| pool.release(node),
            }
        }

        fn allocateArena(self: *Self) !*NodeType {
            const node = try self.arena.allocator().create(NodeType);
            const node_size = @sizeOf(NodeType);
            self.stats.arena_bytes_used += node_size;
            self.stats.total_bytes_allocated += node_size;
            return node;
        }

        fn allocateSmallPool(self: *Self) !*NodeType {
            if (self.small_pool) |*pool| {
                if (pool.acquire()) |node| {
                    self.stats.node_pool_hits += 1;
                    return node;
                }
                self.stats.node_pool_misses += 1;
            }
            // Fallback to arena
            return self.allocateArena();
        }

        fn allocateLargePool(self: *Self) !*NodeType {
            if (self.large_pool) |*pool| {
                if (pool.acquire()) |node| {
                    self.stats.node_pool_hits += 1;
                    return node;
                }
                self.stats.node_pool_misses += 1;
            }
            // Fallback to arena
            return self.allocateArena();
        }

        fn allocateTagged(self: *Self) !*NodeType {
            if (self.tagged_pool) |*pool| {
                return try pool.acquire();
            }
            // Fallback to arena
            return self.allocateArena();
        }
    };
}

/// Small node pool for frequent small allocations
fn SmallNodePool(comptime T: type) type {
    return struct {
        allocator: std.mem.Allocator,
        capacity: usize,
        available: std.ArrayList(*T),
        allocated: std.ArrayList(*T),

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator, capacity: usize) !Self {
            var pool = Self{
                .allocator = allocator,
                .capacity = capacity,
                .available = try std.ArrayList(*T).initCapacity(allocator, capacity),
                .allocated = try std.ArrayList(*T).initCapacity(allocator, capacity),
            };

            // Pre-allocate nodes
            for (0..capacity) |_| {
                const node = try allocator.create(T);
                try pool.available.append(node);
            }

            return pool;
        }

        pub fn deinit(self: *Self) void {
            for (self.available.items) |node| {
                self.allocator.destroy(node);
            }
            for (self.allocated.items) |node| {
                self.allocator.destroy(node);
            }
            self.available.deinit();
            self.allocated.deinit();
        }

        pub fn acquire(self: *Self) ?*T {
            if (self.available.items.len > 0) {
                const node = self.available.pop().?;
                self.allocated.append(node) catch return null;
                return node;
            }
            return null;
        }

        pub fn release(self: *Self, node: *T) void {
            // Find and remove from allocated list
            for (self.allocated.items, 0..) |allocated_node, i| {
                if (allocated_node == node) {
                    _ = self.allocated.swapRemove(i);
                    self.available.append(node) catch {
                        // Pool full, destroy the node
                        self.allocator.destroy(node);
                    };
                    return;
                }
            }
        }
    };
}

/// Large node pool for complex structures
fn LargeNodePool(comptime T: type) type {
    return struct {
        allocator: std.mem.Allocator,
        capacity: usize,
        available: std.ArrayList(*T),
        allocated: std.ArrayList(*T),
        high_water_mark: usize = 0,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator, capacity: usize) !Self {
            var pool = Self{
                .allocator = allocator,
                .capacity = capacity,
                .available = try std.ArrayList(*T).initCapacity(allocator, capacity),
                .allocated = try std.ArrayList(*T).initCapacity(allocator, capacity),
            };

            // Start with smaller pre-allocation for large pool
            const initial_count = @min(64, capacity);
            for (0..initial_count) |_| {
                const node = try allocator.create(T);
                try pool.available.append(node);
            }

            return pool;
        }

        pub fn deinit(self: *Self) void {
            for (self.available.items) |node| {
                self.allocator.destroy(node);
            }
            for (self.allocated.items) |node| {
                self.allocator.destroy(node);
            }
            self.available.deinit();
            self.allocated.deinit();
        }

        pub fn acquire(self: *Self) ?*T {
            if (self.available.items.len > 0) {
                const node = self.available.pop().?;
                self.allocated.append(node) catch return null;
                self.high_water_mark = @max(self.high_water_mark, self.allocated.items.len);
                return node;
            }

            // Try to grow pool if under capacity
            if (self.allocated.items.len < self.capacity) {
                const node = self.allocator.create(T) catch return null;
                self.allocated.append(node) catch {
                    self.allocator.destroy(node);
                    return null;
                };
                self.high_water_mark = @max(self.high_water_mark, self.allocated.items.len);
                return node;
            }

            return null;
        }

        pub fn release(self: *Self, node: *T) void {
            for (self.allocated.items, 0..) |allocated_node, i| {
                if (allocated_node == node) {
                    _ = self.allocated.swapRemove(i);

                    // Keep pool size reasonable
                    if (self.available.items.len < self.capacity / 2) {
                        self.available.append(node) catch {
                            self.allocator.destroy(node);
                        };
                    } else {
                        self.allocator.destroy(node);
                    }
                    return;
                }
            }
        }
    };
}

/// Tagged node pool with embedded metadata (3.0x performance from TODO_ARRAYPOOL_OPTIMIZATION.md)
fn TaggedNodePool(comptime T: type) type {
    return struct {
        allocator: std.mem.Allocator,
        arena: *std.heap.ArenaAllocator,
        magic: u32 = 0xFEEDFACE,

        const Self = @This();
        const Header = struct {
            magic: u32,
            size: usize,
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

        pub fn acquire(self: *Self) !*T {
            // Allocate with header
            const total_size = @sizeOf(Header) + @sizeOf(T);
            const alignment = @max(@alignOf(Header), @alignOf(T));

            const raw = try self.arena.allocator().alignedAlloc(u8, alignment, total_size);

            // Write header
            const header = @as(*Header, @ptrCast(@alignCast(raw)));
            header.* = .{
                .magic = self.magic,
                .size = @sizeOf(T),
                .in_use = true,
            };

            // Return node after header
            const node_ptr = @as(*T, @ptrCast(@alignCast(raw.ptr + @sizeOf(Header))));
            return node_ptr;
        }

        pub fn release(self: *Self, node: *T) void {
            // Find header
            const raw = @as([*]u8, @ptrCast(node)) - @sizeOf(Header);
            const header = @as(*Header, @ptrCast(@alignCast(raw)));

            // Validate magic
            if (header.magic != self.magic) {
                std.log.err("Tagged node pool: corrupt node released!", .{});
                return;
            }

            // Check double-free
            if (!header.in_use) {
                std.log.err("Tagged node pool: double-free detected!", .{});
                return;
            }

            header.in_use = false;
            // Arena handles actual memory cleanup
        }
    };
}
