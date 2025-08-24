/// Utils Module - ZON utility functions and common imports
/// Shared utilities used across ZON implementation

// Common imports and types
pub const common = @import("common.zig");
pub const memory = @import("memory.zig");
pub const patterns = @import("patterns.zig");
pub const helpers = @import("helpers.zig");
pub const validator = @import("validator.zig");

// Re-export frequently used items
pub const ManagedConfig = memory.ManagedConfig;
pub const ValidationError = validator.ValidationError;
