/// Format Module - JSON formatting capabilities
/// Provides both AST-based and streaming formatters

// AST-based formatter for feature-rich formatting (key sorting, etc.)
pub const AstFormatter = @import("ast.zig").JsonFormatter;
pub const FormatOptions = @import("ast.zig").JsonFormatter.JsonFormatOptions;
pub const IndentStyle = @import("ast.zig").JsonFormatter.JsonFormatOptions.IndentStyle;
pub const QuoteStyle = @import("ast.zig").JsonFormatter.JsonFormatOptions.QuoteStyle;

// Streaming formatter for high-performance formatting
pub const StreamFormatter = @import("stream.zig").JsonFormatter;

// Default export (AST-based for backward compatibility)
pub const Formatter = AstFormatter;
