const std = @import("std");
const testing = std.testing;

// Import all detailed parser components
const mod = @import("mod.zig");
const DetailedParser = mod.DetailedParser;
const FactGenerator = mod.FactGenerator;
const BoundaryParser = mod.BoundaryParser;
const ViewportManager = mod.ViewportManager;
const BoundaryCache = mod.BoundaryCache;
const Parser = @import("parser.zig").Parser;
const Grammar = @import("../../grammar/mod.zig").Grammar;
const Rule = @import("../../grammar/mod.zig").Rule;

// Import foundation types
const Span = @import("../foundation/types/span.zig").Span;
const Fact = @import("../foundation/types/fact.zig").Fact;
const Token = @import("../foundation/types/token.zig").Token;
const Predicate = @import("../foundation/types/predicate.zig").Predicate;
const Value = @import("../foundation/types/predicate.zig").Value;

// Import centralized AST infrastructure
const AST = @import("../../ast/mod.zig").AST;
const ASTNode = @import("../../ast/mod.zig").ASTNode;
const createZonAST = @import("../../ast/mod.zig").createZonAST;
const createStructuredAST = @import("../../ast/mod.zig").createStructuredAST;
const ASTStructure = @import("../../ast/mod.zig").ASTStructure;
const TestContext = @import("../../ast/mod.zig").TestContext;

// Import structural types
const ParseBoundary = @import("../structural/mod.zig").ParseBoundary;
const BoundaryKind = @import("../foundation/types/predicate.zig").BoundaryKind;

// ============================================================================
// DetailedParser Integration Tests
// ============================================================================

test "detailed parser initialization and cleanup" {
    var detailed = try DetailedParser.init(testing.allocator);
    defer detailed.deinit();

    try testing.expect(detailed.generation == 0);
    try testing.expect(detailed.cache.max_capacity > 0);
}

test "viewport parsing performance targets" {
    var detailed = try DetailedParser.init(testing.allocator);
    defer detailed.deinit();

    // Create mock viewport and boundaries
    const viewport = Span.init(0, 1000);
    const boundaries = try createMockBoundaries(testing.allocator, 5);
    defer testing.allocator.free(boundaries);

    const tokens = try createMockTokens(testing.allocator, 50);
    defer testing.allocator.free(tokens);

    // Measure viewport parsing time
    const start = std.time.nanoTimestamp();
    var fact_stream = try detailed.parseViewport(viewport, boundaries, tokens);
    defer fact_stream.deinit();
    const elapsed = std.time.nanoTimestamp() - start;

    // Target: <10ms for viewport parsing
    const elapsed_ms = @as(f64, @floatFromInt(elapsed)) / 1_000_000.0;
    try testing.expect(elapsed_ms < 10.0);

    // FactStream doesn't store facts, it processes them
    // For testing, we just verify that the stream was created successfully
}

test "incremental edit processing" {
    var detailed = try DetailedParser.init(testing.allocator);
    defer detailed.deinit();

    // Create initial state
    const IncrementalEdit = @import("../incremental/edit.zig").Edit;
    const edit = IncrementalEdit.init(
        Span.init(100, 200),
        .replace,
        "modified content",
    );

    const affected_boundaries = try createMockBoundaries(testing.allocator, 2);
    defer testing.allocator.free(affected_boundaries);

    const tokens = try createMockTokens(testing.allocator, 20);
    defer testing.allocator.free(tokens);

    // Process incremental edit
    const start = std.time.nanoTimestamp();
    const delta = try detailed.processEdit(edit, affected_boundaries, tokens);
    // FactDelta doesn't need explicit cleanup - it just holds references
    const elapsed = std.time.nanoTimestamp() - start;

    // Target: <5ms for incremental updates
    const elapsed_ms = @as(f64, @floatFromInt(elapsed)) / 1_000_000.0;
    try testing.expect(elapsed_ms < 5.0);

    // Verify delta contains changes
    try testing.expect(!delta.isEmpty());
}

test "cache hit rate targets" {
    var detailed = try DetailedParser.init(testing.allocator);
    defer detailed.deinit();

    const boundaries = try createMockBoundaries(testing.allocator, 3);
    defer testing.allocator.free(boundaries);

    const tokens = try createMockTokens(testing.allocator, 30);
    defer testing.allocator.free(tokens);

    const viewport = Span.init(0, 500);

    // Parse same viewport multiple times to build cache
    for (0..10) |_| {
        var fact_stream = try detailed.parseViewport(viewport, boundaries, tokens);
        fact_stream.deinit();
    }

    const stats = detailed.getStats();

    // Target: >95% cache hit rate
    try testing.expect(stats.cache_hit_rate > 0.95);
}

