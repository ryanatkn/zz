const std = @import("std");
const benchmark_lib = @import("../../../lib/benchmark/mod.zig");
const BenchmarkResult = benchmark_lib.BenchmarkResult;
const BenchmarkOptions = benchmark_lib.BenchmarkOptions;
const BenchmarkError = benchmark_lib.BenchmarkError;

// Import ZON components
const ZonLexer = @import("../../../lib/languages/zon/lexer.zig").ZonLexer;

pub fn runZonLexerBenchmarks(allocator: std.mem.Allocator, options: BenchmarkOptions) BenchmarkError![]BenchmarkResult {
    var results = std.ArrayList(BenchmarkResult).init(allocator);
    errdefer {
        for (results.items) |result| {
            result.deinit(allocator);
        }
        results.deinit();
    }
    
    const effective_duration = @as(u64, @intFromFloat(@as(f64, @floatFromInt(options.duration_ns)) * 1.5 * options.duration_multiplier));
    
    // Generate test data
    const small_zon = try generateZonData(allocator, 10);   // ~1KB
    defer allocator.free(small_zon);
    
    const medium_zon = try generateZonData(allocator, 100); // ~10KB  
    defer allocator.free(medium_zon);
    
    const large_zon = try generateZonData(allocator, 1000); // ~100KB
    defer allocator.free(large_zon);
    
    // Lexer benchmark for small ZON (1KB)
    {
        const context = struct {
            allocator: std.mem.Allocator,
            content: []const u8,
            
            pub fn run(ctx: @This()) anyerror!void {
                var lexer = ZonLexer.init(ctx.allocator, ctx.content, .{});
                defer lexer.deinit();
                
                const tokens = try lexer.tokenize();
                defer ctx.allocator.free(tokens);
                
                std.mem.doNotOptimizeAway(tokens.len);
            }
        }{ .allocator = allocator, .content = small_zon };
        
        const result = try benchmark_lib.measureOperationNamedWithSuite(allocator, "zon-lexer", "ZON Lexer Small (1KB)", effective_duration, options.warmup, context, @TypeOf(context).run);
        try results.append(result);
    }
    
    // Lexer benchmark for medium ZON (10KB) - Performance target
    {
        const context = struct {
            allocator: std.mem.Allocator,
            content: []const u8,
            
            pub fn run(ctx: @This()) anyerror!void {
                var lexer = ZonLexer.init(ctx.allocator, ctx.content, .{});
                defer lexer.deinit();
                
                const tokens = try lexer.tokenize();
                defer ctx.allocator.free(tokens);
                
                std.mem.doNotOptimizeAway(tokens.len);
            }
        }{ .allocator = allocator, .content = medium_zon };
        
        const result = try benchmark_lib.measureOperationNamedWithSuite(allocator, "zon-lexer", "ZON Lexer Medium (10KB)", effective_duration, options.warmup, context, @TypeOf(context).run);
        try results.append(result);
        
        // Performance target check: <0.1ms (100,000ns) for 10KB
        if (result.ns_per_op > 100_000) {
            std.log.warn("ZON Lexer performance target missed: {}ns > 100,000ns for 10KB", .{result.ns_per_op});
        }
    }
    
    // Lexer benchmark for large ZON (100KB)
    {
        const context = struct {
            allocator: std.mem.Allocator,
            content: []const u8,
            
            pub fn run(ctx: @This()) anyerror!void {
                var lexer = ZonLexer.init(ctx.allocator, ctx.content, .{});
                defer lexer.deinit();
                
                const tokens = try lexer.tokenize();
                defer ctx.allocator.free(tokens);
                
                std.mem.doNotOptimizeAway(tokens.len);
            }
        }{ .allocator = allocator, .content = large_zon };
        
        const result = try benchmark_lib.measureOperationNamedWithSuite(allocator, "zon-lexer", "ZON Lexer Large (100KB)", effective_duration, options.warmup, context, @TypeOf(context).run);
        try results.append(result);
    }
    
    // Real-world build.zig.zon file
    {
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
            \\        .json = .{
            \\            .url = "https://github.com/example/json-lib",
            \\            .hash = "1220ijkl9012345678901234ijkl9012345678901234ijkl9012345678901234ijkl",
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
                var lexer = ZonLexer.init(ctx.allocator, ctx.content, .{});
                defer lexer.deinit();
                
                const tokens = try lexer.tokenize();
                defer ctx.allocator.free(tokens);
                
                std.mem.doNotOptimizeAway(tokens.len);
            }
        }{ .allocator = allocator, .content = build_zon };
        
        const result = try benchmark_lib.measureOperationNamedWithSuite(allocator, "zon-lexer", "ZON Lexer build.zig.zon", effective_duration, options.warmup, context, @TypeOf(context).run);
        try results.append(result);
    }
    
    // Configuration ZON file
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
                var lexer = ZonLexer.init(ctx.allocator, ctx.content, .{});
                defer lexer.deinit();
                
                const tokens = try lexer.tokenize();
                defer ctx.allocator.free(tokens);
                
                std.mem.doNotOptimizeAway(tokens.len);
            }
        }{ .allocator = allocator, .content = config_zon };
        
        const result = try benchmark_lib.measureOperationNamedWithSuite(allocator, "zon-lexer", "ZON Lexer Config File", effective_duration, options.warmup, context, @TypeOf(context).run);
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