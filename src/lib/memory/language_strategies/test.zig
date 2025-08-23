const std = @import("std");
const testing = std.testing;

// Import all memory modules
const memory = @import("mod.zig");
const MemoryStrategy = memory.MemoryStrategy;
const MemoryStats = memory.MemoryStats;
const MemoryContext = memory.MemoryContext;
const language_defaults = memory.language_defaults;

// Test node type
const TestNode = struct {
    value: i32,
    next: ?*TestNode = null,
};

test "memory strategy tagged union" {
    // Test simple strategies
    const arena = MemoryStrategy{ .arena_only = {} };
    try testing.expectEqualStrings("arena-only (simple, safe)", arena.describe());

    const pooled = MemoryStrategy{ .pooled = .{ .initial_capacity = 512 } };
    try testing.expectEqualStrings("pooled (optimized for allocation churn)", pooled.describe());

    // Test hybrid composition
    const hybrid = MemoryStrategy{
        .hybrid = .{
            .nodes = .small_pool,
            .arrays = .size_classed,
            .strings = .interned,
        },
    };
    try testing.expectEqualStrings("hybrid (composed strategies)", hybrid.describe());
}

test "language-specific default strategies" {
    // Test that each language has a valid default strategy
    const json_strat = language_defaults.JSON_DEFAULT_STRATEGY;
    const zon_strat = language_defaults.ZON_DEFAULT_STRATEGY;
    const ts_strat = language_defaults.TYPESCRIPT_DEFAULT_STRATEGY;

    // Verify JSON uses hybrid with specific optimizations
    try testing.expect(json_strat == .hybrid);
    try testing.expect(json_strat.hybrid.nodes == .small_pool);
    try testing.expect(json_strat.hybrid.strings == .interned);

    // Verify ZON uses simpler strategy
    try testing.expect(zon_strat == .hybrid);
    try testing.expect(zon_strat.hybrid.nodes == .arena);
    try testing.expect(zon_strat.hybrid.strings == .persistent);

    // Verify TypeScript has appropriate defaults
    try testing.expect(ts_strat == .hybrid);
    try testing.expect(ts_strat.hybrid.nodes == .small_pool);
}

test "memory context with arena strategy" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var ctx = MemoryContext(TestNode).init(allocator, .arena_only);
    defer ctx.deinit();

    // Allocate some nodes
    const node1 = try ctx.allocateNode();
    node1.value = 42;

    const node2 = try ctx.allocateNode();
    node2.value = 100;

    // Allocate arrays
    const array = try ctx.allocateNodes(10);
    try testing.expect(array.len == 10);

    // Allocate strings
    const text = try ctx.allocateAstText("hello world");
    try testing.expectEqualStrings("hello world", text);

    // Check stats
    const stats = ctx.getStats();
    try testing.expect(stats.nodes_allocated == 2);
    try testing.expect(stats.arrays_allocated == 1);
    try testing.expect(stats.strings_allocated == 1);
}

test "memory context with hybrid strategy" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const hybrid_strategy = MemoryStrategy{
        .hybrid = .{
            .nodes = .small_pool,
            .arrays = .size_classed,
            .strings = .interned,
        },
    };

    var ctx = MemoryContext(TestNode).init(allocator, hybrid_strategy);
    defer ctx.deinit();

    // Test node pooling
    const node1 = try ctx.allocateNode();
    node1.value = 1;
    ctx.releaseNode(node1);

    const node2 = try ctx.allocateNode();
    // If pooling works, node2 might be the same as node1
    node2.value = 2;

    // Test string interning
    const str1 = try ctx.allocateAstText("common");
    const str2 = try ctx.allocateAstText("common");
    // With interning, these might be the same pointer
    _ = str1;
    _ = str2;

    const stats = ctx.getStats();
    try testing.expect(stats.nodes_allocated >= 1);
}

