/// Format options for stream-based formatting

const std = @import("std");

/// Options for formatting output
pub const FormatOptions = struct {
    /// Indentation style
    indent_style: IndentStyle = .spaces,
    
    /// Number of spaces/tabs per indent level
    indent_width: u8 = 4,
    
    /// Maximum line width before wrapping
    max_line_width: u32 = 80,
    
    /// Whether to include trailing commas
    trailing_commas: bool = false,
    
    /// Whether to quote keys that don't need it
    quote_keys: QuoteStyle = .as_needed,
    
    /// Whether to sort object keys
    sort_keys: bool = false,
    
    /// Compact mode (no unnecessary whitespace)
    compact: bool = false,
    
    /// Color output for terminals
    use_color: bool = false,
};

pub const IndentStyle = enum {
    spaces,
    tabs,
    none,
};

pub const QuoteStyle = enum {
    always,      // Always quote keys
    as_needed,   // Only quote when necessary
    never,       // Never quote (ZON style)
};

/// Default options for different formats
pub const json_defaults = FormatOptions{
    .indent_style = .spaces,
    .indent_width = 2,
    .quote_keys = .always,
    .trailing_commas = false,
};

pub const zon_defaults = FormatOptions{
    .indent_style = .spaces,
    .indent_width = 4,
    .quote_keys = .never,
    .trailing_commas = true,
};

pub const compact_json = FormatOptions{
    .compact = true,
    .indent_style = .none,
    .quote_keys = .always,
};