/// Format Module - ZON formatting capabilities
/// Provides both AST-based and streaming formatters

// AST-based formatter (main formatter)
pub const Formatter = @import("core.zig").ZonFormatter;
pub const FormatOptions = @import("core.zig").FormatOptions;

// Streaming formatter for high-performance formatting
pub const StreamFormatter = @import("stream.zig").ZonFormatter;
