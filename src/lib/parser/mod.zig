/// Parser module - PURE RE-EXPORTS ONLY
///
/// Optional parser infrastructure that consumes tokens to produce AST.
/// This module contains NO implementations, only re-exports.

// Infrastructure components
pub const interface = @import("interface.zig");
pub const recursive = @import("recursive.zig");
pub const structural = @import("structural.zig");
pub const recovery = @import("recovery.zig");
pub const viewport = @import("viewport.zig");
pub const cache = @import("cache.zig");
pub const context = @import("context.zig");

// Parser pattern modules removed - unused and overcomplicated
// Direct parsing in each language module works better

// Convenience re-exports for common types
pub const ParserInterface = interface.ParserInterface;
pub const createInterface = interface.createInterface;

pub const RecursiveParser = recursive.RecursiveParser;
pub const ParseError = recursive.ParseError;
pub const ParseErrorKind = recursive.ParseErrorKind;
pub const Combinators = recursive.Combinators;

pub const Boundary = structural.Boundary;
pub const BoundaryKind = structural.BoundaryKind;
pub const StructuralAnalyzer = structural.StructuralAnalyzer;

pub const RecoveryStrategy = recovery.RecoveryStrategy;
pub const RecoveryContext = recovery.RecoveryContext;
pub const ErrorRecovery = recovery.ErrorRecovery;

pub const Viewport = viewport.Viewport;
pub const ViewportManager = viewport.ViewportManager;
pub const PredictiveParser = viewport.PredictiveParser;

pub const BoundaryCache = cache.BoundaryCache;
pub const CacheEntry = cache.CacheEntry;
pub const hashTokens = cache.hashTokens;

pub const ParseContext = context.ParseContext;
pub const ParseWarning = context.ParseWarning;
pub const ParseStats = context.ParseStats;
