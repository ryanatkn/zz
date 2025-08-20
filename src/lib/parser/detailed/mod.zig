const std = @import("std");

// ============================================================================
// Core Layer 2 (Detailed) Parser Components
// ============================================================================

/// Traditional recursive descent parser - now Layer 2 of stratified architecture
pub const Parser = @import("parser.zig").Parser;

/// Parse context with position tracking and error reporting
pub const ParseContext = @import("context.zig").ParseContext;

/// Parse results and errors from detailed parsing
pub const ParseResult = @import("parser.zig").ParseResult;
pub const ParseError = @import("context.zig").ParseError;

// ============================================================================
// Stratified Layer 2 Components (New)
// ============================================================================

/// AST-to-facts conversion system
pub const FactGenerator = @import("ast_to_facts.zig").FactGenerator;

/// Boundary-aware parsing within structural boundaries
pub const BoundaryParser = @import("boundary_parser.zig").BoundaryParser;

/// Viewport detection and parsing prioritization
pub const ViewportManager = @import("viewport.zig").ViewportManager;

/// LRU cache for parsed boundaries
pub const BoundaryCache = @import("cache.zig").BoundaryCache;

/// Disambiguation of ambiguous language constructs
pub const Disambiguator = @import("disambiguation.zig").Disambiguator;

// ============================================================================
// Unified Detailed Parser - The Main Interface
// ============================================================================

/// High-level detailed parser that coordinates all Layer 2 components
pub const DetailedParser = struct {
    /// Memory allocator
    allocator: std.mem.Allocator,

    /// Traditional recursive descent parser (existing implementation)
    parser: Parser,

    /// Boundary-aware parsing coordinator
    boundary_parser: BoundaryParser,

    /// Viewport management for parsing prioritization
    viewport_manager: ViewportManager,

    /// AST-to-facts conversion
    fact_generator: FactGenerator,

    /// Cache for parsed boundaries
    cache: BoundaryCache,

    /// Disambiguator for language constructs
    disambiguator: Disambiguator,

    /// Current generation counter for facts
    generation: u32,

    pub fn init(allocator: std.mem.Allocator) !DetailedParser {
        return DetailedParser{
            .allocator = allocator,
            .parser = Parser.init(allocator, @import("../../grammar/mod.zig").Grammar.default()),
            .boundary_parser = try BoundaryParser.init(allocator),
            .viewport_manager = ViewportManager.init(allocator),
            .fact_generator = FactGenerator.init(allocator),
            .cache = try BoundaryCache.init(allocator, 1024), // 1024 boundary cache
            .disambiguator = Disambiguator.init(),
            .generation = 0,
        };
    }

    pub fn deinit(self: *DetailedParser) void {
        self.parser.deinit();
        self.boundary_parser.deinit();
        self.viewport_manager.deinit();
        self.fact_generator.deinit();
        self.cache.deinit();
    }

    /// Parse all visible boundaries in the current viewport
    /// Target: <10ms for typical viewport (50 lines)
    pub fn parseViewport(self: *DetailedParser, viewport: Span, boundaries: []const ParseBoundary, tokens: []const Token) !FactStream {
        // Update viewport and get prioritized boundaries
        try self.viewport_manager.updateViewport(viewport, boundaries);

        var fact_stream = FactStream.init(self.allocator);

        // Parse visible boundaries first (highest priority)
        const visible_boundaries = self.viewport_manager.getVisibleBoundaries();
        for (visible_boundaries) |boundary| {
            const boundary_facts = try self.boundary_parser.parseBoundary(
                boundary,
                tokens,
                &self.parser,
                &self.fact_generator,
                &self.cache,
            );

            try fact_stream.processBatch(boundary_facts);
        }

        // Start predictive parsing for nearby boundaries in background
        // (This would be done asynchronously in a real implementation)
        self.startPredictiveParsing();

        return fact_stream;
    }

    /// Process an incremental edit to update only affected boundaries
    /// Target: <5ms for typical single-function edit
    pub fn processEdit(self: *DetailedParser, edit: Edit, affected_boundaries: []const ParseBoundary, tokens: []const Token) !FactDelta {
        _ = edit;
        self.generation += 1;
        self.fact_generator.setGeneration(self.generation);

        var all_new_facts = std.ArrayList(@import("../foundation/types/fact.zig").Fact).init(self.allocator);
        defer all_new_facts.deinit();

        // Process each affected boundary
        for (affected_boundaries) |boundary| {
            // Invalidate cache for this boundary
            _ = self.cache.invalidate(boundary.span);

            // Get old facts for this boundary (if any)
            if (self.cache.getOldFacts(boundary.span)) |old_facts| {
                // For now, just note that we would add removed facts
                _ = old_facts;
            }

            // Re-parse the boundary with new content
            const new_facts = try self.boundary_parser.parseBoundary(
                boundary,
                tokens,
                &self.parser,
                &self.fact_generator,
                &self.cache,
            );

            try all_new_facts.appendSlice(new_facts);
        }

        const delta = FactDelta.init(
            try all_new_facts.toOwnedSlice(),
            &[_]@import("../foundation/types/fact.zig").Fact{}, // removed facts
            &[_]@import("../foundation/types/fact.zig").Fact{}, // modified facts
        );

        return delta;
    }

    /// Get parsing statistics for performance monitoring
    pub fn getStats(self: DetailedParser) DetailedStats {
        return DetailedStats{
            .cache_hit_rate = self.cache.getHitRate(),
            .boundaries_parsed = self.boundary_parser.getBoundariesParsed(),
            .facts_generated = self.fact_generator.getFactsGenerated(),
            .total_parse_time_ns = self.boundary_parser.getTotalParseTime(),
        };
    }

    /// Reset statistics counters
    pub fn resetStats(self: *DetailedParser) void {
        self.cache.resetStats();
        self.boundary_parser.resetStats();
        self.fact_generator.resetStats();
    }

    // ========================================================================
    // Private Implementation
    // ========================================================================

    /// Start predictive parsing for boundaries near the viewport
    fn startPredictiveParsing(self: *DetailedParser) void {
        // TODO: Implement background parsing for smooth scrolling
        // This would run in a separate thread in a full implementation
        _ = self;
    }
};

