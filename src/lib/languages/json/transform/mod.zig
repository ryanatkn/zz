/// Transform Module - JSON transformation pipeline
/// AST-based transformation with streaming parser support

// Core transformation types and functions
pub const TransformResult = @import("pipeline.zig").TransformResult;
pub const Pipeline = @import("pipeline.zig").Pipeline;
pub const Transform = @import("pipeline.zig").Transform;

// Export with prefix for disambiguation at boundary
pub const JsonTransformPipeline = Pipeline;

// Main transform function
pub const transform = @import("pipeline.zig").transform;
