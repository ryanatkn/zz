const std = @import("std");
const builtin = @import("builtin");

// Core benchmark types and utilities
pub const BenchmarkError = error{
    InvalidDuration,
    InvalidFormat,
    InvalidFilter,
    BaselineNotFound,
    BenchmarkFailed,
    OutOfMemory,
};

pub const OutputFormat = enum {
    markdown,
    json,
    csv,
    pretty,

    pub fn fromString(s: []const u8) ?OutputFormat {
        if (std.mem.eql(u8, s, "markdown")) return .markdown;
        if (std.mem.eql(u8, s, "json")) return .json;
        if (std.mem.eql(u8, s, "csv")) return .csv;
        if (std.mem.eql(u8, s, "pretty")) return .pretty;
        return null;
    }
};

pub const BenchmarkOptions = struct {
    /// Duration to run each benchmark in nanoseconds (default: 2s)
    duration_ns: u64 = 2_000_000_000,
    /// Output format for results
    format: OutputFormat = .markdown,
    /// Path to baseline file for comparison
    baseline: ?[]const u8 = null,
    /// Disable baseline comparison even if baseline exists
    no_compare: bool = false,
    /// Only run benchmarks matching these names (comma-separated)
    only: ?[]const u8 = null,
    /// Skip benchmarks matching these names (comma-separated)
    skip: ?[]const u8 = null,
    /// Include warmup phase before timing
    warmup: bool = true,
    /// Duration multiplier (applied after built-in variance multipliers)
    duration_multiplier: f64 = 1.0,
};

pub const BenchmarkResult = struct {
    name: []const u8,
    total_operations: usize,
    elapsed_ns: u64,
    ns_per_op: u64,
    extra_info: ?[]const u8 = null,
    
    /// Free memory owned by this result
    pub fn deinit(self: BenchmarkResult, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        if (self.extra_info) |info| {
            allocator.free(info);
        }
    }
    
    /// Get human-readable time units
    pub fn getTimeUnit(self: BenchmarkResult) struct { value: f64, unit: []const u8 } {
        const ns = @as(f64, @floatFromInt(self.ns_per_op));
        if (ns < 1_000) return .{ .value = ns, .unit = "ns" };
        if (ns < 1_000_000) return .{ .value = ns / 1_000.0, .unit = "μs" };
        if (ns < 1_000_000_000) return .{ .value = ns / 1_000_000.0, .unit = "ms" };
        return .{ .value = ns / 1_000_000_000.0, .unit = "s" };
    }
};

/// Comparison result between current and baseline
pub const ComparisonResult = struct {
    baseline_ns_per_op: u64,
    current_ns_per_op: u64,
    percent_change: f64,
    is_improvement: bool,
    is_regression: bool,
    
    const REGRESSION_THRESHOLD = 20.0; // 20% regression threshold
    const IMPROVEMENT_THRESHOLD = -1.0; // 1% improvement threshold
    
    pub fn init(baseline_ns: u64, current_ns: u64) ComparisonResult {
        const baseline_f = @as(f64, @floatFromInt(baseline_ns));
        const current_f = @as(f64, @floatFromInt(current_ns));
        const percent_change = ((current_f - baseline_f) / baseline_f) * 100.0;
        
        return ComparisonResult{
            .baseline_ns_per_op = baseline_ns,
            .current_ns_per_op = current_ns,
            .percent_change = percent_change,
            .is_improvement = percent_change < IMPROVEMENT_THRESHOLD,
            .is_regression = percent_change > REGRESSION_THRESHOLD,
        };
    }
};

/// Interface for benchmark implementations
pub const BenchmarkSuite = struct {
    name: []const u8,
    /// Built-in variance multiplier for this suite
    variance_multiplier: f64 = 1.0,
    /// Function to run the benchmark suite
    runFn: *const fn (allocator: std.mem.Allocator, options: BenchmarkOptions) BenchmarkError![]BenchmarkResult,
    
    pub fn run(self: BenchmarkSuite, allocator: std.mem.Allocator, options: BenchmarkOptions) BenchmarkError![]BenchmarkResult {
        return self.runFn(allocator, options);
    }
    
    /// Get effective duration with variance multiplier applied
    pub fn getEffectiveDuration(self: BenchmarkSuite, base_duration_ns: u64, user_multiplier: f64) u64 {
        const effective_ns = @as(f64, @floatFromInt(base_duration_ns)) * self.variance_multiplier * user_multiplier;
        return @intFromFloat(effective_ns);
    }
};

