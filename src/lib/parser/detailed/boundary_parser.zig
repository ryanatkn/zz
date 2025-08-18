const std = @import("std");

// Import foundation types
const Span = @import("../foundation/types/span.zig").Span;
const Token = @import("../foundation/types/token.zig").Token;
const Fact = @import("../foundation/types/fact.zig").Fact;

// Import structural types
const ParseBoundary = @import("../structural/mod.zig").ParseBoundary;

// Import AST types
const AST = @import("../ast/mod.zig").AST;
const ASTNode = @import("../../ast/mod.zig").Node;

// Import detailed parser components
const Parser = @import("parser.zig").Parser;
const FactGenerator = @import("ast_to_facts.zig").FactGenerator;
const BoundaryCache = @import("cache.zig").BoundaryCache;

/// Boundary-aware parser that parses within specific structural boundaries
/// This is the core component that adapts the traditional recursive descent parser
/// to work within the stratified architecture
pub const BoundaryParser = struct {
    /// Memory allocator
    allocator: std.mem.Allocator,

    /// Performance statistics
    stats: BoundaryParserStats,

    pub fn init(allocator: std.mem.Allocator) !BoundaryParser {
        return BoundaryParser{
            .allocator = allocator,
            .stats = BoundaryParserStats{},
        };
    }

    pub fn deinit(self: *BoundaryParser) void {
        _ = self;
        // No cleanup needed for this simple implementation
    }

    /// Parse a single boundary using the detailed parser
    /// This is the main entry point for boundary-aware parsing
    pub fn parseBoundary(
        self: *BoundaryParser,
        boundary: ParseBoundary,
        tokens: []const Token,
        parser: *Parser,
        fact_generator: *FactGenerator,
        cache: *BoundaryCache,
    ) ![]Fact {
        const start_time = std.time.nanoTimestamp();
        defer {
            const elapsed = std.time.nanoTimestamp() - start_time;
            self.stats.total_parse_time_ns += @intCast(elapsed);
            self.stats.boundaries_parsed += 1;
        }

        // Check cache first
        if (try cache.get(boundary.span)) |cached_facts| {
            self.stats.cache_hits += 1;
            return cached_facts;
        }

        self.stats.cache_misses += 1;

        // Extract tokens for this boundary
        const boundary_tokens = try self.extractBoundaryTokens(tokens, boundary);
        defer self.allocator.free(boundary_tokens);

        // Parse the boundary using the traditional parser
        var ast = try self.parseTokensToAST(parser, boundary_tokens, boundary);
        defer ast.deinit();

        // Convert AST to facts
        const facts = try fact_generator.fromAST(ast, boundary);

        // Cache the results for future use
        try cache.put(boundary.span, facts);

        return facts;
    }

    /// Parse multiple boundaries efficiently
    pub fn parseBoundaries(
        self: *BoundaryParser,
        boundaries: []const ParseBoundary,
        tokens: []const Token,
        parser: *Parser,
        fact_generator: *FactGenerator,
        cache: *BoundaryCache,
    ) ![][]Fact {
        var results = std.ArrayList([]Fact).init(self.allocator);
        errdefer {
            for (results.items) |facts| {
                self.allocator.free(facts);
            }
            results.deinit();
        }

        for (boundaries) |boundary| {
            const facts = try self.parseBoundary(
                boundary,
                tokens,
                parser,
                fact_generator,
                cache,
            );
            try results.append(facts);
        }

        return results.toOwnedSlice();
    }

    /// Parse only boundaries that intersect with a given span (viewport)
    pub fn parseVisibleBoundaries(
        self: *BoundaryParser,
        boundaries: []const ParseBoundary,
        viewport: Span,
        tokens: []const Token,
        parser: *Parser,
        fact_generator: *FactGenerator,
        cache: *BoundaryCache,
    ) ![][]Fact {
        var visible_boundaries = std.ArrayList(ParseBoundary).init(self.allocator);
        defer visible_boundaries.deinit();

        // Filter boundaries that intersect with viewport
        for (boundaries) |boundary| {
            if (boundary.span.overlaps(viewport)) {
                try visible_boundaries.append(boundary);
            }
        }

        // Parse only the visible boundaries
        return self.parseBoundaries(
            visible_boundaries.items,
            tokens,
            parser,
            fact_generator,
            cache,
        );
    }

    /// Update a specific boundary after an edit
    pub fn updateBoundary(
        self: *BoundaryParser,
        boundary: ParseBoundary,
        tokens: []const Token,
        parser: *Parser,
        fact_generator: *FactGenerator,
        cache: *BoundaryCache,
    ) !BoundaryUpdateResult {
        // Invalidate cache for this boundary
        const old_facts = cache.invalidate(boundary.span);

        // Re-parse the boundary
        const new_facts = try self.parseBoundary(
            boundary,
            tokens,
            parser,
            fact_generator,
            cache,
        );

        return BoundaryUpdateResult{
            .old_facts = old_facts,
            .new_facts = new_facts,
            .boundary = boundary,
        };
    }

    // ========================================================================
    // Private Implementation
    // ========================================================================

    /// Extract tokens that belong to a specific boundary
    fn extractBoundaryTokens(
        self: *BoundaryParser,
        all_tokens: []const Token,
        boundary: ParseBoundary,
    ) ![]Token {
        var boundary_tokens = std.ArrayList(Token).init(self.allocator);
        errdefer boundary_tokens.deinit();

        for (all_tokens) |token| {
            if (boundary.span.contains(token.span.start)) {
                try boundary_tokens.append(token);
            } else if (token.span.start >= boundary.span.end) {
                // Tokens are ordered, so we can break early
                break;
            }
        }

        return boundary_tokens.toOwnedSlice();
    }

    /// Parse tokens to AST using the traditional parser
    fn parseTokensToAST(
        self: *BoundaryParser,
        parser: *Parser,
        tokens: []const Token,
        boundary: ParseBoundary,
    ) !AST {
        // Create a temporary input from tokens
        // This is a simplified approach - in a real implementation,
        // we would need to reconstruct the source text or adapt the parser
        // to work directly with tokens

        const source_text = try self.reconstructSourceFromTokens(tokens);
        defer self.allocator.free(source_text);

        // Parse using the traditional parser
        // We need to adapt the parser interface to accept our reconstructed source
        const parse_result = try parser.parseWithContext(source_text, .{
            .boundary = boundary,
            .tokens = tokens,
        });

        return switch (parse_result) {
            .success => |node| AST{
                .root = ASTNode{
                    .rule_name = node.rule_name,
                    .node_type = .rule,
                    .text = node.text,
                    .start_position = node.start_position,
                    .end_position = node.end_position,
                    .children = &[_]ASTNode{},
                    .attributes = null,
                    .parent = null,
                },
                .allocator = self.allocator,
                .owned_texts = &[_][]const u8{}, // No owned texts for boundary parser
            },
            .failure => error.ParseFailed,
        };
    }

    /// Reconstruct source text from tokens (simplified approach)
    fn reconstructSourceFromTokens(self: *BoundaryParser, tokens: []const Token) ![]u8 {
        if (tokens.len == 0) return try self.allocator.dupe(u8, "");

        // Calculate total length needed
        var total_len: usize = 0;
        for (tokens) |token| {
            total_len += token.text.len;
            total_len += 1; // Space between tokens
        }

        var result = std.ArrayList(u8).init(self.allocator);
        errdefer result.deinit();

        for (tokens, 0..) |token, i| {
            try result.appendSlice(token.text);
            if (i < tokens.len - 1) {
                try result.append(' ');
            }
        }

        return result.toOwnedSlice();
    }

    // ========================================================================
    // Statistics and Performance Monitoring
    // ========================================================================

    pub fn getStats(self: BoundaryParser) BoundaryParserStats {
        return self.stats;
    }

    pub fn resetStats(self: *BoundaryParser) void {
        self.stats = BoundaryParserStats{};
    }

    pub fn getBoundariesParsed(self: BoundaryParser) u64 {
        return self.stats.boundaries_parsed;
    }

    pub fn getTotalParseTime(self: BoundaryParser) u64 {
        return self.stats.total_parse_time_ns;
    }

    pub fn getCacheHitRate(self: BoundaryParser) f32 {
        const total_requests = self.stats.cache_hits + self.stats.cache_misses;
        if (total_requests == 0) return 0.0;
        return @as(f32, @floatFromInt(self.stats.cache_hits)) / @as(f32, @floatFromInt(total_requests));
    }
};

