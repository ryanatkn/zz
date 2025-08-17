const std = @import("std");

// Import foundation types
const Span = @import("../foundation/types/span.zig").Span;
const Token = @import("../foundation/types/token.zig").Token;

// Import AST types
const AST = @import("../ast/mod.zig").AST;
const ASTNode = @import("../ast/mod.zig").ASTNode;

/// Handles disambiguation of ambiguous language constructs
/// Some language constructs can be interpreted in multiple ways depending on context.
/// This module provides strategies for resolving such ambiguities.
pub const Disambiguator = struct {
    /// Strategy for resolving ambiguities
    strategy: DisambiguationStrategy,
    
    /// Statistics for monitoring disambiguation effectiveness
    stats: DisambiguationStats,
    
    pub fn init() Disambiguator {
        return Disambiguator{
            .strategy = .confidence_based,
            .stats = DisambiguationStats{},
        };
    }
    
    /// Disambiguate an ambiguous construct
    pub fn disambiguate(
        self: *Disambiguator,
        alternatives: []const ParseAlternative,
        context: DisambiguationContext,
    ) ?ParseAlternative {
        self.stats.disambiguation_attempts += 1;
        
        const start_time = std.time.nanoTimestamp();
        defer {
            const elapsed = std.time.nanoTimestamp() - start_time;
            self.stats.total_disambiguation_time_ns += @intCast(elapsed);
        }
        
        if (alternatives.len == 0) return null;
        if (alternatives.len == 1) {
            self.stats.trivial_cases += 1;
            return alternatives[0];
        }
        
        const result = switch (self.strategy) {
            .confidence_based => self.disambiguateByConfidence(alternatives),
            .context_based => self.disambiguateByContext(alternatives, context),
            .hybrid => self.disambiguateHybrid(alternatives, context),
        };
        
        if (result != null) {
            self.stats.successful_disambiguations += 1;
        } else {
            self.stats.failed_disambiguations += 1;
        }
        
        return result;
    }
    
    /// Set disambiguation strategy
    pub fn setStrategy(self: *Disambiguator, strategy: DisambiguationStrategy) void {
        self.strategy = strategy;
    }
    
    /// Get disambiguation statistics
    pub fn getStats(self: Disambiguator) DisambiguationStats {
        return self.stats;
    }
    
    /// Reset statistics
    pub fn resetStats(self: *Disambiguator) void {
        self.stats = DisambiguationStats{};
    }
    
    // ========================================================================
    // Disambiguation Strategies
    // ========================================================================
    
    /// Disambiguate based purely on confidence scores
    fn disambiguateByConfidence(
        self: *Disambiguator,
        alternatives: []const ParseAlternative,
    ) ?ParseAlternative {
        _ = self;
        
        var best_alternative: ?ParseAlternative = null;
        var best_confidence: f32 = 0.0;
        
        for (alternatives) |alternative| {
            if (alternative.confidence > best_confidence) {
                best_confidence = alternative.confidence;
                best_alternative = alternative;
            }
        }
        
        return best_alternative;
    }
    
    /// Disambiguate based on surrounding context
    fn disambiguateByContext(
        self: *Disambiguator,
        alternatives: []const ParseAlternative,
        context: DisambiguationContext,
    ) ?ParseAlternative {
        // Context-based disambiguation logic
        for (alternatives) |alternative| {
            if (self.isContextCompatible(alternative, context)) {
                return alternative;
            }
        }
        
        // Fall back to confidence-based if no context match
        return self.disambiguateByConfidence(alternatives);
    }
    
    /// Hybrid approach combining confidence and context
    fn disambiguateHybrid(
        self: *Disambiguator,
        alternatives: []const ParseAlternative,
        context: DisambiguationContext,
    ) ?ParseAlternative {
        var best_alternative: ?ParseAlternative = null;
        var best_score: f32 = 0.0;
        
        for (alternatives) |alternative| {
            // Combine confidence with context compatibility
            var score = alternative.confidence;
            
            if (self.isContextCompatible(alternative, context)) {
                score *= 1.5; // Boost score for context compatibility
            }
            
            if (score > best_score) {
                best_score = score;
                best_alternative = alternative;
            }
        }
        
        return best_alternative;
    }
    
    /// Check if an alternative is compatible with the given context
    fn isContextCompatible(
        self: *Disambiguator,
        alternative: ParseAlternative,
        context: DisambiguationContext,
    ) bool {
        _ = self;
        
        // Simple context compatibility checks
        switch (context.expected_kind) {
            .expression => return alternative.kind == .expression or alternative.kind == .identifier,
            .statement => return alternative.kind == .statement or alternative.kind == .block,
            .declaration => return alternative.kind == .declaration,
            .type_reference => return alternative.kind == .type_reference or alternative.kind == .identifier,
            else => return true, // Unknown context, accept anything
        }
    }
};