// ============================================================================
// FactGenerator Tests
// ============================================================================

test "fact generator initialization" {
    var generator = FactGenerator.init(testing.allocator);
    defer generator.deinit();

    try testing.expect(generator.next_fact_id == 1);
    try testing.expect(generator.generation == 0);
}

test "AST to facts conversion" {
    var generator = FactGenerator.init(testing.allocator);
    defer generator.deinit();

    // Create mock AST using centralized infrastructure
    var ast = createMockAST();
    defer ast.deinit();

    const boundary = createMockBoundary(Span.init(0, 100), .function);

    const facts = try generator.fromAST(ast, boundary);
    defer testing.allocator.free(facts);

    try testing.expect(facts.len > 0);

    // Verify fact structure
    for (facts) |fact| {
        try testing.expect(fact.id > 0);
        try testing.expect(fact.confidence > 0.0);
        try testing.expect(fact.generation == 0);
    }
}

test "fact generation performance" {
    var generator = FactGenerator.init(testing.allocator);
    defer generator.deinit();

    const ast = createLargeAST(); // Create AST with many nodes
    const boundary = createMockBoundary(Span.init(0, 1000), .function);

    const start = std.time.nanoTimestamp();
    const facts = try generator.fromAST(ast, boundary);
    defer testing.allocator.free(facts);
    const elapsed = std.time.nanoTimestamp() - start;

    // Target: <100ns per fact generated
    const facts_per_ns = @as(f64, @floatFromInt(facts.len)) / @as(f64, @floatFromInt(elapsed));
    const ns_per_fact = 1.0 / facts_per_ns;

    try testing.expect(ns_per_fact < 100.0);
}

test "fact generation statistics" {
    var generator = FactGenerator.init(testing.allocator);
    defer generator.deinit();

    const initial_stats = generator.getStats();
    try testing.expect(initial_stats.facts_generated == 0);
    try testing.expect(initial_stats.conversions_performed == 0);

    // Generate some facts using centralized AST infrastructure
    var ast = createMockAST();
    defer ast.deinit();

    const boundary = createMockBoundary(Span.init(0, 100), .function);

    const facts = try generator.fromAST(ast, boundary);
    defer testing.allocator.free(facts);

    const updated_stats = generator.getStats();
    try testing.expect(updated_stats.facts_generated == facts.len);
    try testing.expect(updated_stats.conversions_performed == 1);
    try testing.expect(updated_stats.total_conversion_time_ns > 0);
}

// ============================================================================
// BoundaryParser Tests
// ============================================================================

test "boundary parser initialization" {
    var parser = try BoundaryParser.init(testing.allocator);
    defer parser.deinit();

    const stats = parser.getStats();
    try testing.expect(stats.boundaries_parsed == 0);
    try testing.expect(stats.total_parse_time_ns == 0);
}

test "single boundary parsing" {
    var parser = try BoundaryParser.init(testing.allocator);
    defer parser.deinit();

    var test_parser = try createTestParser(testing.allocator);
    defer test_parser.deinit();

    var fact_generator = FactGenerator.init(testing.allocator);
    defer fact_generator.deinit();

    var cache = try BoundaryCache.init(testing.allocator, 10);
    defer cache.deinit();

    const boundary = createMockBoundary(Span.init(0, 100), .function);
    const tokens = try createMockTokens(testing.allocator, 10);
    defer testing.allocator.free(tokens);

    const facts = try parser.parseBoundary(
        boundary,
        tokens,
        &test_parser,
        &fact_generator,
        &cache,
    );
    defer testing.allocator.free(facts);

    try testing.expect(facts.len > 0);

    const stats = parser.getStats();
    try testing.expect(stats.boundaries_parsed == 1);
}

test "multiple boundary parsing" {
    var parser = try BoundaryParser.init(testing.allocator);
    defer parser.deinit();

    var test_parser = try createTestParser(testing.allocator);
    defer test_parser.deinit();

    var fact_generator = FactGenerator.init(testing.allocator);
    defer fact_generator.deinit();

    var cache = try BoundaryCache.init(testing.allocator, 10);
    defer cache.deinit();

    const boundaries = try createMockBoundaries(testing.allocator, 3);
    defer testing.allocator.free(boundaries);

    const tokens = try createMockTokens(testing.allocator, 30);
    defer testing.allocator.free(tokens);

    const results = try parser.parseBoundaries(
        boundaries,
        tokens,
        &test_parser,
        &fact_generator,
        &cache,
    );
    defer {
        for (results) |facts| {
            testing.allocator.free(facts);
        }
        testing.allocator.free(results);
    }

    try testing.expect(results.len == boundaries.len);

    const stats = parser.getStats();
    try testing.expect(stats.boundaries_parsed == boundaries.len);
}

