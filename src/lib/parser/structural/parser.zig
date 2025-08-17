const std = @import("std");
const Token = @import("../lexical/mod.zig").Token;
const TokenKind = @import("../lexical/mod.zig").TokenKind;
const TokenDelta = @import("../lexical/mod.zig").TokenDelta;
const Language = @import("../lexical/mod.zig").Language;

const Span = @import("../foundation/types/span.zig").Span;
const Fact = @import("../foundation/types/fact.zig").Fact;
const FactId = @import("../foundation/types/fact.zig").FactId;
const Generation = @import("../foundation/types/fact.zig").Generation;
const Predicate = @import("../foundation/types/predicate.zig").Predicate;
const BoundaryKind = @import("../foundation/types/predicate.zig").BoundaryKind;
const FactPoolManager = @import("../foundation/collections/pools.zig").FactPoolManager;

const StateMachine = @import("state_machine.zig").StateMachine;
const ParseState = @import("state_machine.zig").ParseState;
const StateTransition = @import("state_machine.zig").StateTransition;

const BoundaryDetector = @import("boundaries.zig").BoundaryDetector;
const BoundaryHint = @import("boundaries.zig").BoundaryHint;

const ErrorRecovery = @import("recovery.zig").ErrorRecovery;
const RecoveryPoint = @import("recovery.zig").RecoveryPoint;
const ErrorRegion = @import("recovery.zig").ErrorRegion;
const ErrorKind = @import("recovery.zig").ErrorKind;
const RecoveryContext = @import("recovery.zig").RecoveryContext;

const LanguageMatchers = @import("matchers.zig").LanguageMatchers;

const StructuralConfig = @import("mod.zig").StructuralConfig;
const StructuralResult = @import("mod.zig").StructuralResult;
const StructuralDelta = @import("mod.zig").StructuralDelta;
const StructuralStats = @import("mod.zig").StructuralStats;
const StructuralTimer = @import("mod.zig").StructuralTimer;
const ParseBoundary = @import("mod.zig").ParseBoundary;

