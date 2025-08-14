const std = @import("std");
const path_utils = @import("path.zig");
const PathCache = @import("memory.zig").PathCache;
const ListPool = @import("memory.zig").ListPool;

/// Benchmark result structure
pub const BenchmarkResult = struct {
    name: []const u8,
    total_operations: usize,
    elapsed_ns: u64,
    ns_per_op: u64,
    memory_used: ?usize = null,
    extra_info: ?[]const u8 = null,
};

/// ANSI color codes for terminal output
const Color = struct {
    const reset = "\x1b[0m";
    const bold = "\x1b[1m";
    const dim = "\x1b[2m";
    const green = "\x1b[32m";
    const yellow = "\x1b[33m";
    const blue = "\x1b[34m";
    const cyan = "\x1b[36m";
    const gray = "\x1b[90m";
    const bright_green = "\x1b[92m";
    const bright_yellow = "\x1b[93m";
};

/// Format time in nanoseconds to human-readable units
pub fn formatTime(ns: u64, buf: []u8) ![]const u8 {
    if (ns < 1000) {
        return try std.fmt.bufPrint(buf, "{} ns", .{ns});
    } else if (ns < 1_000_000) {
        const us = @as(f64, @floatFromInt(ns)) / 1000.0;
        return try std.fmt.bufPrint(buf, "{d:.2} μs", .{us});
    } else if (ns < 1_000_000_000) {
        const ms = @as(f64, @floatFromInt(ns)) / 1_000_000.0;
        return try std.fmt.bufPrint(buf, "{d:.2} ms", .{ms});
    } else {
        const s = @as(f64, @floatFromInt(ns)) / 1_000_000_000.0;
        return try std.fmt.bufPrint(buf, "{d:.2} s", .{s});
    }
}


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
    
    /// Benchmark path joining operations for target duration
    pub fn benchmarkPathJoining(self: *Self, target_duration_ns: u64, verbose: bool) !void {
        if (verbose) {
            std.debug.print("\n=== Path Joining Benchmark ===\n", .{});
        }
        
        const dirs = [_][]const u8{ "src", "test", "docs", "lib", "config" };
        const files = [_][]const u8{ "main.zig", "test.zig", "config.zig", "lib.zig" };
        
        var timer = try std.time.Timer.start();
        var total_allocations: usize = 0;
        
        // Run until we hit the target duration
        while (timer.read() < target_duration_ns) {
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
        
        if (verbose) {
            std.debug.print("  {} operations in {}ms ({} ns/op)\n", 
                .{ total_allocations, elapsed / 1_000_000, ns_per_op });
        }
        
        try self.results.append(.{
            .name = "Path Joining",
            .total_operations = total_allocations,
            .elapsed_ns = elapsed,
            .ns_per_op = ns_per_op,
        });
    }
    
    /// Benchmark string pool effectiveness for target duration
    pub fn benchmarkStringPool(self: *Self, target_duration_ns: u64, verbose: bool) !void {
        if (verbose) {
            std.debug.print("\n=== String Pool Benchmark ===\n", .{});
        }
        
        var path_cache = try PathCache.init(self.allocator);
        defer path_cache.deinit();
        
        const common_paths = [_][]const u8{ 
            "src", "test", "lib", "docs", "config", "main.zig", "test.zig" 
        };
        
        var timer = try std.time.Timer.start();
        var total_ops: usize = 0;
        
        // Run until we hit the target duration
        while (timer.read() < target_duration_ns) {
            for (common_paths) |path| {
                _ = try path_cache.getPath(path);
                total_ops += 1;
            }
        }
        
        const elapsed = timer.read();
        const pool = path_cache.getStats();
        const pool_stats = pool.stats();
        
        if (verbose) {
            std.debug.print("  {} operations in {}ms\n", .{ total_ops, elapsed / 1_000_000 });
            std.debug.print("  Cache efficiency: {d:.1}% ({} hits, {} misses)\n", 
                .{ pool_stats.efficiency * 100, pool_stats.hits, pool_stats.misses });
        }
        
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
    
    /// Benchmark memory pools for target duration
    pub fn benchmarkMemoryPools(self: *Self, target_duration_ns: u64, verbose: bool) !void {
        if (verbose) {
            std.debug.print("\n=== Memory Pools Benchmark ===\n", .{});
        }
        
        var pools = ListPool.init(self.allocator);
        defer pools.deinit();
        
        var timer = try std.time.Timer.start();
        var iterations: usize = 0;
        
        // Run until we hit the target duration
        while (timer.read() < target_duration_ns) {
            var list = pools.getConstStringList();
            try list.append(try self.allocator.dupe(u8, "test"));
            for (list.items) |item| {
                self.allocator.free(item);
            }
            pools.putConstStringList(list);
            iterations += 1;
        }
        
        const elapsed = timer.read();
        const ns_per_op = elapsed / iterations;
        
        if (verbose) {
            std.debug.print("  {} operations in {}ms ({} ns/op)\n", 
                .{ iterations, elapsed / 1_000_000, ns_per_op });
        }
        
        try self.results.append(.{
            .name = "Memory Pools",
            .total_operations = iterations,
            .elapsed_ns = elapsed,
            .ns_per_op = ns_per_op,
        });
    }
    
    /// Benchmark glob pattern optimization for target duration
    pub fn benchmarkGlobPatterns(self: *Self, target_duration_ns: u64, verbose: bool) !void {
        if (verbose) {
            std.debug.print("\n=== Glob Pattern Benchmark ===\n", .{});
        }
        
        const patterns = [_][]const u8{
            "*.{zig,c,h}",
            "*.{js,ts}",
            "*.{md,txt}",
            "src/**/*.zig",
        };
        
        var timer = try std.time.Timer.start();
        var fast_path_hits: usize = 0;
        var total_patterns: usize = 0;
        
        // Run until we hit the target duration
        while (timer.read() < target_duration_ns) {
            for (patterns) |pattern| {
                // Simulate fast path checking
                if (std.mem.eql(u8, pattern, "*.{zig,c,h}") or
                    std.mem.eql(u8, pattern, "*.{js,ts}") or
                    std.mem.eql(u8, pattern, "*.{md,txt}")) {
                    fast_path_hits += 1;
                }
                total_patterns += 1;
            }
        }
        
        const elapsed = timer.read();
        const fast_path_ratio = @as(f64, @floatFromInt(fast_path_hits)) / @as(f64, @floatFromInt(total_patterns));
        
        if (verbose) {
            std.debug.print("  {} patterns in {}ms\n", .{ total_patterns, elapsed / 1_000_000 });
            std.debug.print("  Fast path hit ratio: {d:.1}%\n", .{ fast_path_ratio * 100 });
        }
        
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
    
    /// Benchmark code extraction performance
    pub fn benchmarkExtraction(self: *Self, target_duration_ns: u64, verbose: bool) !void {
        if (verbose) {
            std.debug.print("\n📋 Benchmarking Code Extraction...\n", .{});
        }
        
        const ast = @import("ast.zig");
        const ExtractionFlags = ast.ExtractionFlags;
        
        // Sample Zig code for extraction
        const sample_code = 
            \\const std = @import("std");
            \\
            \\/// Documentation for MyStruct
            \\pub const MyStruct = struct {
            \\    value: u32,
            \\    name: []const u8,
            \\};
            \\
            \\pub fn processData(data: []const u8) !void {
            \\    if (data.len == 0) return error.EmptyData;
            \\    // Process the data
            \\    std.debug.print("Processing: {s}\n", .{data});
            \\}
            \\
            \\test "processData test" {
            \\    try processData("test");
            \\}
            \\
            \\fn privateHelper() void {
            \\    // Helper function
            \\}
        ;
        
        const start = std.time.nanoTimestamp();
        var total_extractions: usize = 0;
        
        // Test different extraction modes
        const extraction_modes = [_]struct { 
            name: []const u8, 
            flags: ExtractionFlags 
        }{
            .{ .name = "full", .flags = ExtractionFlags{ .full = true } },
            .{ .name = "signatures", .flags = ExtractionFlags{ .signatures = true } },
            .{ .name = "types", .flags = ExtractionFlags{ .types = true } },
            .{ .name = "combined", .flags = ExtractionFlags{ .signatures = true, .types = true, .docs = true } },
        };
        
        while (@as(u64, @intCast(std.time.nanoTimestamp() - start)) < target_duration_ns) {
            for (extraction_modes) |mode| {
                var parser = ast.createExtractor(self.allocator, .zig);
                
                const extracted = try parser.extract(sample_code, mode.flags);
                defer self.allocator.free(extracted);
                
                total_extractions += 1;
            }
        }
        
        const elapsed = @as(u64, @intCast(std.time.nanoTimestamp() - start));
        
        if (verbose) {
            std.debug.print("  {} extractions in {}ms\n", .{ total_extractions, elapsed / 1_000_000 });
            std.debug.print("  Extraction modes tested: full, signatures, types, combined\n", .{});
        }
        
        var extra_info_buf: [256]u8 = undefined;
        const extra_info = try std.fmt.bufPrint(&extra_info_buf, "4 extraction modes", .{});
        
        try self.results.append(.{
            .name = "Code Extraction",
            .total_operations = total_extractions,
            .elapsed_ns = elapsed,
            .ns_per_op = elapsed / total_extractions,
            .extra_info = try self.allocator.dupe(u8, extra_info),
        });
    }
    
    /// Benchmark cache system performance
    pub fn benchmarkCacheSystem(self: *Self, target_duration_ns: u64, verbose: bool) !void {
        if (verbose) {
            std.debug.print("\n=== Cache System Benchmark ===\n", .{});
        }
        
        const CacheSystem = @import("cache.zig").CacheSystem;
        const AstCacheKey = @import("cache.zig").AstCacheKey;
        
        var cache_system = CacheSystem.init(self.allocator);
        defer cache_system.deinit();
        
        var timer = try std.time.Timer.start();
        var cache_operations: usize = 0;
        
        // Sample content for caching
        const sample_content = "pub fn test() void {}";
        
        // Run cache operations
        while (timer.read() < target_duration_ns) {
            // Create cache key
            const key = AstCacheKey.init(12345, 1, 67890);
            
            // Try cache lookup (miss)
            _ = cache_system.ast_cache.get(key);
            
            // Store in cache
            try cache_system.ast_cache.put(key, sample_content);
            
            // Lookup again (hit)
            _ = cache_system.ast_cache.get(key);
            
            cache_operations += 3; // lookup + put + lookup
        }
        
        const elapsed = timer.read();
        const cache_stats = cache_system.getAstStats();
        
        if (verbose) {
            std.debug.print("  {} cache operations in {}ms\n", .{ cache_operations, elapsed / 1_000_000 });
            std.debug.print("  Hit rate: {d:.1}% ({} hits, {} misses)\n", 
                .{ cache_stats.efficiency(), cache_stats.hits, cache_stats.misses });
        }
        
        var extra_info_buf: [256]u8 = undefined;
        const extra_info = try std.fmt.bufPrint(&extra_info_buf, "Hit rate: {d:.1}%", .{cache_stats.efficiency()});
        
        try self.results.append(.{
            .name = "Cache System",
            .total_operations = cache_operations,
            .elapsed_ns = elapsed,
            .ns_per_op = elapsed / cache_operations,
            .extra_info = try self.allocator.dupe(u8, extra_info),
        });
    }
    
    /// Benchmark incremental file tracking
    pub fn benchmarkIncremental(self: *Self, target_duration_ns: u64, verbose: bool) !void {
        if (verbose) {
            std.debug.print("\n=== Incremental File Tracking Benchmark ===\n", .{});
        }
        
        const FileTracker = @import("incremental.zig").FileTracker;
        
        var tracker = FileTracker.init(self.allocator);
        defer tracker.deinit();
        
        // Create temporary test files
        var tmp_dir = std.testing.tmpDir(.{});
        defer tmp_dir.cleanup();
        
        const test_files = [_][]const u8{ "file1.zig", "file2.zig", "file3.zig" };
        for (test_files) |filename| {
            try tmp_dir.dir.writeFile(.{ .sub_path = filename, .data = "test content" });
        }
        
        var timer = try std.time.Timer.start();
        var tracking_operations: usize = 0;
        
        // Get absolute paths
        var file_paths: [test_files.len][]u8 = undefined;
        for (test_files, 0..) |filename, i| {
            file_paths[i] = try tmp_dir.dir.realpathAlloc(self.allocator, filename);
        }
        defer {
            for (file_paths) |path| {
                self.allocator.free(path);
            }
        }
        
        // Run tracking operations
        while (timer.read() < target_duration_ns) {
            for (file_paths) |file_path| {
                try tracker.trackFile(file_path);
                _ = tracker.getFileState(file_path);
                tracking_operations += 2; // track + get
            }
        }
        
        const elapsed = timer.read();
        
        if (verbose) {
            std.debug.print("  {} tracking operations in {}ms\n", .{ tracking_operations, elapsed / 1_000_000 });
            std.debug.print("  Files tracked: {}\n", .{test_files.len});
        }
        
        var extra_info_buf: [256]u8 = undefined;
        const extra_info = try std.fmt.bufPrint(&extra_info_buf, "{} test files", .{test_files.len});
        
        try self.results.append(.{
            .name = "Incremental Tracking",
            .total_operations = tracking_operations,
            .elapsed_ns = elapsed,
            .ns_per_op = elapsed / tracking_operations,
            .extra_info = try self.allocator.dupe(u8, extra_info),
        });
    }
    
    /// Benchmark parallel processing performance
    pub fn benchmarkParallelProcessing(self: *Self, target_duration_ns: u64, verbose: bool) !void {
        if (verbose) {
            std.debug.print("\n=== Parallel Processing Benchmark ===\n", .{});
        }
        
        const WorkerPool = @import("parallel.zig").WorkerPool;
        const Task = @import("parallel.zig").Task;
        
        // Create worker pool with 4 workers
        var pool = try WorkerPool.init(self.allocator, 4);
        defer pool.deinit();
        
        try pool.start();
        defer pool.stop();
        
        var timer = try std.time.Timer.start();
        var parallel_tasks: usize = 0;
        
        // Simple task function
        const SimpleTaskFn = struct {
            fn execute(task: *Task, context: ?*anyopaque) !void {
                _ = task;
                _ = context;
                // Simulate some work
                var sum: u64 = 0;
                for (0..1000) |i| {
                    sum += i;
                }
                // Prevent optimization
                std.mem.doNotOptimizeAway(sum);
            }
        }.execute;
        
        // Submit tasks until duration reached
        while (timer.read() < target_duration_ns) {
            const task_id = try pool.submitTask(.normal, SimpleTaskFn, null, &.{});
            _ = task_id;
            parallel_tasks += 1;
            
            // Small delay to prevent overwhelming the queue
            if (parallel_tasks % 100 == 0) {
                std.time.sleep(1_000_000); // 1ms
            }
        }
        
        // Wait for completion
        pool.waitForCompletion();
        
        const elapsed = timer.read();
        const stats = pool.getWorkerStats();
        
        if (verbose) {
            std.debug.print("  {} tasks submitted in {}ms\n", .{ parallel_tasks, elapsed / 1_000_000 });
            std.debug.print("  Completed tasks: {}\n", .{stats.total_completed_tasks});
            std.debug.print("  Workers: {}\n", .{stats.worker_count});
        }
        
        var extra_info_buf: [256]u8 = undefined;
        const extra_info = try std.fmt.bufPrint(&extra_info_buf, "{} workers", .{stats.worker_count});
        
        try self.results.append(.{
            .name = "Parallel Processing",
            .total_operations = parallel_tasks,
            .elapsed_ns = elapsed,
            .ns_per_op = elapsed / parallel_tasks,
            .extra_info = try self.allocator.dupe(u8, extra_info),
        });
    }
    
    /// Benchmark AST node visitor performance
    pub fn benchmarkAstTraversal(self: *Self, target_duration_ns: u64, verbose: bool) !void {
        if (verbose) {
            std.debug.print("\n=== AST Traversal Benchmark ===\n", .{});
        }
        
        const AstNode = @import("ast.zig").AstNode;
        const NodeVisitor = @import("ast.zig").NodeVisitor;
        const VisitResult = @import("ast.zig").VisitResult;
        
        // Create a mock AST node for traversal
        const sample_source = "pub fn test() void { const x = 42; return; }";
        const mock_node = AstNode{
            .raw_node = null,
            .node_type = "function",
            .start_byte = 0,
            .end_byte = @intCast(sample_source.len),
            .start_point = AstNode.Point{ .row = 0, .column = 0 },
            .end_point = AstNode.Point{ .row = 0, .column = @intCast(sample_source.len) },
            .text = sample_source,
        };
        
        var timer = try std.time.Timer.start();
        var traversal_operations: usize = 0;
        
        // Visitor function that counts nodes
        const CounterVisitor = struct {
            fn visit(visitor: *NodeVisitor, node: *const AstNode, context: ?*anyopaque) !VisitResult {
                _ = visitor;
                _ = node;
                if (context) |ctx| {
                    const counter: *usize = @ptrCast(@alignCast(ctx));
                    counter.* += 1;
                }
                return VisitResult.continue_traversal;
            }
        }.visit;
        
        // Run traversals
        while (timer.read() < target_duration_ns) {
            var node_count: usize = 0;
            var visitor = NodeVisitor.init(self.allocator, CounterVisitor, &node_count);
            try visitor.traverse(&mock_node, sample_source);
            traversal_operations += 1;
        }
        
        const elapsed = timer.read();
        
        if (verbose) {
            std.debug.print("  {} AST traversals in {}ms\n", .{ traversal_operations, elapsed / 1_000_000 });
            std.debug.print("  Sample AST size: {} bytes\n", .{sample_source.len});
        }
        
        var extra_info_buf: [256]u8 = undefined;
        const extra_info = try std.fmt.bufPrint(&extra_info_buf, "{} bytes AST", .{sample_source.len});
        
        try self.results.append(.{
            .name = "AST Traversal",
            .total_operations = traversal_operations,
            .elapsed_ns = elapsed,
            .ns_per_op = elapsed / traversal_operations,
            .extra_info = try self.allocator.dupe(u8, extra_info),
        });
    }
    
    /// Run all benchmarks for target duration each
    pub fn runAll(self: *Self, target_duration_ns: u64, verbose: bool) !void {
        if (verbose) {
            var duration_buf: [64]u8 = undefined;
            const formatted_duration = try formatTime(target_duration_ns, &duration_buf);
            std.debug.print("Running performance benchmarks for {} each...\n", .{formatted_duration});
        }
        
        try self.benchmarkPathJoining(target_duration_ns, verbose);
        try self.benchmarkStringPool(target_duration_ns, verbose);
        try self.benchmarkMemoryPools(target_duration_ns, verbose);
        try self.benchmarkGlobPatterns(target_duration_ns, verbose);
        try self.benchmarkExtraction(target_duration_ns, verbose);
        try self.benchmarkCacheSystem(target_duration_ns, verbose);
        try self.benchmarkIncremental(target_duration_ns, verbose);
        try self.benchmarkParallelProcessing(target_duration_ns, verbose);
        try self.benchmarkAstTraversal(target_duration_ns, verbose);
        
        if (verbose) {
            std.debug.print("\n=== Benchmark Complete ===\n", .{});
        }
    }
    
    /// Get all benchmark results
    pub fn getResults(self: Self) []const BenchmarkResult {
        return self.results.items;
    }
    
    /// Print comparison summary to terminal
    pub fn printComparison(self: Self, baseline_results: ?[]const BenchmarkResult) void {
        if (baseline_results == null) return;
        
        std.debug.print("\n=== Performance Comparison ===\n", .{});
        for (self.results.items) |result| {
            // Find matching baseline
            const baseline_result = for (baseline_results.?) |b| {
                if (std.mem.eql(u8, b.name, result.name)) break b;
            } else null;
            
            if (baseline_result) |base| {
                const change = @as(f64, @floatFromInt(result.ns_per_op)) / 
                              @as(f64, @floatFromInt(base.ns_per_op)) - 1.0;
                const change_pct = change * 100.0;
                
                // Color coding would be nice but keeping it simple
                const symbol = if (change > 0.05) "⚠" else if (change < -0.05) "✓" else " ";
                
                std.debug.print("  {s} {s}: {s}{d:.1}% ({} ns/op → {} ns/op)\n", .{
                    symbol,
                    result.name,
                    if (change > 0) "+" else "",
                    change_pct,
                    base.ns_per_op,
                    result.ns_per_op,
                });
            } else {
                std.debug.print("  ? {s}: NEW (no baseline)\n", .{result.name});
            }
        }
    }
    
    /// Write results to markdown format
    pub fn writeMarkdown(
        self: Self,
        writer: anytype,
        baseline_results: ?[]const BenchmarkResult,
        build_mode: []const u8,
        duration_per_benchmark: []const u8,
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
        try writer.print("**Duration per benchmark:** {s}  \n\n", .{duration_per_benchmark});
        
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
    
    /// Write results in JSON format
    pub fn writeJSON(
        self: Self,
        writer: anytype,
        build_mode: []const u8,
        duration_per_benchmark: []const u8,
    ) !void {
        const timestamp = std.time.timestamp();
        
        try writer.print("{{\n", .{});
        try writer.print("  \"timestamp\": {},\n", .{timestamp});
        try writer.print("  \"build_mode\": \"{s}\",\n", .{build_mode});
        try writer.print("  \"duration_per_benchmark\": \"{s}\",\n", .{duration_per_benchmark});
        try writer.print("  \"results\": [\n", .{});
        
        for (self.results.items, 0..) |result, i| {
            try writer.print("    {{\n", .{});
            try writer.print("      \"name\": \"{s}\",\n", .{result.name});
            try writer.print("      \"operations\": {},\n", .{result.total_operations});
            try writer.print("      \"elapsed_ns\": {},\n", .{result.elapsed_ns});
            try writer.print("      \"ns_per_op\": {}", .{result.ns_per_op});
            if (result.extra_info) |info| {
                try writer.print(",\n      \"extra_info\": \"{s}\"", .{info});
            }
            try writer.print("\n    }}", .{});
            if (i < self.results.items.len - 1) {
                try writer.print(",", .{});
            }
            try writer.print("\n", .{});
        }
        
        try writer.print("  ]\n", .{});
        try writer.print("}}\n", .{});
    }
    
    /// Write results in CSV format
    pub fn writeCSV(self: Self, writer: anytype) !void {
        // Header
        try writer.print("Benchmark,Operations,Time (ms),ns/op\n", .{});
        
        // Data rows
        for (self.results.items) |result| {
            try writer.print("{s},{},{},{}\n", .{
                result.name,
                result.total_operations,
                result.elapsed_ns / 1_000_000,
                result.ns_per_op,
            });
        }
    }
    
    /// Write results in pretty terminal format
    pub fn writePretty(
        self: Self,
        writer: anytype,
        baseline_results: ?[]const BenchmarkResult,
    ) !void {
        // Header with blue color
        try writer.print("\n{s}{s}╔══════════════════════════════════════════════════════════════╗{s}\n", .{ Color.blue, Color.bold, Color.reset });
        try writer.print("{s}{s}║                  zz Performance Benchmarks                   ║{s}\n", .{ Color.blue, Color.bold, Color.reset });
        try writer.print("{s}{s}╚══════════════════════════════════════════════════════════════╝{s}\n\n", .{ Color.blue, Color.bold, Color.reset });
        
        // Calculate totals for summary
        var total_time: u64 = 0;
        var improved_count: usize = 0;
        var regressed_count: usize = 0;
        var new_count: usize = 0;
        
        // Calculate total runtime
        for (self.results.items) |result| {
            total_time += result.elapsed_ns;
        }
        
        // Results with color coding
        for (self.results.items) |result| {
            var time_buf: [64]u8 = undefined;
            var baseline_buf: [64]u8 = undefined;
            
            const formatted_time = try formatTime(result.ns_per_op, &time_buf);
            
            if (baseline_results) |baseline| {
                const baseline_result = for (baseline) |b| {
                    if (std.mem.eql(u8, b.name, result.name)) break b;
                } else null;
                
                if (baseline_result) |base| {
                    const change = @as(f64, @floatFromInt(result.ns_per_op)) / 
                                  @as(f64, @floatFromInt(base.ns_per_op)) - 1.0;
                    const change_pct = change * 100.0;
                    
                    const formatted_baseline = try formatTime(base.ns_per_op, &baseline_buf);
                    
                    var total_runtime_buf: [64]u8 = undefined;
                    const formatted_total_runtime = try formatTime(result.elapsed_ns, &total_runtime_buf);
                    
                    if (change > 0.05) {
                        regressed_count += 1;
                        try writer.print("{s}⚠ {s: <20} {s: >8} → {s}{s: >8}{s} {s}{s}{d:.1}% in {s}{s}\n", .{
                            Color.bright_yellow,
                            result.name,
                            formatted_baseline,
                            Color.bright_yellow,
                            formatted_time,
                            Color.reset,
                            Color.dim,
                            if (change > 0) "+" else "",
                            change_pct,
                            formatted_total_runtime,
                            Color.reset,
                        });
                    } else if (change < -0.01) {
                        improved_count += 1;
                        try writer.print("{s}✓ {s: <20} {s: >8} → {s}{s: >8}{s} {s}{s}{d:.1}% in {s}{s}\n", .{
                            Color.bright_green,
                            result.name,
                            formatted_baseline,
                            Color.bright_green,
                            formatted_time,
                            Color.reset,
                            Color.dim,
                            if (change > 0) "+" else "",
                            change_pct,
                            formatted_total_runtime,
                            Color.reset,
                        });
                    } else {
                        try writer.print("  {s: <20} {s: >8} → {s: >8} {s}{s}{d:.1}% in {s}{s}\n", .{
                            result.name,
                            formatted_baseline,
                            formatted_time,
                            Color.dim,
                            if (change > 0) "+" else "",
                            change_pct,
                            formatted_total_runtime,
                            Color.reset,
                        });
                    }
                } else {
                    new_count += 1;
                    try writer.print("{s}? {s: <20}{s} {s: >12} {s}(new benchmark){s}\n", .{
                        Color.cyan,
                        result.name,
                        Color.reset,
                        formatted_time,
                        Color.dim,
                        Color.reset,
                    });
                }
            } else {
                try writer.print("  {s: <20} {s: >12}\n", .{
                    result.name,
                    formatted_time,
                });
            }
        }
        
        // Separator
        try writer.print("\n{s}──────────────────────────────────────────────────────────────{s}\n", .{ Color.gray, Color.reset });
        
        // Summary section
        var total_time_buf: [64]u8 = undefined;
        const formatted_total = try formatTime(total_time, &total_time_buf);
        
        if (baseline_results != null) {
            try writer.print("{s}Summary:{s} {} benchmarks, {s} total\n", .{
                Color.bold,
                Color.reset,
                self.results.items.len,
                formatted_total,
            });
            
            if (improved_count > 0 or regressed_count > 0 or new_count > 0) {
                try writer.print("         ", .{});
                if (improved_count > 0) {
                    try writer.print("{s}✓ {} improved{s}  ", .{ Color.green, improved_count, Color.reset });
                }
                if (regressed_count > 0) {
                    try writer.print("{s}⚠ {} regressed{s}  ", .{ Color.yellow, regressed_count, Color.reset });
                }
                if (new_count > 0) {
                    try writer.print("{s}? {} new{s}", .{ Color.cyan, new_count, Color.reset });
                }
                try writer.print("\n", .{});
            }
        } else {
            try writer.print("{s}Summary:{s} {} benchmarks, {s} total\n", .{
                Color.bold,
                Color.reset,
                self.results.items.len,
                formatted_total,
            });
            try writer.print("{s}No baseline found. Run: {s}zig build benchmark-baseline{s}\n", .{
                Color.gray,
                Color.cyan,
                Color.reset,
            });
        }
        
        try writer.print("\n", .{});
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