test "visible boundary parsing" {
    var parser = try BoundaryParser.init(testing.allocator);
    defer parser.deinit();

    var test_parser = try createTestParser(testing.allocator);
    defer test_parser.deinit();

    var fact_generator = FactGenerator.init(testing.allocator);
    defer fact_generator.deinit();

    var cache = try BoundaryCache.init(testing.allocator, 10);
    defer cache.deinit();

    // Create boundaries, some visible, some not
    const all_boundaries = &[_]ParseBoundary{
        createMockBoundary(Span.init(0, 50), .function), // Visible
        createMockBoundary(Span.init(75, 125), .function), // Visible
        createMockBoundary(Span.init(200, 250), .function), // Not visible
    };

    const viewport = Span.init(0, 150); // Covers first two boundaries
    const tokens = try createMockTokens(testing.allocator, 25);
    defer testing.allocator.free(tokens);

    const results = try parser.parseVisibleBoundaries(
        all_boundaries,
        viewport,
        tokens,
        &test_parser,
        &fact_generator,
        &cache,
    );
    defer {
        for (results) |facts| {
            testing.allocator.free(facts);
        }
        testing.allocator.free(results);
    }

    // Should only parse 2 visible boundaries
    try testing.expect(results.len == 2);
}

test "boundary update after edit" {
    var parser = try BoundaryParser.init(testing.allocator);
    defer parser.deinit();

    var test_parser = try createTestParser(testing.allocator);
    defer test_parser.deinit();

    var fact_generator = FactGenerator.init(testing.allocator);
    defer fact_generator.deinit();

    var cache = try BoundaryCache.init(testing.allocator, 10);
    defer cache.deinit();

    const boundary = createMockBoundary(Span.init(0, 100), .function);
    const tokens = try createMockTokens(testing.allocator, 10);
    defer testing.allocator.free(tokens);

    // Initial parse to populate cache
    const initial_facts = try parser.parseBoundary(
        boundary,
        tokens,
        &test_parser,
        &fact_generator,
        &cache,
    );
    defer testing.allocator.free(initial_facts);

    // Update after edit
    var update_result = try parser.updateBoundary(
        boundary,
        tokens,
        &test_parser,
        &fact_generator,
        &cache,
    );
    defer update_result.deinit(testing.allocator);

    try testing.expect(update_result.new_facts.len > 0);
    // old_facts might be null if not previously cached
}

// ============================================================================
// ViewportManager Tests
// ============================================================================

test "viewport manager initialization" {
    var manager = ViewportManager.init(testing.allocator);
    defer manager.deinit();

    try testing.expect(manager.current_viewport.start == 0);
    try testing.expect(manager.current_viewport.end == 0);
    try testing.expect(manager.visible_boundaries.items.len == 0);
}

test "viewport update and boundary detection" {
    var manager = ViewportManager.init(testing.allocator);
    defer manager.deinit();

    const boundaries = try createMockBoundaries(testing.allocator, 5);
    defer testing.allocator.free(boundaries);

    const viewport = Span.init(50, 200);

    try manager.updateViewport(viewport, boundaries);

    try testing.expect(manager.current_viewport.start == viewport.start);
    try testing.expect(manager.current_viewport.end == viewport.end);

    const visible = manager.getVisibleBoundaries();
    try testing.expect(visible.len > 0);

    // All visible boundaries should overlap with viewport
    for (visible) |boundary| {
        try testing.expect(boundary.span.overlaps(viewport));
    }
}

test "parsing priority queue" {
    var manager = ViewportManager.init(testing.allocator);
    defer manager.deinit();

    const boundaries = try createMockBoundaries(testing.allocator, 3);
    defer testing.allocator.free(boundaries);

    const viewport = Span.init(0, 100);
    try manager.updateViewport(viewport, boundaries);

    // Should have boundaries queued for parsing
    const next_boundary = manager.getNextBoundaryToParse();
    try testing.expect(next_boundary != null);
}