test "memory stats tracking" {
    var stats = MemoryStats{};

    // Test efficiency calculation
    stats.total_bytes_allocated = 1000;
    stats.arena_bytes_used = 500;
    stats.pool_bytes_used = 300;
    const efficiency = stats.efficiency();
    try testing.expect(efficiency > 0);

    // Test pool hit rate
    stats.node_pool_hits = 80;
    stats.node_pool_misses = 20;
    const hit_rate = stats.poolHitRate();
    try testing.expect(hit_rate == 80.0);

    // Test allocation rate
    stats.nodes_allocated = 100;
    stats.allocation_time_ns = 1_000_000; // 1ms
    const alloc_rate = stats.allocationRate();
    try testing.expect(alloc_rate == 100.0); // 100 allocs/ms
}

test "workload-based strategy selection" {
    // Small file should get simple strategy
    const small_strat = language_defaults.selectStrategyForWorkload(
        100, // 100 bytes
        10, // 10 nodes
        null, // no language hint
    );
    try testing.expect(small_strat == .arena_only);

    // Large file should get advanced strategy
    const large_strat = language_defaults.selectStrategyForWorkload(
        20 * 1024 * 1024, // 20MB
        100000, // lots of nodes
        null,
    );
    try testing.expect(large_strat == .metadata_tracked);

    // JSON hint should get JSON defaults
    const json_strat = language_defaults.selectStrategyForWorkload(
        5000, // 5KB
        500, // moderate nodes
        "json",
    );
    try testing.expect(json_strat == .hybrid);
    try testing.expect(json_strat.hybrid.strings == .interned);
}

test "adaptive strategy upgrade" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Note: Can't use pointers to stack variables in union, so using language defaults
    const adaptive_strat = MemoryStrategy{
        .adaptive = .{
            .config = .{
                .sample_period = 10, // Check after 10 allocations
                .upgrade_threshold = 1.0, // Low threshold for testing
                .memory_threshold = 100,
                .allow_downgrade = false,
            },
            .initial = &language_defaults.SIMPLE_STRATEGY,
            .target = &language_defaults.OPTIMIZED_STRATEGY,
        },
    };

    var ctx = MemoryContext(TestNode).init(allocator, adaptive_strat);
    defer ctx.deinit();

    // Allocate enough to potentially trigger upgrade
    for (0..15) |i| {
        const node = try ctx.allocateNode();
        node.value = @intCast(i);
    }

    const stats = ctx.getStats();
    // Upgrade might have happened
    _ = stats;
}

test "memory context convenience functions" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test language-specific convenience functions
    var json_ctx = try memory.createForJson(TestNode, allocator);
    defer json_ctx.deinit();

    var zon_ctx = try memory.createForZon(TestNode, allocator);
    defer zon_ctx.deinit();

    // JSON should use hybrid with interning
    try testing.expect(json_ctx.strategy == .hybrid);

    // ZON should use simpler hybrid
    try testing.expect(zon_ctx.strategy == .hybrid);
}

test "formatted text allocation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var ctx = MemoryContext(TestNode).init(allocator, .arena_only);
    defer ctx.deinit();

    const formatted = try ctx.allocatePrintAstText("Node value: {d}", .{42});
    try testing.expectEqualStrings("Node value: 42", formatted);

    const stats = ctx.getStats();
    try testing.expect(stats.strings_allocated == 1);
    try testing.expect(stats.string_bytes_used > 0);

    // Simulate what an AST would do - take ownership of transferred texts
    const transferred = try ctx.transferOwnership();
    defer transferred.deinit(allocator);

    // Verify the text was transferred correctly
    try testing.expect(transferred.texts.len == 1);
    try testing.expectEqualStrings("Node value: 42", transferred.texts[0]);
}

test "strategy description" {
    const json_desc = language_defaults.describeLanguageStrategy("json");
    try testing.expect(std.mem.indexOf(u8, json_desc, "nested objects") != null);

    const zon_desc = language_defaults.describeLanguageStrategy("zon");
    try testing.expect(std.mem.indexOf(u8, zon_desc, "config files") != null);

    const unknown_desc = language_defaults.describeLanguageStrategy("unknown");
    try testing.expect(std.mem.indexOf(u8, unknown_desc, "adaptive") != null);
}