/// Alternative parse results for ambiguous constructs
pub const ParseAlternative = struct {
    ast: AST,
    confidence: f32,
    kind: AlternativeKind,
    span: Span,
    
    pub fn deinit(self: ParseAlternative) void {
        self.ast.deinit();
    }
};

/// Types of parse alternatives
pub const AlternativeKind = enum {
    expression,
    statement,
    declaration,
    type_reference,
    identifier,
    literal,
    block,
    unknown,
};

/// Context for disambiguation decisions
pub const DisambiguationContext = struct {
    preceding_tokens: []const Token,
    following_tokens: []const Token,
    expected_kind: AlternativeKind,
    parent_context: ?*const DisambiguationContext,
    
    pub fn init(expected_kind: AlternativeKind) DisambiguationContext {
        return DisambiguationContext{
            .preceding_tokens = &.{},
            .following_tokens = &.{},
            .expected_kind = expected_kind,
            .parent_context = null,
        };
    }
    
    pub fn withTokens(
        self: DisambiguationContext,
        preceding: []const Token,
        following: []const Token,
    ) DisambiguationContext {
        var context = self;
        context.preceding_tokens = preceding;
        context.following_tokens = following;
        return context;
    }
    
    pub fn withParent(
        self: DisambiguationContext,
        parent: *const DisambiguationContext,
    ) DisambiguationContext {
        var context = self;
        context.parent_context = parent;
        return context;
    }
};

/// Strategy for resolving ambiguities
pub const DisambiguationStrategy = enum {
    confidence_based,  // Choose highest confidence alternative
    context_based,     // Choose based on surrounding context
    hybrid,           // Combine confidence and context
};

/// Statistics for monitoring disambiguation performance
pub const DisambiguationStats = struct {
    disambiguation_attempts: u64 = 0,
    successful_disambiguations: u64 = 0,
    failed_disambiguations: u64 = 0,
    trivial_cases: u64 = 0,
    total_disambiguation_time_ns: u64 = 0,
    
    pub fn successRate(self: DisambiguationStats) f32 {
        const total_attempts = self.disambiguation_attempts;
        if (total_attempts == 0) return 0.0;
        return @as(f32, @floatFromInt(self.successful_disambiguations)) / @as(f32, @floatFromInt(total_attempts));
    }
    
    pub fn averageDisambiguationTime(self: DisambiguationStats) f64 {
        if (self.disambiguation_attempts == 0) return 0.0;
        return @as(f64, @floatFromInt(self.total_disambiguation_time_ns)) / @as(f64, @floatFromInt(self.disambiguation_attempts));
    }
    
    pub fn format(
        self: DisambiguationStats,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        
        try writer.print("DisambiguationStats{{ attempts: {}, success_rate: {d:.1}%, avg_time: {d:.1}ns }}", .{
            self.disambiguation_attempts,
            self.successRate() * 100.0,
            self.averageDisambiguationTime(),
        });
    }
};

// ============================================================================
// Common Ambiguity Patterns
// ============================================================================

/// Common patterns that require disambiguation in programming languages
pub const AmbiguityPattern = enum {
    /// Type vs expression: `foo(bar)` could be function call or type cast
    type_vs_expression,
    
    /// Declaration vs assignment: `var x = y` vs `x = y`
    declaration_vs_assignment,
    
    /// Generic vs comparison: `x<y>z` could be generic type or comparison
    generic_vs_comparison,
    
    /// Lambda vs block: `{ ... }` could be lambda expression or block statement
    lambda_vs_block,
    
    /// Array access vs generic: `x[y]` could be array access or generic type
    array_vs_generic,
    
    /// Pointer dereference vs multiplication: `*x` could be dereference or multiplication
    pointer_vs_multiplication,
    
    /// Function pointer vs call: `func` could be function pointer or function call
    function_pointer_vs_call,
};