test "edit recording and prioritization" {
    var manager = ViewportManager.init(testing.allocator);
    defer manager.deinit();

    const edit_span = Span.init(50, 75);

    try manager.recordEdit(edit_span);

    // Edit should affect boundary prioritization
    const boundaries = try createMockBoundaries(testing.allocator, 2);
    defer testing.allocator.free(boundaries);

    const viewport = Span.init(0, 100);
    try manager.updateViewport(viewport, boundaries);

    // Recently edited boundaries should have higher priority
    const next_boundary = manager.getNextBoundaryToParse();
    try testing.expect(next_boundary != null);
}

test "viewport expansion for smooth scrolling" {
    var manager = ViewportManager.init(testing.allocator);
    defer manager.deinit();

    manager.current_viewport = Span.init(100, 200);

    const expanded = manager.getExpandedViewport(0.5); // 50% expansion

    try testing.expect(expanded.start < manager.current_viewport.start);
    try testing.expect(expanded.end > manager.current_viewport.end);
    try testing.expect(expanded.len() > manager.current_viewport.len());
}

test "predictive boundary detection" {
    var manager = ViewportManager.init(testing.allocator);
    defer manager.deinit();

    const boundaries = try createMockBoundaries(testing.allocator, 10);
    defer testing.allocator.free(boundaries);

    manager.current_viewport = Span.init(100, 200);

    const predicted = manager.getPredictiveBoundaries(boundaries, 3);
    defer testing.allocator.free(predicted);

    try testing.expect(predicted.len <= 3);
}

test "viewport update performance" {
    var manager = ViewportManager.init(testing.allocator);
    defer manager.deinit();

    const boundaries = try createMockBoundaries(testing.allocator, 100);
    defer testing.allocator.free(boundaries);

    const viewport = Span.init(500, 1500);

    const start = std.time.nanoTimestamp();
    try manager.updateViewport(viewport, boundaries);
    const elapsed = std.time.nanoTimestamp() - start;

    // Target: <1ms for viewport updates
    const elapsed_ms = @as(f64, @floatFromInt(elapsed)) / 1_000_000.0;
    try testing.expect(elapsed_ms < 1.0);

    const stats = manager.getStats();
    try testing.expect(stats.viewport_updates == 1);
}

// ============================================================================
// BoundaryCache Tests
// ============================================================================

test "cache initialization" {
    var cache = try BoundaryCache.init(testing.allocator, 100);
    defer cache.deinit();

    try testing.expect(cache.max_capacity == 100);
    try testing.expect(cache.generation == 0);

    const stats = cache.getStats();
    try testing.expect(stats.current_size == 0);
    try testing.expect(stats.hits == 0);
    try testing.expect(stats.misses == 0);
}

test "cache put and get operations" {
    var cache = try BoundaryCache.init(testing.allocator, 10);
    defer cache.deinit();

    const span = Span.init(0, 100);
    const facts = try createMockFacts(testing.allocator, 5);
    defer testing.allocator.free(facts);

    // Put facts in cache
    try cache.put(span, facts);

    // Get facts from cache
    const cached_facts = try cache.get(span);
    try testing.expect(cached_facts != null);
    defer if (cached_facts) |cf| testing.allocator.free(cf);

    if (cached_facts) |cf| {
        try testing.expect(cf.len == facts.len);
    }

    const stats = cache.getStats();
    try testing.expect(stats.hits == 1);
    try testing.expect(stats.current_size == 1);
}

test "cache miss handling" {
    var cache = try BoundaryCache.init(testing.allocator, 10);
    defer cache.deinit();

    const span = Span.init(0, 100);

    // Try to get non-existent entry
    const result = try cache.get(span);
    try testing.expect(result == null);

    const stats = cache.getStats();
    try testing.expect(stats.misses == 1);
    try testing.expect(stats.hits == 0);
}

test "cache LRU eviction" {
    var cache = try BoundaryCache.init(testing.allocator, 2); // Small cache
    defer cache.deinit();

    const facts = try createMockFacts(testing.allocator, 3);
    defer testing.allocator.free(facts);

    // Fill cache to capacity
    try cache.put(Span.init(0, 100), facts);
    try cache.put(Span.init(100, 200), facts);

    // Access first entry to make it recently used
    _ = try cache.get(Span.init(0, 100));

    // Add third entry, should evict second entry
    try cache.put(Span.init(200, 300), facts);

    // Second entry should be evicted
    const result = try cache.get(Span.init(100, 200));
    try testing.expect(result == null);

    // First and third should still be cached
    const first = try cache.get(Span.init(0, 100));
    try testing.expect(first != null);
    defer if (first) |f| testing.allocator.free(f);

    const third = try cache.get(Span.init(200, 300));
    try testing.expect(third != null);
    defer if (third) |t| testing.allocator.free(t);
}

