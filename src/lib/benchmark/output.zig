const std = @import("std");
const builtin = @import("builtin");
const types = @import("types.zig");
const baseline = @import("baseline.zig");
const utils = @import("utils.zig");
const text_builders = @import("../text/builders.zig");

const BenchmarkResult = types.BenchmarkResult;
const BenchmarkOptions = types.BenchmarkOptions;
const ComparisonResult = types.ComparisonResult;
const StatisticalConfidence = types.StatisticalConfidence;
const BaselineManager = baseline.BaselineManager;

pub fn outputResults(
    writer: anytype,
    results: []const BenchmarkResult,
    options: BenchmarkOptions,
    baseline_manager: *BaselineManager,
) !void {
    switch (options.format) {
        .markdown => try outputMarkdown(writer, results, options, baseline_manager),
        .json => try outputJson(writer, results, options, baseline_manager),
        .csv => try outputCsv(writer, results, options, baseline_manager),
        .pretty => try outputPretty(writer, results, options, baseline_manager),
    }
}

fn outputMarkdown(
    writer: anytype,
    results: []const BenchmarkResult,
    options: BenchmarkOptions,
    baseline_manager: *BaselineManager,
) !void {
    const now = std.time.timestamp();
    const date_time = std.time.epoch.EpochSeconds{ .secs = @intCast(now) };
    const year_day = date_time.getEpochDay().calculateYearDay();

    try writer.print("# Benchmark Results\n\n", .{});
    try writer.print("Date: {d}-01-01 00:00:00\n", .{year_day.year});
    try writer.print("Build: {s}\n", .{@tagName(builtin.mode)});
    try writer.print("Iterations: Time-based ({d}s duration)\n\n", .{options.duration_ns / 1_000_000_000});

    try writer.print("| Benchmark | Operations | Time (ms) | ns/op |", .{});
    if (baseline_manager.baseline_results != null) {
        try writer.print(" vs Baseline |", .{});
    }
    try writer.print("\n", .{});

    try writer.print("|-----------|------------|-----------|-------|", .{});
    if (baseline_manager.baseline_results != null) {
        try writer.print("-------------|", .{});
    }
    try writer.print("\n", .{});

    for (results) |result| {
        const time_ms = @as(f64, @floatFromInt(result.elapsed_ns)) / 1_000_000.0;
        const confidence_symbol = if (result.confidence == .low or result.confidence == .insufficient) " ⚠" else "";

        try writer.print("| {s}{s} | {d} | {d:.1} | {d} |", .{ result.name, confidence_symbol, result.total_operations, time_ms, result.ns_per_op });

        if (baseline_manager.baseline_results != null) {
            if (baseline_manager.compare(result.name, result.ns_per_op)) |comparison| {
                const change = utils.formatPercentageChange(comparison.percent_change);
                try writer.print(" {s}{d:.1}% |", .{ change.sign, change.value });
            } else {
                try writer.print(" NEW |", .{});
            }
        }

        try writer.print("\n", .{});
    }

    // Add confidence legend if needed
    const confidence_stats = baseline_manager.getConfidenceStats(results);
    if (confidence_stats.low > 0 or confidence_stats.insufficient > 0) {
        try writer.print("\n**Confidence:** ⚠ indicates low statistical confidence ({} low, {} insufficient)\n", .{ confidence_stats.low, confidence_stats.insufficient });
    }

    if (baseline_manager.baseline_results != null) {
        try writer.print("\n**Legend:** Positive percentages indicate slower performance (regression), negative percentages indicate faster performance (improvement).\n", .{});
    }
}

