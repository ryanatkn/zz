/// Format Module - JSON formatting capabilities
/// Provides both AST-based and streaming formatters

// AST-based formatter for feature-rich formatting (key sorting, etc.)
pub const AstFormatter = @import("ast.zig").Formatter;
pub const FormatOptions = @import("ast.zig").Formatter.FormatOptions;
pub const IndentStyle = @import("ast.zig").Formatter.FormatOptions.IndentStyle;
pub const QuoteStyle = @import("ast.zig").Formatter.FormatOptions.QuoteStyle;

// Streaming formatter for high-performance formatting
pub const StreamFormatter = @import("stream.zig").Formatter;

// Default export (AST-based for backward compatibility)
pub const Formatter = AstFormatter;
