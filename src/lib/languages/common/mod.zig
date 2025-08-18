/// Common utilities shared across all language implementations
///
/// This module provides reusable components that language-specific
/// implementations can use to avoid code duplication.

// Re-export all common utilities
pub const tokens = @import("tokens.zig");
pub const patterns = @import("patterns.zig");
pub const formatting = @import("formatting.zig");
pub const analysis = @import("analysis.zig");

// Convenience re-exports of commonly used types
pub const CommonToken = tokens.CommonToken;
pub const Pattern = patterns.Pattern;
pub const FormatBuilder = formatting.FormatBuilder;
pub const SymbolTable = analysis.SymbolTable;
