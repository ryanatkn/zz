/// Transform module - Bidirectional transformation pipeline system
/// Provides infrastructure for composable, reversible transforms

pub const types = @import("types.zig");
pub const transform = @import("transform.zig");
pub const pipeline_simple = @import("pipeline_simple.zig");

// Re-export key types for convenience
pub const Transform = transform.Transform;
pub const Context = transform.Context;
pub const SimplePipeline = pipeline_simple.SimplePipeline;

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