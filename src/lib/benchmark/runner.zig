const std = @import("std");
const types = @import("types.zig");
const baseline = @import("baseline.zig");
const output = @import("output.zig");
const utils = @import("utils.zig");

const BenchmarkResult = types.BenchmarkResult;
const BenchmarkOptions = types.BenchmarkOptions;
const BenchmarkSuite = types.BenchmarkSuite;
const BenchmarkError = types.BenchmarkError;
const BaselineManager = baseline.BaselineManager;

/// Central benchmark runner
pub const BenchmarkRunner = struct {
    allocator: std.mem.Allocator,
    options: BenchmarkOptions,
    suites: std.ArrayList(BenchmarkSuite),
    results: std.ArrayList(BenchmarkResult),
    baseline_manager: BaselineManager,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator, options: BenchmarkOptions) BenchmarkRunner {
        return BenchmarkRunner{
            .allocator = allocator,
            .options = options,
            .suites = std.ArrayList(BenchmarkSuite).init(allocator),
            .results = std.ArrayList(BenchmarkResult).init(allocator),
            .baseline_manager = BaselineManager.init(allocator),
        };
    }
    
    pub fn deinit(self: *Self) void {
        for (self.results.items) |result| {
            result.deinit(self.allocator);
        }
        self.results.deinit();
        self.suites.deinit();
        self.baseline_manager.deinit();
    }
    
    pub fn registerSuite(self: *Self, suite: BenchmarkSuite) !void {
        try self.suites.append(suite);
    }
    
    /// Load baseline results from file for comparison
    pub fn loadBaseline(self: *Self, baseline_path: []const u8) !void {
        try self.baseline_manager.loadBaseline(baseline_path);
    }
    
    /// Run all registered benchmark suites
    pub fn runAll(self: *Self) !void {
        for (self.suites.items) |suite| {
            // Check if this suite should be run based on filters
            if (!self.shouldRunSuite(suite.name)) continue;
            
            std.debug.print("\n═══ Running suite: {s} ═══\n", .{suite.name});
            const suite_start_time = std.time.nanoTimestamp();
            
            const suite_results = try suite.run(self.allocator, self.options);
            
            const suite_end_time = std.time.nanoTimestamp();
            const suite_elapsed_ms = @divTrunc(suite_end_time - suite_start_time, 1_000_000);
            
            // Check confidence requirements
            for (suite_results) |result| {
                if (!result.meetsConfidenceRequirement(self.options.min_confidence)) {
                    std.debug.print("Error: Benchmark '{s}' failed minimum confidence requirement\n", .{result.name});
                    return BenchmarkError.BenchmarkFailed;
                }
                try self.results.append(result);
            }
            self.allocator.free(suite_results);
            
            std.debug.print("═══ Suite complete: {s} ({} benchmarks, {}ms total) ═══\n", .{ suite.name, suite_results.len, @as(u32, @intCast(suite_elapsed_ms)) });
        }
    }
    
    fn shouldRunSuite(self: *Self, suite_name: []const u8) bool {
        // Check skip filter - if there's a skip filter and this suite matches it, skip it
        if (self.options.skip) |skip_filter| {
            if (utils.matchesFilter(suite_name, skip_filter, true)) {
                return false; // Suite is in skip list
            }
        }
        
        // Check only filter - if there's an only filter, suite must match it
        if (self.options.only) |only_filter| {
            return utils.matchesFilter(suite_name, only_filter, false);
        }
        
        // No filters mean run all suites
        return true;
    }
    
    /// Output results in specified format
    pub fn outputResults(self: *Self, writer: anytype) !void {
        try output.outputResults(writer, self.results.items, self.options, &self.baseline_manager);
    }
    
    /// Check for performance regressions and return appropriate exit code
    pub fn checkRegressions(self: *Self) bool {
        return self.baseline_manager.hasRegressions(self.results.items);
    }
};