fn outputJson(
    writer: anytype,
    results: []const BenchmarkResult,
    options: BenchmarkOptions,
    baseline_manager: *BaselineManager,
) !void {
    try writer.writeAll("{\n");
    try writer.print("  \"timestamp\": {d},\n", .{std.time.timestamp()});
    try writer.print("  \"build_mode\": \"{s}\",\n", .{@tagName(builtin.mode)});
    try writer.print("  \"duration_seconds\": {d},\n", .{options.duration_ns / 1_000_000_000});

    // Add confidence summary
    const confidence_stats = baseline_manager.getConfidenceStats(results);
    try writer.print("  \"confidence_stats\": {{\n", .{});
    try writer.print("    \"high\": {d},\n", .{confidence_stats.high});
    try writer.print("    \"medium\": {d},\n", .{confidence_stats.medium});
    try writer.print("    \"low\": {d},\n", .{confidence_stats.low});
    try writer.print("    \"insufficient\": {d}\n", .{confidence_stats.insufficient});
    try writer.print("  }},\n", .{});

    try writer.writeAll("  \"results\": [\n");

    for (results, 0..) |result, i| {
        if (i > 0) try writer.writeAll(",\n");

        try writer.print("    {{\n", .{});
        try writer.print("      \"name\": \"{s}\",\n", .{result.name});
        try writer.print("      \"operations\": {d},\n", .{result.total_operations});
        try writer.print("      \"elapsed_ns\": {d},\n", .{result.elapsed_ns});
        try writer.print("      \"ns_per_op\": {d},\n", .{result.ns_per_op});
        try writer.print("      \"confidence\": \"{s}\"", .{@tagName(result.confidence)});

        if (result.extra_info) |info| {
            try writer.print(",\n      \"extra_info\": \"{s}\"", .{info});
        }

        if (baseline_manager.compare(result.name, result.ns_per_op)) |comparison| {
            try writer.print(",\n      \"baseline_comparison\": {{\n", .{});
            try writer.print("        \"baseline_ns_per_op\": {d},\n", .{comparison.baseline_ns_per_op});
            try writer.print("        \"percent_change\": {d:.2},\n", .{comparison.percent_change});
            try writer.print("        \"is_improvement\": {}\n", .{comparison.is_improvement});
            try writer.print("      }}", .{});
        }

        try writer.print("\n    }}", .{});
    }

    try writer.writeAll("\n  ]\n}");
}

fn outputCsv(
    writer: anytype,
    results: []const BenchmarkResult,
    options: BenchmarkOptions,
    baseline_manager: *BaselineManager,
) !void {
    _ = options;

    try writer.writeAll("benchmark,operations,elapsed_ns,ns_per_op,confidence");
    if (baseline_manager.baseline_results != null) {
        try writer.writeAll(",baseline_ns_per_op,percent_change");
    }
    try writer.writeAll("\n");

    for (results) |result| {
        try writer.print("{s},{d},{d},{d},{s}", .{ result.name, result.total_operations, result.elapsed_ns, result.ns_per_op, @tagName(result.confidence) });

        if (baseline_manager.compare(result.name, result.ns_per_op)) |comparison| {
            try writer.print(",{d},{d:.2}", .{ comparison.baseline_ns_per_op, comparison.percent_change });
        } else if (baseline_manager.baseline_results != null) {
            try writer.writeAll(",,");
        }

        try writer.writeAll("\n");
    }
}

