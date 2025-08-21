/// Transform module - Bidirectional transformation pipeline system
/// Provides infrastructure for composable, reversible transforms
pub const types = @import("types.zig");
pub const transform = @import("transform.zig");
pub const pipeline_simple = @import("pipeline_simple.zig");

// Stage interfaces
pub const stages = struct {
    pub const lexical = @import("stages/lexical.zig");
    pub const syntactic = @import("stages/syntactic.zig");
};

// Pipeline implementations
pub const pipelines = struct {
    pub const lex_parse = @import("pipelines/lex_parse.zig");
    pub const format = @import("pipelines/format.zig");
};

// Re-export key types for convenience
pub const Transform = transform.Transform;
pub const Context = transform.Context;
pub const SimplePipeline = pipeline_simple.SimplePipeline;

// Re-export stage interfaces
pub const ILexicalTransform = stages.lexical.ILexicalTransform;
pub const ISyntacticTransform = stages.syntactic.ISyntacticTransform;
pub const LexicalTransform = stages.lexical.LexicalTransform;
pub const SyntacticTransform = stages.syntactic.SyntacticTransform;

// Re-export pipelines
pub const LexParsePipeline = pipelines.lex_parse.LexParsePipeline;
pub const StreamingLexParsePipeline = pipelines.lex_parse.StreamingLexParsePipeline;
pub const FormatPipeline = pipelines.format.FormatPipeline;
pub const PreservingFormatPipeline = pipelines.format.PreservingFormatPipeline;

// Re-export type definitions
pub const TransformResult = types.TransformResult;
pub const Diagnostic = types.Diagnostic;
pub const Span = types.Span;
pub const IOMode = types.IOMode;
pub const TransformMetadata = types.TransformMetadata;
pub const Progress = types.Progress;
pub const TransformError = types.TransformError;
pub const OptionsMap = types.OptionsMap;

// Re-export helper functions
pub const createTransform = transform.createTransform;
pub const identity = transform.identity;