/// Result of updating a boundary after an edit
pub const BoundaryUpdateResult = struct {
    old_facts: ?[]Fact,
    new_facts: []Fact,
    boundary: ParseBoundary,

    pub fn deinit(self: BoundaryUpdateResult, allocator: std.mem.Allocator) void {
        if (self.old_facts) |old_facts| {
            allocator.free(old_facts);
        }
        allocator.free(self.new_facts);
    }
};

/// Statistics for monitoring boundary parser performance
pub const BoundaryParserStats = struct {
    boundaries_parsed: u64 = 0,
    total_parse_time_ns: u64 = 0,
    cache_hits: u64 = 0,
    cache_misses: u64 = 0,

    pub fn averageParseTime(self: BoundaryParserStats) f64 {
        if (self.boundaries_parsed == 0) return 0.0;
        return @as(f64, @floatFromInt(self.total_parse_time_ns)) / @as(f64, @floatFromInt(self.boundaries_parsed));
    }

    pub fn cacheHitRate(self: BoundaryParserStats) f32 {
        const total_requests = self.cache_hits + self.cache_misses;
        if (total_requests == 0) return 0.0;
        return @as(f32, @floatFromInt(self.cache_hits)) / @as(f32, @floatFromInt(total_requests));
    }

    pub fn format(
        self: BoundaryParserStats,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.print("BoundaryParserStats{{ parsed: {}, avg_time: {d:.1}μs, cache_hit_rate: {d:.1}% }}", .{
            self.boundaries_parsed,
            self.averageParseTime() / 1000.0,
            self.cacheHitRate() * 100.0,
        });
    }
};

