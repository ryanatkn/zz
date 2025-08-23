const std = @import("std");
const MemoryStrategy = @import("strategy.zig").MemoryStrategy;
const MemoryStats = @import("stats.zig").MemoryStats;
const NodeAllocator = @import("node_allocator.zig").NodeAllocator;
const ArrayAllocator = @import("array_allocator.zig").ArrayAllocator;
const StringAllocator = @import("string_allocator.zig").StringAllocator;

/// Generic memory management context with composed strategy support
pub fn MemoryContext(comptime NodeType: type) type {
    return struct {
        /// Main allocator for persistent allocations
        allocator: std.mem.Allocator,
        /// Arena for temporary parse-time allocations (heap-allocated to avoid move issues)
        arena: *std.heap.ArenaAllocator,
        /// Current memory strategy
        strategy: MemoryStrategy,
        
        /// Specialized allocators based on strategy
        node_allocator: NodeAllocator(NodeType),
        array_allocator: ArrayAllocator(NodeType),
        string_allocator: StringAllocator,
        
        /// Texts that will be transferred to AST ownership
        transferred_texts: std.ArrayList([]const u8),
        /// Node arrays that will be transferred to AST ownership
        transferred_nodes: std.ArrayList([]NodeType),
        
        /// Memory usage statistics
        stats: MemoryStats = .{},
        
        /// For adaptive strategies
        last_sample_time: i64 = 0,
        allocation_count_since_sample: usize = 0,
        
        const Self = @This();
        
        /// Initialize memory context with specified strategy
        pub fn init(allocator: std.mem.Allocator, strategy: MemoryStrategy) Self {
            // Create arena on heap to avoid move issues
            const arena = allocator.create(std.heap.ArenaAllocator) catch unreachable;
            arena.* = std.heap.ArenaAllocator.init(allocator);
            
            var ctx = Self{
                .allocator = allocator,
                .arena = arena,
                .strategy = strategy,
                .node_allocator = undefined, // Will be set after init
                .array_allocator = undefined, // Will be set after init
                .string_allocator = undefined, // Will be set after init
                .transferred_texts = std.ArrayList([]const u8).init(allocator),
                .transferred_nodes = std.ArrayList([]NodeType).init(allocator),
                .stats = MemoryStats{},
            };
            
            // Initialize allocators now that arena is stable
            ctx.initializeAllocators();
            
            return ctx;
        }

        /// Re-initialize allocators after the context has been moved to its final location
        pub fn finalizeInit(self: *Self) void {
            self.initializeAllocators();
            
            // Pre-warm pools if beneficial
            if (self.strategy.shouldPrewarm()) {
                self.prewarmPools() catch |err| {
                    std.log.warn("Failed to prewarm pools: {}", .{err});
                };
            }
        }
        
        /// Static function to get node strategy from a strategy
        fn getNodeStrategyFor(strategy: MemoryStrategy) @import("strategy.zig").NodeStrategy {
            return switch (strategy) {
                .arena_only => .arena,
                .pooled => .small_pool,
                .hybrid => |h| h.nodes,
                .adaptive => |a| switch (a.initial.*) {
                    .hybrid => |h| h.nodes,
                    .pooled => .small_pool,
                    else => .arena,
                },
                .metadata_tracked => .tagged,
                .tagged_allocation => .tagged,
                .custom => .arena,
            };
        }
        
        /// Static function to get array strategy from a strategy
        fn getArrayStrategyFor(strategy: MemoryStrategy) @import("strategy.zig").ArrayStrategy {
            return switch (strategy) {
                .arena_only => .arena,
                .pooled => .size_classed,
                .hybrid => |h| h.arrays,
                .adaptive => |a| switch (a.initial.*) {
                    .hybrid => |h| h.arrays,
                    .pooled => .size_classed,
                    else => .arena,
                },
                .metadata_tracked => .metadata_tracked,
                .tagged_allocation => .tagged,
                .custom => .arena,
            };
        }
        
        /// Static function to get string strategy from a strategy
        fn getStringStrategyFor(strategy: MemoryStrategy) @import("strategy.zig").StringStrategy {
            return switch (strategy) {
                .arena_only => .arena,
                .pooled => .persistent,
                .hybrid => |h| h.strings,
                .adaptive => |a| switch (a.initial.*) {
                    .hybrid => |h| h.strings,
                    .pooled => .persistent,
                    else => .arena,
                },
                .metadata_tracked => .persistent,
                .tagged_allocation => .persistent,
                .custom => .persistent,
            };
        }
        
        /// Initialize specialized allocators based on current strategy
        fn initializeAllocators(self: *Self) void {
            const node_strat = getNodeStrategyFor(self.strategy);
            const array_strat = getArrayStrategyFor(self.strategy);
            const string_strat = getStringStrategyFor(self.strategy);
            
            self.node_allocator = NodeAllocator(NodeType).init(
                self.allocator,
                self.arena,  // Arena is now a pointer, not a value
                node_strat,
                &self.stats,
            );
            
            self.array_allocator = ArrayAllocator(NodeType).init(
                self.allocator,
                self.arena,  // Arena is now a pointer, not a value
                array_strat,
                &self.stats,
            );
            
            self.string_allocator = StringAllocator.init(
                self.allocator,
                self.arena,  // Arena is now a pointer, not a value
                string_strat,
                &self.stats,
            );
        }
        
        /// Get node allocation strategy from current strategy
        fn getNodeStrategy(self: Self) @import("strategy.zig").NodeStrategy {
            return switch (self.strategy) {
                .arena_only => .arena,
                .pooled => .small_pool,
                .hybrid => |h| h.nodes,
                .adaptive => |a| switch (a.initial.*) {
                    .hybrid => |h| h.nodes,
                    .pooled => .small_pool,
                    else => .arena,
                },
                .metadata_tracked => .tagged,
                .tagged_allocation => .tagged,
                .custom => .arena, // Default to arena for custom
            };
        }
        
        /// Get array allocation strategy from current strategy
        fn getArrayStrategy(self: Self) @import("strategy.zig").ArrayStrategy {
            return switch (self.strategy) {
                .arena_only => .arena,
                .pooled => .size_classed,
                .hybrid => |h| h.arrays,
                .adaptive => |a| switch (a.initial.*) {
                    .hybrid => |h| h.arrays,
                    .pooled => .size_classed,
                    else => .arena,
                },
                .metadata_tracked => .metadata_tracked,
                .tagged_allocation => .tagged,
                .custom => .arena,
            };
        }
        
        /// Get string allocation strategy from current strategy
        fn getStringStrategy(self: Self) @import("strategy.zig").StringStrategy {
            return switch (self.strategy) {
                .arena_only => .arena,
                .pooled => .persistent,
                .hybrid => |h| h.strings,
                .adaptive => |a| switch (a.initial.*) {
                    .hybrid => |h| h.strings,
                    .pooled => .persistent,
                    else => .arena,
                },
                .metadata_tracked => .persistent,
                .tagged_allocation => .persistent,
                .custom => .persistent,
            };
        }
        
        /// Reinitialize allocators when strategy changes
        fn reinitializeAllocators(self: *Self) void {
            // Deinit old allocators
            self.node_allocator.deinit();
            self.array_allocator.deinit();
            self.string_allocator.deinit();
            
            // Get new strategies
            const node_strat = getNodeStrategyFor(self.strategy);
            const array_strat = getArrayStrategyFor(self.strategy);
            const string_strat = getStringStrategyFor(self.strategy);
            
            // Create new allocators
            self.node_allocator = NodeAllocator(NodeType).init(
                self.allocator,
                self.arena,  // Arena is now a pointer, not a value
                node_strat,
                &self.stats,
            );
            
            self.array_allocator = ArrayAllocator(NodeType).init(
                self.allocator,
                self.arena,  // Arena is now a pointer, not a value
                array_strat,
                &self.stats,
            );
            
            self.string_allocator = StringAllocator.init(
                self.allocator,
                self.arena,  // Arena is now a pointer, not a value
                string_strat,
                &self.stats,
            );
        }
        
        /// Pre-warm pools for better initial performance
        fn prewarmPools(self: *Self) !void {
            // Pre-allocate some nodes if using pools
            const node_strat = getNodeStrategyFor(self.strategy);
            if (node_strat != .arena) {
                for (0..16) |_| {
                    const node = try self.node_allocator.allocate();
                    self.node_allocator.release(node);
                }
            }
            
            // Pre-allocate some arrays if using pools
            const array_strat = getArrayStrategyFor(self.strategy);
            if (array_strat != .arena) {
                const small = try self.array_allocator.allocate(8);
                self.array_allocator.release(small);
                
                const medium = try self.array_allocator.allocate(64);
                self.array_allocator.release(medium);
            }
        }
        
        /// Clean up all memory and pools
        pub fn deinit(self: *Self) void {
            // Deinitialize specialized allocators
            self.node_allocator.deinit();
            self.array_allocator.deinit();
            self.string_allocator.deinit();
            
            // Arena automatically frees all temporary allocations
            self.arena.deinit();
            // Free the heap-allocated arena itself
            self.allocator.destroy(self.arena);
            
            // Free tracking arrays (but not the tracked memory itself)
            self.transferred_texts.deinit();
            self.transferred_nodes.deinit();
        }
        
        /// Get arena allocator for temporary allocations
        pub fn tempAllocator(self: *Self) std.mem.Allocator {
            return self.arena.allocator();
        }
        
        /// Allocate a single node
        pub fn allocateNode(self: *Self) !*NodeType {
            const start = std.time.nanoTimestamp();
            defer {
                const end = std.time.nanoTimestamp();
                // Use saturating arithmetic to avoid overflow issues
                if (end > start) {
                    const diff = @as(u64, @intCast(end - start));
                    self.stats.allocation_time_ns +|= diff;
                }
            }
            
            self.stats.nodes_allocated += 1;
            self.allocation_count_since_sample += 1;
            
            // Check for adaptive strategy upgrade
            if (self.shouldCheckAdaptive()) {
                self.checkAdaptiveUpgrade();
            }
            
            return self.node_allocator.allocate();
        }
        
        /// Allocate an array of nodes
        pub fn allocateNodes(self: *Self, count: usize) ![]NodeType {
            const start = std.time.nanoTimestamp();
            defer {
                const end = std.time.nanoTimestamp();
                // Use saturating arithmetic to avoid overflow issues
                if (end > start) {
                    const diff = @as(u64, @intCast(end - start));
                    self.stats.allocation_time_ns +|= diff;
                }
            }
            
            self.stats.arrays_allocated += 1;
            self.allocation_count_since_sample += 1;
            
            return self.array_allocator.allocate(count);
        }
        
        /// Allocate text that will be owned by the AST
        pub fn allocateAstText(self: *Self, text: []const u8) ![]const u8 {
            const start = std.time.nanoTimestamp();
            defer {
                const end = std.time.nanoTimestamp();
                // Use saturating arithmetic to avoid overflow issues
                if (end > start) {
                    const diff = @as(u64, @intCast(end - start));
                    self.stats.allocation_time_ns +|= diff;
                }
            }
            
            self.stats.strings_allocated += 1;
            
            const owned = try self.string_allocator.allocate(text);
            try self.transferred_texts.append(owned);
            
            return owned;
        }
        
        /// Create formatted text that will be owned by the AST
        pub fn allocatePrintAstText(self: *Self, comptime fmt: []const u8, args: anytype) ![]const u8 {
            const text = try std.fmt.allocPrint(self.allocator, fmt, args);
            try self.transferred_texts.append(text);
            self.stats.strings_allocated += 1;
            self.stats.string_bytes_used += text.len;
            return text;
        }
        
        /// Transfer node array to AST ownership
        pub fn transferNodeArray(self: *Self, nodes: []NodeType) ![]NodeType {
            const owned = try self.allocator.dupe(NodeType, nodes);
            try self.transferred_nodes.append(owned);
            return owned;
        }
        
        /// Release a node back to the pool (if using pooled strategy)
        pub fn releaseNode(self: *Self, node: *NodeType) void {
            const start = std.time.nanoTimestamp();
            defer {
                const end = std.time.nanoTimestamp();
                // Use saturating arithmetic to avoid overflow issues
                if (end > start) {
                    const diff = @as(u64, @intCast(end - start));
                    self.stats.deallocation_time_ns +|= diff;
                }
            }
            
            self.node_allocator.release(node);
        }
        
        /// Release node array back to the pool (if using pooled strategy)
        pub fn releaseNodes(self: *Self, nodes: []NodeType) void {
            const start = std.time.nanoTimestamp();
            defer {
                const end = std.time.nanoTimestamp();
                // Use saturating arithmetic to avoid overflow issues
                if (end > start) {
                    const diff = @as(u64, @intCast(end - start));
                    self.stats.deallocation_time_ns +|= diff;
                }
            }
            
            self.array_allocator.release(nodes);
        }
        
        /// Transfer ownership of all AST memory to caller
        pub fn transferOwnership(self: *Self) !TransferredMemory(NodeType) {
            const texts = try self.transferred_texts.toOwnedSlice();
            const nodes = try self.transferred_nodes.toOwnedSlice();
            
            // Update peak memory usage
            self.stats.peak_memory_usage = @max(
                self.stats.peak_memory_usage,
                self.stats.total_bytes_allocated
            );
            
            return TransferredMemory(NodeType){
                .texts = texts,
                .nodes = nodes,
                .stats = self.stats,
            };
        }
        
        /// Get current memory statistics
        pub fn getStats(self: Self) MemoryStats {
            return self.stats;
        }
        
        /// Check if should evaluate adaptive strategy
        fn shouldCheckAdaptive(self: Self) bool {
            if (self.strategy != .adaptive) return false;
            
            const adaptive = self.strategy.adaptive;
            return self.allocation_count_since_sample >= adaptive.config.sample_period;
        }
        
        /// Check and potentially upgrade adaptive strategy
        fn checkAdaptiveUpgrade(self: *Self) void {
            const adaptive = self.strategy.adaptive;
            const current_time = std.time.milliTimestamp();
            
            if (self.last_sample_time == 0) {
                self.last_sample_time = current_time;
                return;
            }
            
            const time_delta_ms = current_time - self.last_sample_time;
            if (time_delta_ms <= 0) return;
            
            const alloc_rate = @as(f32, @floatFromInt(self.allocation_count_since_sample)) / 
                               @as(f32, @floatFromInt(time_delta_ms));
            
            // Check if should upgrade
            if (alloc_rate > adaptive.config.upgrade_threshold or
                self.stats.total_bytes_allocated > adaptive.config.memory_threshold) {
                
                // Upgrade to target strategy
                self.strategy = adaptive.target.*;
                self.stats.strategy_upgrades += 1;
                
                // Reinitialize allocators with new strategy
                self.reinitializeAllocators();
                
                std.log.info("Adaptive strategy upgraded to: {s}", .{self.strategy.describe()});
            }
            
            // Reset counters
            self.last_sample_time = current_time;
            self.allocation_count_since_sample = 0;
        }
        
        /// Force a strategy change (for testing or manual optimization)
        pub fn changeStrategy(self: *Self, new_strategy: MemoryStrategy) void {
            self.strategy = new_strategy;
            self.initializeAllocators();
        }
    };
}

/// Memory ownership transfer for AST lifetime management
pub fn TransferredMemory(comptime NodeType: type) type {
    return struct {
        /// Text strings owned by AST (must be freed with AST)
        texts: []const []const u8,
        /// Node arrays owned by AST (must be freed with AST)
        nodes: []const []NodeType,
        /// Memory statistics for analysis
        stats: MemoryStats,
        
        const Self = @This();
        
        /// Free all transferred memory
        pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
            // Free all transferred texts
            for (self.texts) |text| {
                allocator.free(text);
            }
            allocator.free(self.texts);
            
            // Free all transferred node arrays
            for (self.nodes) |node_array| {
                allocator.free(node_array);
            }
            allocator.free(self.nodes);
        }
    };
}