/// High-performance structural parser for Layer 1 of stratified architecture
/// 
/// Processes token streams from lexical layer to detect:
/// - Block boundaries (functions, structs, classes)
/// - Error recovery regions
/// - Structural facts for detailed parser
/// 
/// Performance targets:
/// - <1ms boundary detection for 1000 lines
/// - <100μs incremental updates
/// - <10ms error recovery
pub const StructuralParser = struct {
    /// Parser configuration
    config: StructuralConfig,
    
    /// Memory allocator
    allocator: std.mem.Allocator,
    
    /// Memory pool manager for facts
    pool_manager: *FactPoolManager,
    
    /// Parsing state machine
    state_machine: StateMachine,
    
    /// Boundary detection system
    boundary_detector: BoundaryDetector,
    
    /// Error recovery system
    error_recovery: ErrorRecovery,
    
    /// Language-specific matchers
    matchers: LanguageMatchers,
    
    /// Current generation counter
    generation: Generation,
    
    /// Next fact ID to assign
    next_fact_id: FactId,
    
    /// Performance statistics
    stats: StructuralStats,
    
    /// Currently detected boundaries
    current_boundaries: std.ArrayList(ParseBoundary),
    
    /// Current error regions
    current_errors: std.ArrayList(ErrorRegion),
    
    pub fn init(allocator: std.mem.Allocator, config: StructuralConfig) !StructuralParser {
        const pool_manager = try allocator.create(FactPoolManager);
        pool_manager.* = FactPoolManager.init(allocator);
        
        return StructuralParser{
            .config = config,
            .allocator = allocator,
            .pool_manager = pool_manager,
            .state_machine = StateMachine.init(allocator, config.language),
            .boundary_detector = BoundaryDetector.init(allocator, config.language),
            .error_recovery = ErrorRecovery.init(allocator, config.language),
            .matchers = LanguageMatchers.init(config.language),
            .generation = 0,
            .next_fact_id = 1,
            .stats = StructuralStats{},
            .current_boundaries = std.ArrayList(ParseBoundary).init(allocator),
            .current_errors = std.ArrayList(ErrorRegion).init(allocator),
        };
    }
    
    pub fn deinit(self: *StructuralParser) void {
        self.state_machine.deinit();
        self.boundary_detector.deinit();
        self.error_recovery.deinit();
        self.current_boundaries.deinit();
        self.current_errors.deinit();
        self.pool_manager.deinit();
        self.allocator.destroy(self.pool_manager);
    }
    
    /// Parse token stream and detect structural boundaries
    pub fn parse(self: *StructuralParser, tokens: []const Token) !StructuralResult {
        const timer = StructuralTimer.start();
        self.stats.total_parses += 1;
        
        // Clear previous results
        self.current_boundaries.clearRetainingCapacity();
        self.current_errors.clearRetainingCapacity();
        self.state_machine.reset();
        
        // Main parsing loop
        const success = try self.parseTokenStream(tokens);
        
        // Generate facts from detected boundaries
        const facts = try self.generateStructuralFacts();
        
        // Create result
        const processing_time = timer.elapsedNs();
        self.stats.total_time_ns += processing_time;
        
        if (success) {
            self.stats.successful_parses += 1;
        }
        
        // Check performance target
        if (!timer.checkTarget(self.config.performance_threshold_ns)) {
            std.log.warn("Structural parsing exceeded performance target: {}ms", .{timer.elapsedMs()});
        }
        
        return StructuralResult{
            .boundaries = try self.allocator.dupe(ParseBoundary, self.current_boundaries.items),
            .facts = facts,
            .error_regions = try self.allocator.dupe(ErrorRegion, self.current_errors.items),
            .processing_time_ns = processing_time,
            .success = success,
        };
    }
    
    /// Process incremental token changes
    pub fn processTokenDelta(self: *StructuralParser, delta: TokenDelta) !StructuralDelta {
        const timer = StructuralTimer.start();
        
        // Simple approach: re-parse affected range
        // TODO: Optimize with true incremental parsing
        
        var structural_delta = StructuralDelta.init(self.allocator);
        structural_delta.generation = delta.generation;
        structural_delta.affected_range = delta.affected_range;
        
        // For now, mark all facts in affected range as removed
        // In a full implementation, we'd be smarter about this
        const removed_facts = try self.findFactsInRange(delta.affected_range);
        structural_delta.removed_facts = removed_facts;
        
        // Generate new facts for the added tokens
        if (delta.added.len > 0) {
            const new_facts = try self.generateFactsForTokens(delta.added);
            structural_delta.added_facts = new_facts;
        }
        
        self.stats.total_time_ns += timer.elapsedNs();
        self.stats.incremental_updates += 1;
        
        return structural_delta;
    }
    
    /// Get current parsing statistics
    pub fn getStats(self: StructuralParser) StructuralStats {
        return self.stats;
    }
    
    /// Reset statistics
    pub fn resetStats(self: *StructuralParser) void {
        self.stats.reset();
    }
    
    // ========================================================================
    // Private Implementation
    // ========================================================================
    
    /// Main token stream parsing logic
    fn parseTokenStream(self: *StructuralParser, tokens: []const Token) !bool {
        var success = true;
        var i: usize = 0;
        
        while (i < tokens.len) {
            const token = tokens[i];
            
            // Update statistics
            self.stats.tokens_processed += 1;
            
            // Process token through state machine
            const transition = self.state_machine.processToken(token);
            
            // Handle boundary detection
            if (transition.boundary_detected) {
                if (try self.processBoundaryTransition(tokens, i, transition)) |boundary| {
                    try self.current_boundaries.append(boundary);
                    self.stats.boundaries_detected += 1;
                    
                    // Skip to end of boundary if found
                    if (boundary.span.end > token.span.start) {
                        i = self.findTokenIndexAtPosition(tokens, boundary.span.end) orelse i + 1;
                        continue;
                    }
                }
            }
            
            // Handle error transitions
            if (transition.is_error) {
                if (try self.processErrorTransition(tokens, i)) |error_region| {
                    try self.current_errors.append(error_region);
                    self.stats.error_regions_found += 1;
                    success = false;
                    
                    // Skip to recovery point
                    if (error_region.recovery_points.len > 0) {
                        const recovery_idx = error_region.recovery_points[0].token_idx;
                        i = recovery_idx;
                        continue;
                    }
                }
            }
            
            i += 1;
        }
        
        return success;
    }
    
    /// Process a boundary transition from state machine
    fn processBoundaryTransition(
        self: *StructuralParser,
        tokens: []const Token,
        token_idx: usize,
        transition: StateTransition,
    ) !?ParseBoundary {
        if (token_idx >= tokens.len) return null;
        
        const token = tokens[token_idx];
        const boundary_kind = transition.new_state.toBoundaryKind() orelse return null;
        
        // Use boundary detector to find full boundary
        if (try self.boundary_detector.detectBoundaryAtPosition(tokens, token_idx)) |hint| {
            var boundary = ParseBoundary.init(hint.span, hint.kind, hint.depth);
            boundary = boundary.withConfidence(hint.confidence * transition.confidence);
            
            // Add metadata
            if (hint.metadata.is_foldable) {
                // Could add folding fact here
            }
            
            return boundary;
        }
        
        // Fallback: create minimal boundary from token
        const boundary = ParseBoundary.init(token.span, boundary_kind, token.bracket_depth);
        return boundary.withConfidence(transition.confidence);
    }
    
    /// Process an error transition from state machine
    fn processErrorTransition(
        self: *StructuralParser,
        tokens: []const Token,
        token_idx: usize,
    ) !?ErrorRegion {
        if (token_idx >= tokens.len) return null;
        
        const context = self.getRecoveryContext();
        
        // Create error region
        const error_region = try self.error_recovery.createErrorRegion(
            tokens,
            token_idx,
            null, // End will be determined by recovery
            .unexpected_token,
            context,
        );
        
        return error_region;
    }
    
    /// Generate structural facts from detected boundaries
    fn generateStructuralFacts(self: *StructuralParser) ![]Fact {
        var facts = std.ArrayList(Fact).init(self.allocator);
        errdefer facts.deinit();
        
        // Generate facts for boundaries
        for (self.current_boundaries.items) |boundary| {
            // Boundary fact
            const boundary_fact = Fact.withValue(
                self.next_fact_id,
                boundary.span,
                Predicate{ .is_boundary = boundary.kind },
                @import("../foundation/types/predicate.zig").Value{ .string = @tagName(boundary.kind) },
                self.generation,
            );
            try facts.append(boundary_fact);
            self.next_fact_id += 1;
            
            // Foldable fact if applicable
            if (self.config.include_folding and boundary.span.len() > 20) {
                const fold_fact = Fact.simple(
                    self.next_fact_id,
                    boundary.span,
                    .is_foldable,
                    self.generation,
                );
                try facts.append(fold_fact);
                self.next_fact_id += 1;
            }
            
            // Bracket depth fact
            const depth_fact = Fact.simple(
                self.next_fact_id,
                boundary.span,
                Predicate{ .bracket_depth = boundary.depth },
                self.generation,
            );
            try facts.append(depth_fact);
            self.next_fact_id += 1;
        }
        
        // Generate facts for error regions
        for (self.current_errors.items) |error_region| {
            const error_fact = Fact.simple(
                self.next_fact_id,
                error_region.span,
                .is_error_region,
                self.generation,
            );
            try facts.append(error_fact);
            self.next_fact_id += 1;
        }
        
        self.stats.facts_generated += facts.items.len;
        return facts.toOwnedSlice();
    }
    
    /// Find facts in a given range (for incremental updates)
    fn findFactsInRange(self: *StructuralParser, range: Span) ![]FactId {
        // For now, return empty array
        // In full implementation, would query fact index
        _ = self;
        _ = range;
        return &.{};
    }
    
    /// Generate facts for specific tokens
    fn generateFactsForTokens(self: *StructuralParser, tokens: []const Token) ![]Fact {
        // Simplified: re-parse just these tokens
        const result = try self.parse(tokens);
        defer {
            self.allocator.free(result.boundaries);
            self.allocator.free(result.error_regions);
        }
        
        return result.facts;
    }
    
    /// Find token index at or near a position
    fn findTokenIndexAtPosition(self: *StructuralParser, tokens: []const Token, position: usize) ?usize {
        _ = self;
        
        for (tokens, 0..) |token, idx| {
            if (token.span.contains(position) or token.span.start >= position) {
                return idx;
            }
        }
        
        return null;
    }
    
    /// Get recovery context from current parsing state
    fn getRecoveryContext(self: *StructuralParser) RecoveryContext {
        return switch (self.state_machine.getCurrentState()) {
            .function_signature, .function_body => .function_definition,
            .struct_signature, .struct_body => .struct_definition,
            .enum_signature, .enum_body => .enum_definition,
            .block => .block_statement,
            .expression => .expression,
            else => .unknown,
        };
    }
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "structural parser initialization" {
    const config = StructuralConfig.forLanguage(.zig);
    var parser = try StructuralParser.init(testing.allocator, config);
    defer parser.deinit();
    
    try testing.expectEqual(Language.zig, parser.config.language);
    try testing.expectEqual(@as(usize, 0), parser.stats.boundaries_detected);
}

test "basic boundary detection" {
    const config = StructuralConfig.forLanguage(.zig);
    var parser = try StructuralParser.init(testing.allocator, config);
    defer parser.deinit();
    
    // Create simple function tokens
    const tokens = [_]Token{
        Token.simple(Span.init(0, 2), .keyword, "fn", 0),
        Token.simple(Span.init(3, 7), .identifier, "test", 0),
        Token.simple(Span.init(7, 8), .delimiter, "(", 1),
        Token.simple(Span.init(8, 9), .delimiter, ")", 0),
        Token.simple(Span.init(10, 11), .delimiter, "{", 1),
        Token.simple(Span.init(12, 13), .delimiter, "}", 0),
    };
    
    const result = try parser.parse(&tokens);
    defer {
        testing.allocator.free(result.boundaries);
        testing.allocator.free(result.facts);
        testing.allocator.free(result.error_regions);
    }
    
    try testing.expect(result.success);
    try testing.expect(result.boundaries.len > 0);
    try testing.expectEqual(BoundaryKind.function, result.boundaries[0].kind);
}

test "error recovery" {
    const config = StructuralConfig.forLanguage(.zig);
    var parser = try StructuralParser.init(testing.allocator, config);
    defer parser.deinit();
    
    // Create tokens with syntax error (missing closing paren)
    const tokens = [_]Token{
        Token.simple(Span.init(0, 2), .keyword, "fn", 0),
        Token.simple(Span.init(3, 7), .identifier, "test", 0),
        Token.simple(Span.init(7, 8), .delimiter, "(", 1),
        // Missing ")"
        Token.simple(Span.init(10, 11), .delimiter, "{", 1),
        Token.simple(Span.init(12, 13), .delimiter, "}", 0),
    };
    
    const result = try parser.parse(&tokens);
    defer {
        testing.allocator.free(result.boundaries);
        testing.allocator.free(result.facts);
        testing.allocator.free(result.error_regions);
    }
    
    // Should detect the error but continue parsing
    try testing.expect(result.error_regions.len > 0);
}

test "incremental updates" {
    const config = StructuralConfig.forLanguage(.zig);
    var parser = try StructuralParser.init(testing.allocator, config);
    defer parser.deinit();
    
    // Create token delta
    const added_tokens = [_]Token{
        Token.simple(Span.init(100, 102), .keyword, "fn", 0),
        Token.simple(Span.init(103, 107), .identifier, "new", 0),
    };
    
    var delta = TokenDelta.init(testing.allocator);
    defer delta.deinit(testing.allocator);
    
    delta.added = @constCast(&added_tokens);
    delta.affected_range = Span.init(100, 107);
    delta.generation = 1;
    
    var structural_delta = try parser.processTokenDelta(delta);
    defer structural_delta.deinit(testing.allocator);
    
    try testing.expectEqual(@as(Generation, 1), structural_delta.generation);
}

test "performance measurement" {
    const config = StructuralConfig.forLanguage(.zig);
    var parser = try StructuralParser.init(testing.allocator, config);
    defer parser.deinit();
    
    // Create larger token stream
    var tokens = std.ArrayList(Token).init(testing.allocator);
    defer tokens.deinit();
    
    // Add 100 simple functions
    for (0..100) |i| {
        const offset = i * 10;
        try tokens.append(Token.simple(Span.init(offset, offset + 2), .keyword, "fn", 0));
        try tokens.append(Token.simple(Span.init(offset + 3, offset + 7), .identifier, "test", 0));
        try tokens.append(Token.simple(Span.init(offset + 7, offset + 8), .delimiter, "(", 1));
        try tokens.append(Token.simple(Span.init(offset + 8, offset + 9), .delimiter, ")", 0));
        try tokens.append(Token.simple(Span.init(offset + 10, offset + 11), .delimiter, "{", 1));
        try tokens.append(Token.simple(Span.init(offset + 12, offset + 13), .delimiter, "}", 0));
    }
    
    const result = try parser.parse(tokens.items);
    defer {
        testing.allocator.free(result.boundaries);
        testing.allocator.free(result.facts);
        testing.allocator.free(result.error_regions);
    }
    
    try testing.expect(result.success);
    try testing.expectEqual(@as(usize, 100), result.boundaries.len);
    
    const stats = parser.getStats();
    try testing.expect(stats.tokensPerSecond() > 1000); // Should be fast
}