/// Central benchmark runner
pub const BenchmarkRunner = struct {
    allocator: std.mem.Allocator,
    options: BenchmarkOptions,
    suites: std.ArrayList(BenchmarkSuite),
    results: std.ArrayList(BenchmarkResult),
    baseline_results: ?std.HashMap([]const u8, u64, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator, options: BenchmarkOptions) BenchmarkRunner {
        return BenchmarkRunner{
            .allocator = allocator,
            .options = options,
            .suites = std.ArrayList(BenchmarkSuite).init(allocator),
            .results = std.ArrayList(BenchmarkResult).init(allocator),
            .baseline_results = null,
        };
    }
    
    pub fn deinit(self: *Self) void {
        for (self.results.items) |result| {
            result.deinit(self.allocator);
        }
        self.results.deinit();
        self.suites.deinit();
        
        if (self.baseline_results) |*baseline| {
            var iterator = baseline.iterator();
            while (iterator.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
            }
            baseline.deinit();
        }
    }
    
    pub fn registerSuite(self: *Self, suite: BenchmarkSuite) !void {
        try self.suites.append(suite);
    }
    
    /// Load baseline results from file for comparison
    pub fn loadBaseline(self: *Self, baseline_path: []const u8) !void {
        const file = std.fs.cwd().openFile(baseline_path, .{}) catch |err| switch (err) {
            error.FileNotFound => return BenchmarkError.BaselineNotFound,
            else => return err,
        };
        defer file.close();
        
        const content = try file.readToEndAlloc(self.allocator, 1024 * 1024); // 1MB limit
        defer self.allocator.free(content);
        
        self.baseline_results = std.HashMap([]const u8, u64, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(self.allocator);
        
        // Parse markdown table format
        var lines = std.mem.splitScalar(u8, content, '\n');
        var in_table = false;
        
        while (lines.next()) |line| {
            if (std.mem.indexOf(u8, line, "| Benchmark |") != null) {
                in_table = true;
                _ = lines.next(); // Skip separator line
                continue;
            }
            
            if (!in_table) continue;
            if (line.len == 0) break;
            
            // Parse table row: | Name | Operations | Time (ms) | ns/op | vs Baseline |
            var parts = std.mem.splitScalar(u8, line, '|');
            _ = parts.next(); // Skip empty first part
            
            const name_part = parts.next() orelse continue;
            _ = parts.next(); // Skip operations
            _ = parts.next(); // Skip time
            const ns_part = parts.next() orelse continue;
            
            const name = std.mem.trim(u8, name_part, " ");
            const ns_str = std.mem.trim(u8, ns_part, " ");
            
            const ns_per_op = std.fmt.parseInt(u64, ns_str, 10) catch continue;
            const owned_name = try self.allocator.dupe(u8, name);
            try self.baseline_results.?.put(owned_name, ns_per_op);
        }
    }
    
    /// Run all registered benchmark suites
    pub fn runAll(self: *Self) !void {
        for (self.suites.items) |suite| {
            // Check if this suite should be run based on filters
            if (!self.shouldRunSuite(suite.name)) continue;
            
            const suite_results = try suite.run(self.allocator, self.options);
            for (suite_results) |result| {
                try self.results.append(result);
            }
            self.allocator.free(suite_results);
        }
    }
    
    fn shouldRunSuite(self: *Self, suite_name: []const u8) bool {
        // Check skip filter
        if (self.options.skip) |skip_list| {
            var skip_items = std.mem.splitScalar(u8, skip_list, ',');
            while (skip_items.next()) |skip_item| {
                const trimmed = std.mem.trim(u8, skip_item, " ");
                if (std.mem.indexOf(u8, suite_name, trimmed) != null) {
                    return false;
                }
            }
        }
        
        // Check only filter
        if (self.options.only) |only_list| {
            var only_items = std.mem.splitScalar(u8, only_list, ',');
            while (only_items.next()) |only_item| {
                const trimmed = std.mem.trim(u8, only_item, " ");
                if (std.mem.indexOf(u8, suite_name, trimmed) != null) {
                    return true;
                }
            }
            return false;
        }
        
        return true;
    }
    
    /// Output results in specified format
    pub fn outputResults(self: *Self, writer: anytype) !void {
        switch (self.options.format) {
            .markdown => try self.outputMarkdown(writer),
            .json => try self.outputJson(writer),
            .csv => try self.outputCsv(writer),
            .pretty => try self.outputPretty(writer),
        }
    }
    
    fn outputMarkdown(self: *Self, writer: anytype) !void {
        const now = std.time.timestamp();
        const date_time = std.time.epoch.EpochSeconds{ .secs = @intCast(now) };
        const year_day = date_time.getEpochDay().calculateYearDay();
        
        try writer.print("# Benchmark Results\n\n", .{});
        try writer.print("Date: {d}-01-01 00:00:00\n", .{year_day.year});
        try writer.print("Build: {s}\n", .{@tagName(builtin.mode)});
        try writer.print("Iterations: Time-based ({d}s duration)\n\n", .{self.options.duration_ns / 1_000_000_000});
        
        try writer.print("| Benchmark | Operations | Time (ms) | ns/op |", .{});
        if (self.baseline_results != null) {
            try writer.print(" vs Baseline |", .{});
        }
        try writer.print("\n", .{});
        
        try writer.print("|-----------|------------|-----------|-------|", .{});
        if (self.baseline_results != null) {
            try writer.print("-------------|", .{});
        }
        try writer.print("\n", .{});
        
        for (self.results.items) |result| {
            const time_ms = @as(f64, @floatFromInt(result.elapsed_ns)) / 1_000_000.0;
            
            try writer.print("| {s} | {d} | {d:.1} | {d} |", .{
                result.name, result.total_operations, time_ms, result.ns_per_op
            });
            
            if (self.baseline_results) |baseline| {
                if (baseline.get(result.name)) |baseline_ns| {
                    const comparison = ComparisonResult.init(baseline_ns, result.ns_per_op);
                    const sign = if (comparison.percent_change >= 0) "+" else "";
                    try writer.print(" {s}{d:.1}% |", .{ sign, comparison.percent_change });
                } else {
                    try writer.print(" NEW |", .{});
                }
            }
            
            try writer.print("\n", .{});
        }
        
        if (self.baseline_results != null) {
            try writer.print("\n**Legend:** Positive percentages indicate slower performance (regression), negative percentages indicate faster performance (improvement).\n", .{});
        }
    }
    
    fn outputJson(self: *Self, writer: anytype) !void {
        try writer.writeAll("{\n");
        try writer.print("  \"timestamp\": {d},\n", .{std.time.timestamp()});
        try writer.print("  \"build_mode\": \"{s}\",\n", .{@tagName(builtin.mode)});
        try writer.print("  \"duration_seconds\": {d},\n", .{self.options.duration_ns / 1_000_000_000});
        try writer.writeAll("  \"results\": [\n");
        
        for (self.results.items, 0..) |result, i| {
            if (i > 0) try writer.writeAll(",\n");
            
            try writer.print("    {{\n", .{});
            try writer.print("      \"name\": \"{s}\",\n", .{result.name});
            try writer.print("      \"operations\": {d},\n", .{result.total_operations});
            try writer.print("      \"elapsed_ns\": {d},\n", .{result.elapsed_ns});
            try writer.print("      \"ns_per_op\": {d}", .{result.ns_per_op});
            
            if (result.extra_info) |info| {
                try writer.print(",\n      \"extra_info\": \"{s}\"", .{info});
            }
            
            if (self.baseline_results) |baseline| {
                if (baseline.get(result.name)) |baseline_ns| {
                    const comparison = ComparisonResult.init(baseline_ns, result.ns_per_op);
                    try writer.print(",\n      \"baseline_comparison\": {{\n", .{});
                    try writer.print("        \"baseline_ns_per_op\": {d},\n", .{baseline_ns});
                    try writer.print("        \"percent_change\": {d:.2},\n", .{comparison.percent_change});
                    try writer.print("        \"is_improvement\": {}\n", .{comparison.is_improvement});
                    try writer.print("      }}", .{});
                }
            }
            
            try writer.print("\n    }}", .{});
        }
        
        try writer.writeAll("\n  ]\n}");
    }
    
    fn outputCsv(self: *Self, writer: anytype) !void {
        try writer.writeAll("benchmark,operations,elapsed_ns,ns_per_op");
        if (self.baseline_results != null) {
            try writer.writeAll(",baseline_ns_per_op,percent_change");
        }
        try writer.writeAll("\n");
        
        for (self.results.items) |result| {
            try writer.print("{s},{d},{d},{d}", .{
                result.name, result.total_operations, result.elapsed_ns, result.ns_per_op
            });
            
            if (self.baseline_results) |baseline| {
                if (baseline.get(result.name)) |baseline_ns| {
                    const comparison = ComparisonResult.init(baseline_ns, result.ns_per_op);
                    try writer.print(",{d},{d:.2}", .{ baseline_ns, comparison.percent_change });
                } else {
                    try writer.writeAll(",,");
                }
            }
            
            try writer.writeAll("\n");
        }
    }
    
    fn outputPretty(self: *Self, writer: anytype) !void {
        const Color = struct {
            const reset = "\x1b[0m";
            const green = "\x1b[32m";
            const yellow = "\x1b[33m";
            const cyan = "\x1b[36m";
            const bold = "\x1b[1m";
        };
        
        try writer.print("{s}╔══════════════════════════════════════════════════════════════╗{s}\n", .{ Color.bold, Color.reset });
        try writer.print("{s}║                    zz Performance Benchmarks                 ║{s}\n", .{ Color.bold, Color.reset });
        try writer.print("{s}╚══════════════════════════════════════════════════════════════╝{s}\n\n", .{ Color.bold, Color.reset });
        
        var total_time_ns: u64 = 0;
        var improvements: u32 = 0;
        var regressions: u32 = 0;
        var new_benchmarks: u32 = 0;
        
        for (self.results.items) |result| {
            total_time_ns += result.elapsed_ns;
            
            const time_unit = result.getTimeUnit();
            const progress_bar = self.createProgressBar(result.ns_per_op);
            
            var status_color: []const u8 = Color.reset;
            var status_symbol: []const u8 = " ";
            
            if (self.baseline_results) |baseline| {
                if (baseline.get(result.name)) |baseline_ns| {
                    const comparison = ComparisonResult.init(baseline_ns, result.ns_per_op);
                    if (comparison.is_improvement) {
                        status_color = Color.green;
                        status_symbol = "✓";
                        improvements += 1;
                    } else if (comparison.is_regression) {
                        status_color = Color.yellow;
                        status_symbol = "⚠";
                        regressions += 1;
                    }
                    
                    try writer.print("{s}{s} {s:<20} {d:.2} {s} [{s}] ({s}{d:.1}%{s} vs {d:.2} {s}){s}\n", .{
                        status_color, status_symbol, result.name, time_unit.value, time_unit.unit,
                        progress_bar, if (comparison.percent_change >= 0) "+" else "", comparison.percent_change, Color.reset,
                        @as(f64, @floatFromInt(baseline_ns)) / 1000.0, "μs", Color.reset
                    });
                } else {
                    status_color = Color.cyan;
                    status_symbol = "?";
                    new_benchmarks += 1;
                    
                    try writer.print("{s}{s} {s:<20} {d:.2} {s} [{s}] (NEW){s}\n", .{
                        status_color, status_symbol, result.name, time_unit.value, time_unit.unit,
                        progress_bar, Color.reset
                    });
                }
            } else {
                try writer.print("  {s:<20} {d:.2} {s} [{s}]\n", .{
                    result.name, time_unit.value, time_unit.unit, progress_bar
                });
            }
        }
        
        try writer.writeAll("\n──────────────────────────────────────────────────────────────\n");
        const total_time_ms = @as(f64, @floatFromInt(total_time_ns)) / 1_000_000.0;
        try writer.print("Summary: {d} benchmarks, {d:.2} ms total\n", .{ self.results.items.len, total_time_ms });
        
        if (self.baseline_results != null) {
            try writer.print("         {s}✓ {d} improved{s}  {s}⚠ {d} regressed{s}", .{
                Color.green, improvements, Color.reset,
                Color.yellow, regressions, Color.reset
            });
            if (new_benchmarks > 0) {
                try writer.print("  {s}? {d} new{s}", .{ Color.cyan, new_benchmarks, Color.reset });
            }
            try writer.writeAll("\n");
        }
    }
    
    fn createProgressBar(self: *Self, ns_per_op: u64) []const u8 {
        _ = self;
        // Simple progress bar based on logarithmic scale
        const log_ns = std.math.log10(@as(f64, @floatFromInt(ns_per_op)));
        const normalized = std.math.clamp((log_ns - 1.0) / 6.0, 0.0, 1.0); // 10ns to 1s scale
        const bar_length = @as(usize, @intFromFloat(normalized * 10));
        
        const bars = [_][]const u8{
            "          ", "=         ", "==        ", "===       ", "====      ",
            "=====     ", "======    ", "=======   ", "========  ", "========= ",
            "=========="
        };
        
        return bars[bar_length];
    }
    
    /// Check for performance regressions and return appropriate exit code
    pub fn checkRegressions(self: *Self) bool {
        if (self.baseline_results == null) return false;
        
        for (self.results.items) |result| {
            if (self.baseline_results.?.get(result.name)) |baseline_ns| {
                const comparison = ComparisonResult.init(baseline_ns, result.ns_per_op);
                if (comparison.is_regression) {
                    return true;
                }
            }
        }
        
        return false;
    }
};

/// Utility function for timing operations
pub fn measureOperation(
    allocator: std.mem.Allocator,
    duration_ns: u64,
    warmup: bool,
    context: anytype,
    comptime operation: fn (@TypeOf(context)) anyerror!void,
) BenchmarkError!BenchmarkResult {
    // Warmup phase
    if (warmup) {
        const warmup_iterations = 100;
        for (0..warmup_iterations) |_| {
            operation(context) catch |err| {
                return switch (err) {
                    error.OutOfMemory => BenchmarkError.OutOfMemory,
                    else => BenchmarkError.BenchmarkFailed,
                };
            };
        }
    }
    
    var operations: usize = 0;
    const start_time = std.time.nanoTimestamp();
    var current_time = start_time;
    
    // Run operations until duration is reached
    while ((current_time - start_time) < duration_ns) {
        operation(context) catch |err| {
            return switch (err) {
                error.OutOfMemory => BenchmarkError.OutOfMemory,
                else => BenchmarkError.BenchmarkFailed,
            };
        };
        operations += 1;
        current_time = std.time.nanoTimestamp();
    }
    
    const elapsed_ns: u64 = @intCast(current_time - start_time);
    const ns_per_op = elapsed_ns / operations;
    
    return BenchmarkResult{
        .name = try allocator.dupe(u8, "operation"),
        .total_operations = operations,
        .elapsed_ns = elapsed_ns,
        .ns_per_op = ns_per_op,
    };
}

/// Parse duration string to nanoseconds
pub fn parseDuration(duration_str: []const u8) !u64 {
    if (duration_str.len == 0) return BenchmarkError.InvalidDuration;
    
    // Try parsing as pure number (nanoseconds)
    if (std.fmt.parseInt(u64, duration_str, 10)) |ns| {
        return ns;
    } else |_| {}
    
    // Parse with unit suffix
    var value_part: []const u8 = undefined;
    var unit_part: []const u8 = undefined;
    
    if (std.mem.endsWith(u8, duration_str, "ns")) {
        value_part = duration_str[0..duration_str.len - 2];
        unit_part = "ns";
    } else if (std.mem.endsWith(u8, duration_str, "us") or std.mem.endsWith(u8, duration_str, "μs")) {
        value_part = duration_str[0..duration_str.len - 2];
        unit_part = "us";
    } else if (std.mem.endsWith(u8, duration_str, "ms")) {
        value_part = duration_str[0..duration_str.len - 2];
        unit_part = "ms";
    } else if (std.mem.endsWith(u8, duration_str, "s")) {
        value_part = duration_str[0..duration_str.len - 1];
        unit_part = "s";
    } else {
        return BenchmarkError.InvalidDuration;
    }
    
    const value = std.fmt.parseFloat(f64, value_part) catch return BenchmarkError.InvalidDuration;
    
    const multiplier: f64 = if (std.mem.eql(u8, unit_part, "ns"))
        1.0
    else if (std.mem.eql(u8, unit_part, "us"))
        1_000.0
    else if (std.mem.eql(u8, unit_part, "ms"))
        1_000_000.0
    else if (std.mem.eql(u8, unit_part, "s"))
        1_000_000_000.0
    else
        return BenchmarkError.InvalidDuration;
    
    return @intFromFloat(value * multiplier);
}