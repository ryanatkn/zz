const std = @import("std");
const benchmark_lib = @import("../../../lib/benchmark/mod.zig");
const BenchmarkResult = benchmark_lib.BenchmarkResult;
const BenchmarkOptions = benchmark_lib.BenchmarkOptions;
const BenchmarkError = benchmark_lib.BenchmarkError;

// Import ZON components
const zon_mod = @import("../../../lib/languages/zon/mod.zig");

pub fn runZonPipelineBenchmarks(allocator: std.mem.Allocator, options: BenchmarkOptions) BenchmarkError![]BenchmarkResult {
    var results = std.ArrayList(BenchmarkResult).init(allocator);
    errdefer {
        for (results.items) |result| {
            result.deinit(allocator);
        }
        results.deinit();
    }

    const effective_duration = @as(u64, @intFromFloat(@as(f64, @floatFromInt(options.duration_ns)) * 2.0 * options.duration_multiplier));

    // Generate test data
    const test_zon = try generateZonData(allocator, 100); // ~10KB
    defer allocator.free(test_zon);

    // Complete pipeline: parse → format → validate
    {
        const context = struct {
            allocator: std.mem.Allocator,
            content: []const u8,

            pub fn run(ctx: @This()) anyerror!void {
                // Format ZON
                std.debug.print("[zon-pipeline-debug] Starting formatZonString...\n", .{});
                const formatted = zon_mod.formatZonString(ctx.allocator, ctx.content) catch |err| {
                    std.debug.print("[zon-pipeline-debug] formatZonString failed: {}\n", .{err});
                    return err;
                };
                defer ctx.allocator.free(formatted);
                std.debug.print("[zon-pipeline-debug] formatZonString complete ({} bytes)\n", .{formatted.len});

                // Validate ZON
                std.debug.print("[zon-pipeline-debug] Starting validateZonString...\n", .{});
                const diagnostics = zon_mod.validateZonString(ctx.allocator, ctx.content) catch |err| {
                    std.debug.print("[zon-pipeline-debug] validateZonString failed: {}\n", .{err});
                    return err;
                };
                defer {
                    for (diagnostics) |diag| {
                        ctx.allocator.free(diag.message);
                    }
                    ctx.allocator.free(diagnostics);
                }
                std.debug.print("[zon-pipeline-debug] validateZonString complete ({} diagnostics)\n", .{diagnostics.len});

                // Extract schema
                std.debug.print("[zon-pipeline-debug] Starting extractZonSchema...\n", .{});
                var schema = zon_mod.extractZonSchema(ctx.allocator, ctx.content) catch |err| {
                    std.debug.print("[zon-pipeline-debug] extractZonSchema failed: {}\n", .{err});
                    return err;
                };
                defer schema.deinit();
                std.debug.print("[zon-pipeline-debug] extractZonSchema complete ({} nodes)\n", .{schema.statistics.total_nodes});

                std.mem.doNotOptimizeAway(formatted.len);
                std.mem.doNotOptimizeAway(diagnostics.len);
                std.mem.doNotOptimizeAway(schema.statistics.total_nodes);
            }
        }{ .allocator = allocator, .content = test_zon };

        const result = try benchmark_lib.measureOperationNamedWithSuite(allocator, "zon-pipeline", "ZON Complete Pipeline (10KB)", effective_duration, options.warmup, context, @TypeOf(context).run);
        try results.append(result);

        // Performance target check: <2ms (2,000,000ns) for 10KB complete pipeline
        if (result.ns_per_op > 2_000_000) {
            std.log.warn("ZON Complete pipeline performance target missed: {}ns > 2,000,000ns for 10KB", .{result.ns_per_op});
        }
    }

    // build.zig.zon processing
    {
        std.debug.print("[zon-pipeline-debug] Starting build.zig.zon benchmark...\n", .{});
        const build_zon =
            \\.{
            \\    .name = "example_project",
            \\    .version = "0.1.0",
            \\    .minimum_zig_version = "0.14.0",
            \\    .dependencies = .{
            \\        .std = .{
            \\            .url = "https://github.com/ziglang/zig",
            \\            .hash = "1220abcd1234567890abcdef1234567890abcdef1234567890abcdef1234567890ab",
            \\        },
            \\        .utils = .{
            \\            .url = "https://github.com/example/utils", 
            \\            .hash = "1220efgh5678901234567890efgh5678901234567890efgh5678901234567890efgh",
            \\        },
            \\    },
            \\    .paths = .{
            \\        "build.zig",
            \\        "build.zig.zon",
            \\        "src",
            \\        "README.md",
            \\        "LICENSE",
            \\    },
            \\}
        ;

        const context = struct {
            allocator: std.mem.Allocator,
            content: []const u8,

            pub fn run(ctx: @This()) anyerror!void {
                // Format
                const formatted = try zon_mod.formatZonString(ctx.allocator, ctx.content);
                defer ctx.allocator.free(formatted);

                // Validate
                const diagnostics = try zon_mod.validateZonString(ctx.allocator, ctx.content);
                defer {
                    for (diagnostics) |diag| {
                        ctx.allocator.free(diag.message);
                    }
                    ctx.allocator.free(diagnostics);
                }

                std.mem.doNotOptimizeAway(formatted.len);
                std.mem.doNotOptimizeAway(diagnostics.len);
            }
        }{ .allocator = allocator, .content = build_zon };

        std.debug.print("[zon-pipeline-debug] About to start build.zon measurement...\n", .{});
        const result = try benchmark_lib.measureOperationNamedWithSuite(allocator, "zon-pipeline", "ZON build.zig.zon Processing", effective_duration, options.warmup, context, @TypeOf(context).run);
        try results.append(result);
    }

    // Configuration file processing
    {
        const config_zon =
            \\.{
            \\    .base_patterns = "extend",
            \\    .ignored_patterns = .{
            \\        "node_modules",
            \\        "*.tmp",
            \\        "cache",
            \\        "dist",
            \\        "build",
            \\    },
            \\    .hidden_files = .{
            \\        ".DS_Store",
            \\        "Thumbs.db",
            \\        "*.swp",
            \\    },
            \\    .respect_gitignore = true,
            \\    .symlink_behavior = "skip",
            \\    .format = .{
            \\        .indent_size = 4,
            \\        .indent_style = "space",
            \\        .line_width = 100,
            \\        .preserve_newlines = true,
            \\        .trailing_comma = false,
            \\    },
            \\}
        ;

        const context = struct {
            allocator: std.mem.Allocator,
            content: []const u8,

            pub fn run(ctx: @This()) anyerror!void {
                // Format
                const formatted = try zon_mod.formatZonString(ctx.allocator, ctx.content);
                defer ctx.allocator.free(formatted);

                // Validate
                const diagnostics = try zon_mod.validateZonString(ctx.allocator, ctx.content);
                defer {
                    for (diagnostics) |diag| {
                        ctx.allocator.free(diag.message);
                    }
                    ctx.allocator.free(diagnostics);
                }

                std.mem.doNotOptimizeAway(formatted.len);
                std.mem.doNotOptimizeAway(diagnostics.len);
            }
        }{ .allocator = allocator, .content = config_zon };

        const result = try benchmark_lib.measureOperationNamedWithSuite(allocator, "zon-pipeline", "ZON Config File Processing", effective_duration, options.warmup, context, @TypeOf(context).run);
        try results.append(result);
    }

    // Format → Parse round-trip
    {
        const context = struct {
            allocator: std.mem.Allocator,
            content: []const u8,

            pub fn run(ctx: @This()) anyerror!void {
                // Format
                const formatted = try zon_mod.formatZonString(ctx.allocator, ctx.content);
                defer ctx.allocator.free(formatted);

                // Extract schema from formatted result (round-trip test)
                var schema = try zon_mod.extractZonSchema(ctx.allocator, formatted);
                defer schema.deinit();

                std.mem.doNotOptimizeAway(schema.statistics.total_nodes);
            }
        }{ .allocator = allocator, .content = test_zon };

        const result = try benchmark_lib.measureOperationNamedWithSuite(allocator, "zon-pipeline", "ZON Round-Trip (10KB)", effective_duration, options.warmup, context, @TypeOf(context).run);
        try results.append(result);
    }

    // Error recovery benchmark
    {
        const invalid_zon =
            \\.{
            \\    .name = "invalid_project",
            \\    .version = "0.1.0"
            \\    // Missing comma here
            \\    .dependencies = .{
            \\        .std = .{
            \\            .url = "https://github.com/ziglang/zig",
            \\            .hash = "invalid_hash_format",
            \\        },
            \\        .missing_url = .{
            \\            // Missing url field
            \\            .hash = "1220abcd1234567890abcdef1234567890abcdef1234567890abcdef1234567890ab",
            \\        },
            \\    },
            \\    .paths = .{
            \\        "build.zig",
            \\        "src",
            \\        // trailing comma
            \\    },
            \\    // Missing closing brace
        ;

        const context = struct {
            allocator: std.mem.Allocator,
            content: []const u8,

            pub fn run(ctx: @This()) anyerror!void {
                // Try to validate invalid ZON and collect diagnostics
                const diagnostics = try zon_mod.validateZonString(ctx.allocator, ctx.content);
                defer {
                    for (diagnostics) |diag| {
                        ctx.allocator.free(diag.message);
                    }
                    ctx.allocator.free(diagnostics);
                }

                std.mem.doNotOptimizeAway(diagnostics.len);
            }
        }{ .allocator = allocator, .content = invalid_zon };

        const result = try benchmark_lib.measureOperationNamedWithSuite(allocator, "zon-pipeline", "ZON Error Recovery", effective_duration, options.warmup, context, @TypeOf(context).run);
        try results.append(result);
    }

    return results.toOwnedSlice();
}

fn generateZonData(allocator: std.mem.Allocator, field_count: u32) ![]u8 {
    var output = std.ArrayList(u8).init(allocator);
    errdefer output.deinit();

    try output.appendSlice(".{\n");
    try output.writer().print("    .name = \"test_package\",\n", .{});
    try output.writer().print("    .version = \"1.0.0\",\n", .{});
    try output.writer().print("    .description = \"Generated test ZON with {} fields\",\n", .{field_count});

    try output.appendSlice("    .metadata = .{\n");

    var i: u32 = 0;
    while (i < field_count) : (i += 1) {
        const field_type = i % 6;
        switch (field_type) {
            0 => try output.writer().print("        .string_field_{} = \"value_{}\",\n", .{ i, i }),
            1 => try output.writer().print("        .number_field_{} = {},\n", .{ i, i }),
            2 => try output.writer().print("        .bool_field_{} = {},\n", .{ i, i % 2 == 0 }),
            3 => try output.writer().print("        .hex_field_{} = 0x{x},\n", .{ i, i }),
            4 => try output.writer().print("        .array_field_{} = .{{ {}, {}, {} }},\n", .{ i, i * 2, i * 3, i * 4 }),
            5 => try output.writer().print("        .nested_field_{} = .{{ .inner = \"value_{}\" }},\n", .{ i, i }),
            else => unreachable,
        }
    }

    try output.appendSlice("    },\n");

    try output.appendSlice("    .dependencies = .{\n");
    const dep_count = @min(field_count / 10, 20); // Up to 20 dependencies
    i = 0;
    while (i < dep_count) : (i += 1) {
        try output.writer().print("        .dep_{} = .{{\n", .{i});
        try output.writer().print("            .url = \"https://github.com/example/dep_{}\",\n", .{i});
        try output.writer().print("            .hash = \"1220abcd{}efgh{}ijkl{}mnop{}\",\n", .{ i, i * 2, i * 3, i * 4 });
        try output.appendSlice("        },\n");
    }
    try output.appendSlice("    },\n");

    try output.appendSlice("    .paths = .{\n");
    try output.appendSlice("        \"build.zig\",\n");
    try output.appendSlice("        \"build.zig.zon\",\n");
    try output.appendSlice("        \"src\",\n");
    try output.appendSlice("        \"README.md\",\n");
    try output.appendSlice("    },\n");

    try output.appendSlice("}");

    return output.toOwnedSlice();
}
