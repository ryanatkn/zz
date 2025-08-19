const std = @import("std");
const types = @import("types.zig");
const BenchmarkError = types.BenchmarkError;
const ComparisonResult = types.ComparisonResult;

/// Baseline management for benchmark comparisons
pub const BaselineManager = struct {
    allocator: std.mem.Allocator,
    baseline_results: ?std.HashMap([]const u8, u64, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) BaselineManager {
        return BaselineManager{
            .allocator = allocator,
            .baseline_results = null,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.baseline_results) |*baseline| {
            var iterator = baseline.iterator();
            while (iterator.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
            }
            baseline.deinit();
        }
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

        try self.parseMarkdownBaseline(content);
    }

    fn parseMarkdownBaseline(self: *Self, content: []const u8) !void {
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

    /// Get baseline value for a benchmark name
    pub fn getBaseline(self: *Self, name: []const u8) ?u64 {
        if (self.baseline_results) |*baseline| {
            return baseline.get(name);
        }
        return null;
    }

    /// Compare current result with baseline
    pub fn compare(self: *Self, name: []const u8, current_ns: u64) ?ComparisonResult {
        if (self.getBaseline(name)) |baseline_ns| {
            return ComparisonResult.init(baseline_ns, current_ns);
        }
        return null;
    }

    /// Check if any results have regressions
    pub fn hasRegressions(self: *Self, results: []const types.BenchmarkResult) bool {
        if (self.baseline_results == null) return false;

        for (results) |result| {
            if (self.compare(result.name, result.ns_per_op)) |comparison| {
                if (comparison.is_regression) {
                    return true;
                }
            }
        }

        return false;
    }

    pub const ConfidenceStats = struct {
        high: u32,
        medium: u32,
        low: u32,
        insufficient: u32,
    };

    /// Count confidence issues in results
    pub fn getConfidenceStats(self: *Self, results: []const types.BenchmarkResult) ConfidenceStats {
        _ = self;
        var stats = ConfidenceStats{ .high = 0, .medium = 0, .low = 0, .insufficient = 0 };

        for (results) |result| {
            switch (result.confidence) {
                .high => stats.high += 1,
                .medium => stats.medium += 1,
                .low => stats.low += 1,
                .insufficient => stats.insufficient += 1,
            }
        }

        return stats;
    }
};