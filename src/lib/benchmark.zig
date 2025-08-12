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
    
    /// Write results to markdown format
    pub fn writeMarkdown(
        self: Self,
        writer: anytype,
        baseline_results: ?[]const BenchmarkResult,
        build_mode: []const u8,
        iterations: usize,
    ) !void {
        // Header
        try writer.print("# Benchmark Results\n\n", .{});
        
        // Metadata
        const timestamp = std.time.timestamp();
        const date_time = std.time.epoch.EpochSeconds{ .secs = @intCast(timestamp) };
        try writer.print("**Date:** {d}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}  \n", .{
            date_time.getEpochDay().calculateYearDay().year,
            date_time.getEpochDay().calculateYearDay().calculateMonthDay().month.numeric(),
            date_time.getEpochDay().calculateYearDay().calculateMonthDay().day_index + 1,
            date_time.getDaySeconds().getHoursIntoDay(),
            date_time.getDaySeconds().getMinutesIntoHour(),
            date_time.getDaySeconds().getSecondsIntoMinute(),
        });
        try writer.print("**Build:** {s}  \n", .{build_mode});
        try writer.print("**Iterations:** {}  \n\n", .{iterations});
        
        // Results table
        try writer.print("## Results\n\n", .{});
        try writer.print("| Benchmark | Operations | Time (ms) | ns/op |", .{});
        if (baseline_results != null) {
            try writer.print(" Baseline | Change |", .{});
        }
        try writer.print("\n", .{});
        
        try writer.print("|-----------|------------|-----------|-------|", .{});
        if (baseline_results != null) {
            try writer.print("----------|--------|", .{});
        }
        try writer.print("\n", .{});
        
        // Data rows
        for (self.results.items) |result| {
            try writer.print("| {s} | {} | {} | {} |", .{
                result.name,
                result.total_operations,
                result.elapsed_ns / 1_000_000,
                result.ns_per_op,
            });
            
            if (baseline_results) |baseline| {
                // Find matching baseline
                const baseline_result = for (baseline) |b| {
                    if (std.mem.eql(u8, b.name, result.name)) break b;
                } else null;
                
                if (baseline_result) |base| {
                    const change = @as(f64, @floatFromInt(result.ns_per_op)) / 
                                  @as(f64, @floatFromInt(base.ns_per_op)) - 1.0;
                    const change_pct = change * 100.0;
                    
                    try writer.print(" {} | {s}{d:.1}% |", .{
                        base.ns_per_op,
                        if (change > 0) "+" else "",
                        change_pct,
                    });
                } else {
                    try writer.print(" - | N/A |", .{});
                }
            }
            try writer.print("\n", .{});
        }
        
        // Extra info section if any
        try writer.print("\n## Notes\n\n", .{});
        for (self.results.items) |result| {
            if (result.extra_info) |info| {
                try writer.print("- **{s}:** {s}\n", .{ result.name, info });
            }
        }
    }
    
    /// Load benchmark results from markdown file
    pub fn loadFromMarkdown(allocator: std.mem.Allocator, content: []const u8) ![]BenchmarkResult {
        var results = std.ArrayList(BenchmarkResult).init(allocator);
        errdefer results.deinit();
        
        var lines = std.mem.tokenizeScalar(u8, content, '\n');
        var in_table = false;
        var skip_header = true;
        
        while (lines.next()) |line| {
            // Look for table start
            if (!in_table) {
                if (std.mem.indexOf(u8, line, "| Benchmark |") != null) {
                    in_table = true;
                    skip_header = true;
                }
                continue;
            }
            
            // Skip header separator
            if (skip_header and std.mem.indexOf(u8, line, "|---") != null) {
                skip_header = false;
                continue;
            }
            
            // Parse data row
            if (line[0] == '|') {
                var parts = std.mem.tokenizeScalar(u8, line, '|');
                
                const name = std.mem.trim(u8, parts.next() orelse continue, " ");
                const ops_str = std.mem.trim(u8, parts.next() orelse continue, " ");
                _ = parts.next(); // Skip time_ms
                const ns_op_str = std.mem.trim(u8, parts.next() orelse continue, " ");
                
                const ops = std.fmt.parseInt(usize, ops_str, 10) catch continue;
                const ns_op = std.fmt.parseInt(u64, ns_op_str, 10) catch continue;
                
                try results.append(.{
                    .name = try allocator.dupe(u8, name),
                    .total_operations = ops,
                    .elapsed_ns = ns_op * ops,
                    .ns_per_op = ns_op,
                });
            }
        }
        
        return results.toOwnedSlice();
    }
};