test "cache invalidation" {
    var cache = try BoundaryCache.init(testing.allocator, 10);
    defer cache.deinit();

    const span = Span.init(0, 100);
    const facts = try createMockFacts(testing.allocator, 3);
    defer testing.allocator.free(facts);

    // Put and verify cached
    try cache.put(span, facts);
    const cached = try cache.get(span);
    try testing.expect(cached != null);
    defer if (cached) |c| testing.allocator.free(c);

    // Invalidate
    const old_facts = cache.invalidate(span);
    try testing.expect(old_facts != null);
    defer if (old_facts) |of| testing.allocator.free(of);

    // Should no longer be cached
    const after_invalidation = try cache.get(span);
    try testing.expect(after_invalidation == null);
}

test "cache overlapping invalidation" {
    var cache = try BoundaryCache.init(testing.allocator, 10);
    defer cache.deinit();

    const facts = try createMockFacts(testing.allocator, 2);
    defer testing.allocator.free(facts);

    // Cache facts for overlapping spans
    try cache.put(Span.init(0, 100), facts);
    try cache.put(Span.init(50, 150), facts);
    try cache.put(Span.init(200, 300), facts); // Non-overlapping

    // Invalidate overlapping spans
    try cache.invalidateOverlapping(Span.init(75, 125));

    // First two should be invalidated
    const first = try cache.get(Span.init(0, 100));
    try testing.expect(first == null);

    const second = try cache.get(Span.init(50, 150));
    try testing.expect(second == null);

    // Third should remain
    const third = try cache.get(Span.init(200, 300));
    try testing.expect(third != null);
    defer if (third) |t| testing.allocator.free(t);
}

test "cache performance targets" {
    var cache = try BoundaryCache.init(testing.allocator, 1000);
    defer cache.deinit();

    const facts = try createMockFacts(testing.allocator, 10);
    defer testing.allocator.free(facts);

    // Perform many cache operations
    const operation_count = 1000;

    const start = std.time.nanoTimestamp();

    for (0..operation_count) |i| {
        const span = Span.init(i * 10, (i + 1) * 10);

        // Put
        try cache.put(span, facts);

        // Get
        const result = try cache.get(span);
        defer if (result) |r| testing.allocator.free(r);
    }

    const elapsed = std.time.nanoTimestamp() - start;
    const avg_operation_time = @as(f64, @floatFromInt(elapsed)) / @as(f64, @floatFromInt(operation_count * 2)); // put + get

    // Target: <1000ns per operation
    try testing.expect(avg_operation_time < 1000.0);

    const metrics = cache.getEfficiencyMetrics();
    try testing.expect(metrics.hit_rate > 0.0);
}

test "cache generation invalidation" {
    var cache = try BoundaryCache.init(testing.allocator, 10);
    defer cache.deinit();

    const span = Span.init(0, 100);
    const facts = try createMockFacts(testing.allocator, 3);
    defer testing.allocator.free(facts);

    // Cache with generation 0
    try cache.put(span, facts);

    // Verify cached
    const cached = try cache.get(span);
    try testing.expect(cached != null);
    defer if (cached) |c| testing.allocator.free(c);

    // Increment generation
    cache.incrementGeneration();

    // Entry should now be stale
    const after_generation = try cache.get(span);
    try testing.expect(after_generation == null);
}

// ============================================================================
// Helper Functions for Testing
// ============================================================================

fn createMockBoundaries(allocator: std.mem.Allocator, count: usize) ![]ParseBoundary {
    var boundaries = std.ArrayList(ParseBoundary).init(allocator);
    errdefer boundaries.deinit();

    for (0..count) |i| {
        try boundaries.append(createMockBoundary(
            Span.init(i * 100, (i + 1) * 100),
            .function,
        ));
    }

    return boundaries.toOwnedSlice();
}

fn createMockBoundary(span: Span, kind: BoundaryKind) ParseBoundary {
    return ParseBoundary{
        .span = span,
        .kind = kind,
        .depth = 0,
        .confidence = 0.9,
        .has_errors = false,
        .recovery_points = &.{},
    };
}

