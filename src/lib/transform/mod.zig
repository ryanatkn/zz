/// Transform module - PURE RE-EXPORTS ONLY
///
/// Pipeline infrastructure for progressive data enrichment.
/// This module contains NO implementations, only re-exports.

// Infrastructure components
pub const pipeline = @import("pipeline.zig");
pub const format = @import("format.zig");
pub const extract = @import("extract.zig");
pub const optimize = @import("optimize.zig");

// Convenience re-exports for common types
pub const Transform = pipeline.Transform;
pub const Pipeline = pipeline.Pipeline;
pub const PipelineStats = pipeline.PipelineStats;
pub const TokenToFactTransform = pipeline.TokenToFactTransform;
pub const ASTToFactTransform = pipeline.ASTToFactTransform;

pub const FormatOptions = format.FormatOptions;
pub const IndentStyle = format.IndentStyle;
pub const FormatTransform = format.FormatTransform;
pub const StreamFormatTransform = format.StreamFormatTransform;

pub const ExtractOptions = extract.ExtractOptions;
pub const SignatureExtractor = extract.SignatureExtractor;
pub const TypeExtractor = extract.TypeExtractor;
pub const FactExtractor = extract.FactExtractor;

pub const OptimizeOptions = optimize.OptimizeOptions;
pub const TokenOptimizer = optimize.TokenOptimizer;
pub const ASTOptimizer = optimize.ASTOptimizer;
pub const Minifier = optimize.Minifier;