// ============================================================================
// Error Handling
// ============================================================================

pub const BoundaryParserError = error{
    OutOfMemory,
    InvalidBoundary,
    ParseFailure,
    TokenExtractionFailure,
    CacheOperationFailure,
};

// ============================================================================
// Testing Utilities
// ============================================================================

pub const TestHelpers = struct {
    /// Create a mock boundary for testing
    pub fn createMockBoundary(start: usize, end: usize, kind: anytype) ParseBoundary {
        return ParseBoundary{
            .span = Span.init(start, end),
            .kind = kind,
            .depth = 0,
            .confidence = 1.0,
        };
    }

    /// Create mock tokens for testing
    pub fn createMockTokens(allocator: std.mem.Allocator, count: usize) ![]Token {
        var tokens = std.ArrayList(Token).init(allocator);
        errdefer tokens.deinit();

        for (0..count) |i| {
            try tokens.append(Token{
                .span = Span.init(i * 10, (i + 1) * 10),
                .kind = .identifier,
                .text = "mock",
                .bracket_depth = 0,
            });
        }

        return tokens.toOwnedSlice();
    }

    /// Verify boundary parser performance meets targets
    pub fn verifyPerformanceTargets(stats: BoundaryParserStats) !void {
        const avg_parse_time_us = stats.averageParseTime() / 1000.0;

        // Target: <10ms per boundary for viewport parsing
        if (avg_parse_time_us > 10_000.0) {
            std.log.warn("Boundary parsing too slow: {d:.1}μs > 10ms target", .{avg_parse_time_us});
            return error.PerformanceTargetMissed;
        }

        // Target: >95% cache hit rate
        if (stats.cacheHitRate() < 0.95) {
            std.log.warn("Cache hit rate too low: {d:.1}% < 95% target", .{stats.cacheHitRate() * 100.0});
            return error.CacheTargetMissed;
        }
    }
};
