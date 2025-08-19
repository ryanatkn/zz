/// Common utilities shared across all language implementations
///
/// This module provides reusable components that language-specific
/// implementations can use to avoid code duplication.

// Re-export all common utilities
pub const formatting = @import("formatting.zig");
pub const analysis = @import("analysis.zig");

// Note: patterns.zig has been removed - use char module instead:
// const char = @import("../../char/mod.zig");
// Note: tokens.zig (CommonToken) has been removed - use foundation TokenKind instead

// Convenience re-exports of commonly used types
pub const FormatBuilder = formatting.FormatBuilder;
pub const SymbolTable = analysis.SymbolTable;
