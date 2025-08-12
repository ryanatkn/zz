const std = @import("std");
const path_utils = @import("path.zig");
const PathCache = @import("string_pool.zig").PathCache;
const MemoryPools = @import("pools.zig").MemoryPools;

/// Benchmark result structure
pub const BenchmarkResult = struct {
    name: []const u8,
    total_operations: usize,
    elapsed_ns: u64,
    ns_per_op: u64,
    memory_used: ?usize = null,
    extra_info: ?[]const u8 = null,
};

/// Simple benchmark utilities for measuring optimization impact
pub const Benchmark = struct {
    allocator: std.mem.Allocator,
    results: std.ArrayList(BenchmarkResult),
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{ 
            .allocator = allocator,
            .results = std.ArrayList(BenchmarkResult).init(allocator),
        };
    }
    
    pub fn deinit(self: *Self) void {
        // Free any allocated extra_info strings
        for (self.results.items) |result| {
            if (result.extra_info) |extra| {
                self.allocator.free(extra);
            }
        }
        self.results.deinit();
    }
    
    /// Benchmark path joining operations
    pub fn benchmarkPathJoining(self: *Self, iterations: usize) !void {
        std.debug.print("\n=== Path Joining Benchmark ===\n", .{});
        
        const dirs = [_][]const u8{ "src", "test", "docs", "lib", "config" };
        const files = [_][]const u8{ "main.zig", "test.zig", "config.zig", "lib.zig" };
        
        // Benchmark optimized joinPath
        var timer = try std.time.Timer.start();
        var total_allocations: usize = 0;
        
        for (0..iterations) |_| {
            for (dirs) |dir| {
                for (files) |file| {
                    const joined = try path_utils.joinPath(self.allocator, dir, file);
                    self.allocator.free(joined);
                    total_allocations += 1;
                }
            }
        }
        
        const elapsed = timer.read();
        const ns_per_op = elapsed / total_allocations;
        
        std.debug.print("Optimized joinPath: {} operations in {}ms ({} ns/op)\n", 
            .{ total_allocations, elapsed / 1_000_000, ns_per_op });
        
        try self.results.append(.{
            .name = "Path Joining",
            .total_operations = total_allocations,
            .elapsed_ns = elapsed,
            .ns_per_op = ns_per_op,
        });
    }
    
    /// Benchmark string pool effectiveness
    pub fn benchmarkStringPool(self: *Self, iterations: usize) !void {
        std.debug.print("\n=== String Pool Benchmark ===\n", .{});
        
        var path_cache = try PathCache.init(self.allocator);
        defer path_cache.deinit();
        
        const common_paths = [_][]const u8{ 
            "src", "test", "lib", "docs", "config", "main.zig", "test.zig" 
        };
        
        var timer = try std.time.Timer.start();
        
        // Test cache effectiveness
        for (0..iterations) |_| {
            for (common_paths) |path| {
                _ = try path_cache.getPath(path);
            }
        }
        
        const elapsed = timer.read();
        const pool = path_cache.getStats();
        const pool_stats = pool.stats();
        
        const total_ops = iterations * common_paths.len;
        std.debug.print("PathCache: {} operations in {}ms\n", .{ total_ops, elapsed / 1_000_000 });
        std.debug.print("Cache efficiency: {d:.1}% ({} hits, {} misses)\n", 
            .{ pool_stats.efficiency * 100, pool_stats.hits, pool_stats.misses });
        
        var extra_info_buf: [256]u8 = undefined;
        const extra_info = try std.fmt.bufPrint(&extra_info_buf, "Cache efficiency: {d:.1}%", .{pool_stats.efficiency * 100});
        
        try self.results.append(.{
            .name = "String Pool",
            .total_operations = total_ops,
            .elapsed_ns = elapsed,
            .ns_per_op = elapsed / total_ops,
            .extra_info = try self.allocator.dupe(u8, extra_info),
        });
    }
    
    /// Benchmark memory pools
    pub fn benchmarkMemoryPools(self: *Self, iterations: usize) !void {
        std.debug.print("\n=== Memory Pools Benchmark ===\n", .{});
        
        var pools = MemoryPools.init(self.allocator);
        defer pools.deinit();
        
        var timer = try std.time.Timer.start();
        
        // Test ArrayList pooling
        for (0..iterations) |_| {
            var list = try pools.createPathList();
            try list.append(try self.allocator.dupe(u8, "test"));
            for (list.items) |item| {
                self.allocator.free(item);
            }
            pools.releasePathList(list);
        }
        
        const elapsed = timer.read();
        const ns_per_op = elapsed / iterations;
        
        std.debug.print("Memory pools: {} operations in {}ms ({} ns/op)\n", 
            .{ iterations, elapsed / 1_000_000, ns_per_op });
        
        try self.results.append(.{
            .name = "Memory Pools",
            .total_operations = iterations,
            .elapsed_ns = elapsed,
            .ns_per_op = ns_per_op,
        });
    }
    
    /// Benchmark glob pattern optimization
    pub fn benchmarkGlobPatterns(self: *Self, iterations: usize) !void {
        std.debug.print("\n=== Glob Pattern Benchmark ===\n", .{});
        
        const patterns = [_][]const u8{
            "*.{zig,c,h}",
            "*.{js,ts}",
            "*.{md,txt}",
            "src/**/*.zig",
        };
        
        var timer = try std.time.Timer.start();
        
        // This would require integrating with GlobExpander
        // For now, just measure pattern checking
        var fast_path_hits: usize = 0;
        
        for (0..iterations) |_| {
            for (patterns) |pattern| {
                // Simulate fast path checking
                if (std.mem.eql(u8, pattern, "*.{zig,c,h}") or
                    std.mem.eql(u8, pattern, "*.{js,ts}") or
                    std.mem.eql(u8, pattern, "*.{md,txt}")) {
                    fast_path_hits += 1;
                }
            }
        }
        
        const elapsed = timer.read();
        const total_patterns = iterations * patterns.len;
        const fast_path_ratio = @as(f64, @floatFromInt(fast_path_hits)) / @as(f64, @floatFromInt(total_patterns));
        
        std.debug.print("Pattern matching: {} patterns in {}ms\n", .{ total_patterns, elapsed / 1_000_000 });
        std.debug.print("Fast path hit ratio: {d:.1}%\n", .{ fast_path_ratio * 100 });
        
        var extra_info_buf: [256]u8 = undefined;
        const extra_info = try std.fmt.bufPrint(&extra_info_buf, "Fast path hit ratio: {d:.1}%", .{fast_path_ratio * 100});
        
        try self.results.append(.{
            .name = "Glob Patterns",
            .total_operations = total_patterns,
            .elapsed_ns = elapsed,
            .ns_per_op = elapsed / total_patterns,
            .extra_info = try self.allocator.dupe(u8, extra_info),
        });
    }
    
    /// Run all benchmarks
    pub fn runAll(self: *Self, iterations: usize) !void {
        std.debug.print("Running performance benchmarks with {} iterations...\n", .{iterations});
        
        try self.benchmarkPathJoining(iterations);
        try self.benchmarkStringPool(iterations);
        try self.benchmarkMemoryPools(iterations);
        try self.benchmarkGlobPatterns(iterations);
        
        std.debug.print("\n=== Benchmark Complete ===\n");
    }
    
    /// Get all benchmark results
    pub fn getResults(self: Self) []const BenchmarkResult {
        return self.results.items;
    }
};