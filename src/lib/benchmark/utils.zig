const std = @import("std");
const types = @import("types.zig");
const BenchmarkError = types.BenchmarkError;

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
        value_part = duration_str[0 .. duration_str.len - 2];
        unit_part = "ns";
    } else if (std.mem.endsWith(u8, duration_str, "us") or std.mem.endsWith(u8, duration_str, "μs")) {
        value_part = duration_str[0 .. duration_str.len - 2];
        unit_part = "us";
    } else if (std.mem.endsWith(u8, duration_str, "ms")) {
        value_part = duration_str[0 .. duration_str.len - 2];
        unit_part = "ms";
    } else if (std.mem.endsWith(u8, duration_str, "s")) {
        value_part = duration_str[0 .. duration_str.len - 1];
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

/// Create a progress bar for pretty output
pub fn createProgressBar(ns_per_op: u64) []const u8 {
    // Simple progress bar based on logarithmic scale
    const log_ns = std.math.log10(@as(f64, @floatFromInt(ns_per_op)));
    const normalized = std.math.clamp((log_ns - 1.0) / 6.0, 0.0, 1.0); // 10ns to 1s scale
    const bar_length = @as(usize, @intFromFloat(normalized * 10));

    const bars = [_][]const u8{ "          ", "=         ", "==        ", "===       ", "====      ", "=====     ", "======    ", "=======   ", "========  ", "========= ", "==========" };

    return bars[bar_length];
}

/// Format large numbers with appropriate units
pub fn formatOperationCount(operations: usize, allocator: std.mem.Allocator) ![]u8 {
    if (operations >= 1_000_000) {
        const ops_f = @as(f64, @floatFromInt(operations)) / 1_000_000.0;
        return std.fmt.allocPrint(allocator, "{d:.1}M", .{ops_f});
    } else if (operations >= 1_000) {
        return std.fmt.allocPrint(allocator, "{}k", .{operations / 1000});
    } else {
        return std.fmt.allocPrint(allocator, "{}", .{operations});
    }
}

/// Calculate percentage change with proper formatting
pub fn formatPercentageChange(percent_change: f64) struct { sign: []const u8, value: f64 } {
    const sign = if (percent_change >= 0) "+" else "";
    return .{ .sign = sign, .value = percent_change };
}

/// Check if a suite name matches filter criteria
pub fn matchesFilter(suite_name: []const u8, filter: ?[]const u8, is_skip_filter: bool) bool {
    const filter_list = filter orelse return !is_skip_filter; // If no filter, include for "only", exclude for "skip"

    var items = std.mem.splitScalar(u8, filter_list, ',');
    while (items.next()) |item| {
        const trimmed = std.mem.trim(u8, item, " ");
        if (std.mem.indexOf(u8, suite_name, trimmed) != null) {
            return !is_skip_filter; // Found match: include for "only", exclude for "skip"
        }
    }

    return is_skip_filter; // No match: exclude for "only", include for "skip"
}