/// Resolver for specific ambiguity patterns
pub const PatternResolver = struct {
    /// Resolve type vs expression ambiguity
    pub fn resolveTypeVsExpression(
        alternatives: []const ParseAlternative,
        context: DisambiguationContext,
    ) ?ParseAlternative {
        // Look at preceding tokens for hints
        for (context.preceding_tokens) |token| {
            if (std.mem.eql(u8, token.text, "as") or std.mem.eql(u8, token.text, ":")) {
                // Likely a type cast or annotation
                for (alternatives) |alternative| {
                    if (alternative.kind == .type_reference) {
                        return alternative;
                    }
                }
            }
        }
        
        // Default to expression if no clear type context
        for (alternatives) |alternative| {
            if (alternative.kind == .expression) {
                return alternative;
            }
        }
        
        return null;
    }
    
    /// Resolve declaration vs assignment ambiguity
    pub fn resolveDeclarationVsAssignment(
        alternatives: []const ParseAlternative,
        context: DisambiguationContext,
    ) ?ParseAlternative {
        // Look for declaration keywords
        for (context.preceding_tokens) |token| {
            if (std.mem.eql(u8, token.text, "var") or 
                std.mem.eql(u8, token.text, "const") or
                std.mem.eql(u8, token.text, "let")) {
                // Definitely a declaration
                for (alternatives) |alternative| {
                    if (alternative.kind == .declaration) {
                        return alternative;
                    }
                }
            }
        }
        
        // Default to assignment
        for (alternatives) |alternative| {
            if (alternative.kind == .statement) {
                return alternative;
            }
        }
        
        return null;
    }
    
    /// Resolve generic vs comparison ambiguity
    pub fn resolveGenericVsComparison(
        alternatives: []const ParseAlternative,
        context: DisambiguationContext,
    ) ?ParseAlternative {
        // Look at the broader context
        if (context.expected_kind == .type_reference) {
            for (alternatives) |alternative| {
                if (alternative.kind == .type_reference) {
                    return alternative;
                }
            }
        }
        
        // Default to comparison in expression context
        for (alternatives) |alternative| {
            if (alternative.kind == .expression) {
                return alternative;
            }
        }
        
        return null;
    }
};

// ============================================================================
// Testing Utilities
// ============================================================================

pub const TestHelpers = struct {
    /// Create mock parse alternatives for testing
    pub fn createMockAlternatives(allocator: std.mem.Allocator, count: usize) ![]ParseAlternative {
        var alternatives = std.ArrayList(ParseAlternative).init(allocator);
        errdefer alternatives.deinit();
        
        for (0..count) |i| {
            const confidence = 0.5 + (@as(f32, @floatFromInt(i)) * 0.1);
            const kind = switch (i % 3) {
                0 => AlternativeKind.expression,
                1 => AlternativeKind.statement,
                2 => AlternativeKind.declaration,
                else => AlternativeKind.unknown,
            };
            
            try alternatives.append(ParseAlternative{
                .ast = createMockAST(),
                .confidence = confidence,
                .kind = kind,
                .span = Span.init(i * 10, (i + 1) * 10),
            });
        }
        
        return alternatives.toOwnedSlice();
    }
    
    /// Create mock AST for testing
    fn createMockAST() AST {
        // This would create a simple mock AST structure
        // Implementation depends on the actual AST module
        return AST{ .root = undefined }; // Placeholder
    }
    
    /// Test disambiguation performance
    pub fn testDisambiguationPerformance(allocator: std.mem.Allocator) !void {
        var disambiguator = Disambiguator.init();
        
        const alternatives = try createMockAlternatives(allocator, 5);
        defer {
            for (alternatives) |alternative| {
                alternative.deinit();
            }
            allocator.free(alternatives);
        }
        
        const context = DisambiguationContext.init(.expression);
        
        const start = std.time.nanoTimestamp();
        _ = disambiguator.disambiguate(alternatives, context);
        const elapsed = std.time.nanoTimestamp() - start;
        
        // Target: <1000ns per disambiguation
        std.debug.assert(elapsed < 1000);
    }
};