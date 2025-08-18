const std = @import("std");

// ============================================================================
// Legacy Parser Types (moved to detailed layer)
// ============================================================================

/// Traditional recursive descent parser - now in detailed layer
pub const Parser = @import("detailed/parser.zig").Parser;

/// Parse context with position tracking and error reporting
pub const ParseContext = @import("detailed/context.zig").ParseContext;

// ============================================================================
// Parse Results and Errors
// ============================================================================

pub const ParseResult = @import("detailed/parser.zig").ParseResult;
pub const ParseError = @import("detailed/context.zig").ParseError;

// ============================================================================
// Stratified Parser Architecture - Phase 5 Complete
// ============================================================================

/// Foundation types for fact-based parsing
pub const Foundation = @import("foundation/mod.zig");

/// Lexical layer - Layer 0 (<0.1ms viewport tokenization)
pub const Lexical = @import("lexical/mod.zig");

/// Structural layer - Layer 1 (<1ms boundary detection)
pub const Structural = @import("structural/mod.zig");

/// Detailed layer - Layer 2 (<10ms viewport parsing) - PHASE 5 COMPLETE
pub const Detailed = @import("detailed/mod.zig");

// ============================================================================
// Convenience Re-exports for Stratified Parser
// ============================================================================

/// High-performance structural parser for boundary detection
pub const StructuralParser = @import("structural/mod.zig").StructuralParser;

/// Streaming lexer for viewport tokenization
pub const StreamingLexer = @import("lexical/mod.zig").StreamingLexer;

/// Complete detailed parser with viewport awareness and caching
pub const DetailedParser = @import("detailed/mod.zig").DetailedParser;

/// Core fact and span types
pub const Fact = @import("foundation/types/fact.zig").Fact;
pub const Span = @import("foundation/types/span.zig").Span;
pub const Token = @import("foundation/types/token.zig").Token;

// ============================================================================
// Additional Re-exports for Complete Stratified Architecture
// ============================================================================

/// AST-to-facts conversion system
pub const FactGenerator = @import("detailed/ast_to_facts.zig").FactGenerator;

/// Boundary-aware parsing within structural boundaries
pub const BoundaryParser = @import("detailed/boundary_parser.zig").BoundaryParser;

/// Viewport detection and parsing prioritization
pub const ViewportManager = @import("detailed/viewport.zig").ViewportManager;

/// LRU cache for parsed boundaries
pub const BoundaryCache = @import("detailed/cache.zig").BoundaryCache;

// ============================================================================
// Re-export AST types when they exist
// ============================================================================

// AST types are now available
pub const AST = @import("../ast/mod.zig").AST;
pub const Node = @import("../ast/mod.zig").Node;
pub const Visitor = @import("../ast/mod.zig").Visitor;

// ============================================================================
// Complete Stratified Parser API Summary
// ============================================================================

// The complete three-layer stratified parser architecture:
//
// Layer 0 (Lexical): StreamingLexer provides <0.1ms viewport tokenization
// Layer 1 (Structural): StructuralParser provides <1ms boundary detection
// Layer 2 (Detailed): DetailedParser provides <10ms viewport parsing
//
// Key features:
// - Fact-based intermediate representation
// - Viewport-aware parsing prioritization
// - LRU caching for boundary results
// - Incremental updates with confidence scoring
// - Predictive parsing for smooth user experience
//
// Usage:
// ```zig
// const parser = @import("lib/parser/mod.zig");
//
// // Initialize stratified parser
// var lexer = try parser.StreamingLexer.init(allocator, config);
// var structural = try parser.StructuralParser.init(allocator, config);
// var detailed = try parser.DetailedParser.init(allocator);
//
// // Three-layer parsing
// const tokens = try lexer.tokenize(source);
// const boundaries = try structural.parse(tokens);
// const facts = try detailed.parseViewport(viewport, boundaries, tokens);
// ```