fn createMockTokens(allocator: std.mem.Allocator, count: usize) ![]Token {
    var tokens = std.ArrayList(Token).init(allocator);
    errdefer tokens.deinit();

    for (0..count) |i| {
        try tokens.append(Token{
            .span = Span.init(i * 10, (i + 1) * 10),
            .kind = .identifier,
            .text = "mock_token",
            .bracket_depth = 0,
            .flags = .{},
        });
    }

    return tokens.toOwnedSlice();
}

fn createMockFacts(allocator: std.mem.Allocator, count: usize) ![]Fact {
    var facts = std.ArrayList(Fact).init(allocator);
    errdefer facts.deinit();

    for (0..count) |i| {
        try facts.append(Fact{
            .id = @as(u32, @intCast(i + 1)),
            .subject = Span.init(i * 20, (i + 1) * 20),
            .predicate = .is_function,
            .object = Value{ .string = "mock_function" },
            .confidence = 0.95,
            .generation = 0,
        });
    }

    return facts.toOwnedSlice();
}

fn createMockAST() AST {
    // Use centralized AST infrastructure for robust, consistent testing
    const structure = ASTStructure{ .object = &.{
        .{ .name = "kind", .value = .{ .string = "function" } },
        .{ .name = "name", .value = .{ .string = "mock_function" } },
        .{ .name = "is_public", .value = .{ .boolean = true } },
        .{ .name = "return_type", .value = .{ .string = "void" } },
    } };

    return createStructuredAST(testing.allocator, structure) catch {
        // Fallback to ZON AST if structured creation fails
        return createZonAST(testing.allocator, ".{ .kind = \"function\", .name = \"mock_function\" }") catch {
            @panic("Failed to create mock AST for testing");
        };
    };
}

fn createLargeAST() AST {
    // Create AST with many nested nodes for performance testing
    const structure = ASTStructure{ .object = &.{
        .{ .name = "kind", .value = .{ .string = "large_function" } },
        .{ .name = "name", .value = .{ .string = "large_function" } },
        .{ .name = "is_public", .value = .{ .boolean = true } },
        .{ .name = "return_type", .value = .{ .string = "void" } },
        .{ .name = "children", .value = .{ .array = &[_]ASTStructure{
            .{ .object = &.{.{ .name = "child1", .value = .{ .string = "value1" } }} },
            .{ .object = &.{.{ .name = "child2", .value = .{ .string = "value2" } }} },
            .{ .object = &.{.{ .name = "child3", .value = .{ .string = "value3" } }} },
        } } },
    } };

    return createStructuredAST(testing.allocator, structure) catch {
        // Fallback for performance testing
        return createZonAST(testing.allocator,
            \\.{ 
            \\  .kind = "large_function", 
            \\  .name = "large_function",
            \\  .children = .{ "child1", "child2", "child3" }
            \\}
        ) catch @panic("Failed to create large AST for testing");
    };
}

fn createTestParser(allocator: std.mem.Allocator) !Parser {
    const grammar = Grammar.init(allocator, 0);
    // Grammar will be cleaned up by Parser.deinit()
    return Parser.init(allocator, grammar);
}

// Mock types for testing (these would be defined in separate files)
const MockAST = struct {
    root: MockASTNode,

    fn deinit(self: MockAST) void {
        _ = self;
    }
};

const MockASTNode = struct {
    kind: MockNodeKind,
    span: Span,
    name: ?[]const u8,
    children: []const MockASTNode,
    is_public: bool,
    return_type: ?[]const u8,
    is_mutable: bool,

    // Additional fields for different node types
    var_type: ?[]const u8 = null,
    const_type: ?[]const u8 = null,
    import_path: ?[]const u8 = null,
    import_alias: ?[]const u8 = null,
    field_type: ?[]const u8 = null,
    param_type: ?[]const u8 = null,
    function_name: ?[]const u8 = null,
    literal_value: ?[]const u8 = null,
    literal_type: ?[]const u8 = null,
    assignment_target: ?[]const u8 = null,
    operator: ?[]const u8 = null,
    has_else: bool = false,
    comment_text: ?[]const u8 = null,
    is_doc_comment: bool = false,
};

const MockNodeKind = enum {
    function,
    struct_declaration,
    variable_declaration,
    constant_declaration,
    import_statement,
    type_declaration,
    enum_declaration,
    field_declaration,
    parameter,
    function_call,
    identifier,
    literal,
    block,
    assignment,
    binary_expression,
    unary_expression,
    if_statement,
    while_loop,
    for_loop,
    return_statement,
    comment,
};

// Parser instances are created using createTestParser function

// Edit type is imported from incremental/edit.zig when needed
