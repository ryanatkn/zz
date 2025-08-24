/// ZON Parser - Core parsing functionality
///
/// This module provides the main ZON parsing interface

// Re-export core parser
pub const Parser = @import("core.zig").ZonParser;

// Compatibility alias
pub const ZonParser = Parser;

// Re-export commonly used types and functions
pub const ParseError = @import("core.zig").ParseError;
pub const ZonParseError = @import("core.zig").ZonParseError;
pub const ParserOptions = @import("core.zig").ParserOptions;