// ============================================================================
// Statistics and Performance Monitoring
// ============================================================================

pub const DetailedStats = struct {
    cache_hit_rate: f32,
    boundaries_parsed: u64,
    facts_generated: u64,
    total_parse_time_ns: u64,

    pub fn averageParseTimePerBoundary(self: DetailedStats) f64 {
        if (self.boundaries_parsed == 0) return 0.0;
        return @as(f64, @floatFromInt(self.total_parse_time_ns)) / @as(f64, @floatFromInt(self.boundaries_parsed));
    }

    pub fn format(
        self: DetailedStats,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.print("DetailedStats{{ cache_hit_rate: {d:.1}%, boundaries_parsed: {}, facts_generated: {}, avg_parse_time: {d:.1}μs }}", .{
            self.cache_hit_rate * 100.0,
            self.boundaries_parsed,
            self.facts_generated,
            self.averageParseTimePerBoundary() / 1000.0,
        });
    }
};

// ============================================================================
// Re-exports for convenience
// ============================================================================

// Foundation types needed by detailed parser
pub const Span = @import("../foundation/types/span.zig").Span;
pub const Fact = @import("../foundation/types/fact.zig").Fact;
pub const Token = @import("../foundation/types/token.zig").Token;
pub const ParseBoundary = @import("../structural/mod.zig").ParseBoundary;

// Collections for fact management
pub const FactStream = @import("../foundation/collections/mod.zig").FactStream;
pub const FactDelta = @import("../foundation/collections/mod.zig").FactDelta;

// Incremental parsing types
pub const Edit = @import("../incremental/edit.zig").Edit;

// Error types
pub const DetailedError = error{
    OutOfMemory,
    BoundaryNotFound,
    CacheFailure,
    ParseFailure,
    FactGenerationFailure,
};