fn outputPretty(
    writer: anytype,
    results: []const BenchmarkResult,
    options: BenchmarkOptions,
    baseline_manager: *BaselineManager,
) !void {
    _ = options;

    const Color = struct {
        const reset = "\x1b[0m";
        const green = "\x1b[32m";
        const yellow = "\x1b[33m";
        const cyan = "\x1b[36m";
        const red = "\x1b[31m";
        const bold = "\x1b[1m";
        const dim = "\x1b[2m";
    };

    try writer.print("{s}╔══════════════════════════════════════════════════════════════╗{s}\n", .{ Color.bold, Color.reset });
    try writer.print("{s}║                    zz Performance Benchmarks                 ║{s}\n", .{ Color.bold, Color.reset });
    try writer.print("{s}╚══════════════════════════════════════════════════════════════╝{s}\n\n", .{ Color.bold, Color.reset });

    var total_time_ns: u64 = 0;
    var improvements: u32 = 0;
    var regressions: u32 = 0;
    var new_benchmarks: u32 = 0;
    var low_confidence: u32 = 0;

    // First pass: find maximum absolute percentage change for progress bar scaling
    var max_abs_change: f64 = 0.0;
    for (results) |result| {
        if (baseline_manager.compare(result.name, result.ns_per_op)) |comparison| {
            const abs_change = @abs(comparison.percent_change);
            if (abs_change > max_abs_change) {
                max_abs_change = abs_change;
            }
        }
    }

    for (results) |result| {
        total_time_ns += result.elapsed_ns;

        const time_formatted = text_builders.formatTime(result.ns_per_op);
        const time_str = std.mem.sliceTo(&time_formatted.buffer, 0);

        var status_color: []const u8 = Color.reset;
        var status_symbol: []const u8 = " ";

        // Check confidence first
        if (result.confidence == .low or result.confidence == .insufficient) {
            status_color = Color.red;
            status_symbol = result.confidence.getSymbol();
            low_confidence += 1;
        } else if (baseline_manager.compare(result.name, result.ns_per_op)) |comparison| {
            if (comparison.is_improvement) {
                status_color = Color.green;
                status_symbol = "✓";
                improvements += 1;
            } else if (comparison.is_regression) {
                status_color = Color.yellow;
                status_symbol = "⚠";
                regressions += 1;
            } else {
                status_symbol = result.confidence.getSymbol();
            }

            const baseline_formatted = text_builders.formatTime(comparison.baseline_ns_per_op);
            const baseline_str = std.mem.sliceTo(&baseline_formatted.buffer, 0);
            const progress_bar = utils.createChangeProgressBar(comparison.percent_change, max_abs_change);
            try writer.print("{s}{s} {s:<30} {s} [{s}] ({s}{d:.1}%{s} vs {s}){s}\n", .{ status_color, status_symbol, result.name, time_str, progress_bar, if (comparison.percent_change >= 0) "+" else "", comparison.percent_change, Color.reset, baseline_str, Color.reset });
        } else if (baseline_manager.baseline_results != null) {
            status_color = Color.cyan;
            status_symbol = "?";
            new_benchmarks += 1;

            const progress_bar = "          "; // No change info for new benchmarks
            try writer.print("{s}{s} {s:<30} {s} [{s}] (NEW){s}\n", .{ status_color, status_symbol, result.name, time_str, progress_bar, Color.reset });
        } else {
            status_symbol = result.confidence.getSymbol();
            const progress_bar = "          "; // No baseline for comparison
            try writer.print("{s}{s} {s:<30} {s} [{s}]{s}\n", .{ status_color, status_symbol, result.name, time_str, progress_bar, Color.reset });
        }
    }

    try writer.writeAll("\n──────────────────────────────────────────────────────────────\n");
    const total_time_ms = @as(f64, @floatFromInt(total_time_ns)) / 1_000_000.0;
    try writer.print("Summary: {d} benchmarks, {d:.2} ms total\n", .{ results.len, total_time_ms });

    if (baseline_manager.baseline_results != null) {
        const regression_color = if (regressions == 0) Color.dim else Color.yellow;
        try writer.print("         {s}✓ {d} improved{s}  {s}⚠ {d} regressed{s}", .{ Color.green, improvements, Color.reset, regression_color, regressions, Color.reset });
        if (new_benchmarks > 0) {
            try writer.print("  {s}? {d} new{s}", .{ Color.cyan, new_benchmarks, Color.reset });
        }
        try writer.writeAll("\n");
    }

    if (low_confidence > 0) {
        try writer.print("Warning: {s}{d} benchmarks{s} have low statistical confidence\n", .{ Color.red, low_confidence, Color.reset });
    }
}
