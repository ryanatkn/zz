const std = @import("std");
const FormatOptions = @import("../interface.zig").FormatOptions;

/// Common formatting utilities shared across languages
/// 
/// This module provides building blocks for consistent code formatting
/// across all supported languages.
pub const FormatBuilder = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8),
    options: FormatOptions,
    current_indent: u32,
    line_start: bool,
    
    pub fn init(allocator: std.mem.Allocator, options: FormatOptions) FormatBuilder {
        return FormatBuilder{
            .allocator = allocator,
            .buffer = std.ArrayList(u8).init(allocator),
            .options = options,
            .current_indent = 0,
            .line_start = true,
        };
    }
    
    pub fn deinit(self: *FormatBuilder) void {
        self.buffer.deinit();
    }
    
    /// Get the formatted output
    pub fn toOwnedSlice(self: *FormatBuilder) ![]u8 {
        return self.buffer.toOwnedSlice();
    }
    
    /// Add indentation if at start of line
    pub fn addIndentIfNeeded(self: *FormatBuilder) !void {
        if (self.line_start) {
            try self.addIndent();
            self.line_start = false;
        }
    }
    
    /// Add current indentation
    pub fn addIndent(self: *FormatBuilder) !void {
        const total_indent = self.current_indent * self.options.indent_size;
        
        switch (self.options.indent_style) {
            .space => {
                try self.buffer.appendNTimes(' ', total_indent);
            },
            .tab => {
                try self.buffer.appendNTimes('\t', self.current_indent);
            },
        }
    }
    
    /// Increase indentation level
    pub fn indent(self: *FormatBuilder) void {
        self.current_indent += 1;
    }
    
    /// Decrease indentation level
    pub fn dedent(self: *FormatBuilder) void {
        if (self.current_indent > 0) {
            self.current_indent -= 1;
        }
    }
    
    /// Add text without any formatting
    pub fn addRaw(self: *FormatBuilder, text: []const u8) !void {
        try self.addIndentIfNeeded();
        try self.buffer.appendSlice(text);
    }
    
    /// Add text with potential line wrapping
    pub fn addText(self: *FormatBuilder, text: []const u8) !void {
        try self.addIndentIfNeeded();
        
        // Check if adding this text would exceed line width
        if (self.shouldWrapLine(text.len)) {
            try self.newline();
            try self.addIndent();
        }
        
        try self.buffer.appendSlice(text);
    }
    
    /// Add a single character
    pub fn addChar(self: *FormatBuilder, char: u8) !void {
        try self.addIndentIfNeeded();
        try self.buffer.append(char);
    }
    
    /// Add a space (unless already at line start)
    pub fn addSpace(self: *FormatBuilder) !void {
        if (!self.line_start) {
            try self.buffer.append(' ');
        }
    }
    
    /// Add spaces if enabled (for optional spacing)
    pub fn addOptionalSpace(self: *FormatBuilder) !void {
        // For now, always add space. Could be made configurable
        try self.addSpace();
    }
    
    /// Add a newline
    pub fn newline(self: *FormatBuilder) !void {
        try self.buffer.append('\n');
        self.line_start = true;
    }
    
    /// Add newline only if not already at line start
    pub fn ensureNewline(self: *FormatBuilder) !void {
        if (!self.line_start) {
            try self.newline();
        }
    }
    
    /// Add multiple newlines (for blank lines)
    pub fn addBlankLine(self: *FormatBuilder) !void {
        try self.ensureNewline();
        try self.newline();
    }
    
    /// Add a comma with optional trailing comma handling
    pub fn addComma(self: *FormatBuilder, is_last: bool) !void {
        if (!is_last or self.options.trailing_comma) {
            try self.addChar(',');
        }
    }
    
    /// Add opening brace with newline style
    pub fn addOpenBrace(self: *FormatBuilder, same_line: bool) !void {
        if (same_line) {
            try self.addSpace();
        } else {
            try self.newline();
            try self.addIndent();
        }
        try self.addChar('{');
        try self.newline();
        self.indent();
    }
    
    /// Add closing brace
    pub fn addCloseBrace(self: *FormatBuilder) !void {
        self.dedent();
        try self.addIndent();
        try self.addChar('}');
    }
    
    /// Add opening parenthesis
    pub fn addOpenParen(self: *FormatBuilder) !void {
        try self.addChar('(');
    }
    
    /// Add closing parenthesis
    pub fn addCloseParen(self: *FormatBuilder) !void {
        try self.addChar(')');
    }
    
    /// Add opening bracket
    pub fn addOpenBracket(self: *FormatBuilder) !void {
        try self.addChar('[');
    }
    
    /// Add closing bracket
    pub fn addCloseBracket(self: *FormatBuilder) !void {
        try self.addChar(']');
    }
    
    /// Check if we should wrap to next line
    pub fn shouldWrapLine(self: *FormatBuilder, additional_length: u32) bool {
        const current_line_length = self.getCurrentLineLength();
        return current_line_length + additional_length > self.options.line_width;
    }
    
    /// Get length of current line
    pub fn getCurrentLineLength(self: *FormatBuilder) u32 {
        const content = self.buffer.items;
        var line_start_pos: usize = 0;
        
        // Find the last newline
        for (content, 0..) |char, i| {
            if (char == '\n') {
                line_start_pos = i + 1;
            }
        }
        
        return @intCast(content.len - line_start_pos);
    }
    
    /// Format a list of items with separators
    pub fn formatList(
        self: *FormatBuilder,
        items: []const []const u8,
        separator: []const u8,
        multiline: bool,
    ) !void {
        for (items, 0..) |item, i| {
            if (multiline) {
                try self.addIndent();
            }
            
            try self.addText(item);
            
            if (i < items.len - 1) {
                try self.addText(separator);
                if (multiline) {
                    try self.newline();
                } else {
                    try self.addSpace();
                }
            }
        }
    }
    
    /// Format key-value pairs (for objects, structs)
    pub fn formatKeyValue(
        self: *FormatBuilder,
        key: []const u8,
        value: []const u8,
        separator: []const u8,
    ) !void {
        try self.addText(key);
        try self.addText(separator);
        try self.addOptionalSpace();
        try self.addText(value);
    }
};

/// Utility functions for common formatting tasks

/// Escape string for output (basic escaping)
pub fn escapeString(allocator: std.mem.Allocator, input: []const u8, quote_char: u8) ![]u8 {
    var escaped = std.ArrayList(u8).init(allocator);
    defer escaped.deinit();
    
    try escaped.append(quote_char);
    
    for (input) |char| {
        switch (char) {
            '\n' => try escaped.appendSlice("\\n"),
            '\r' => try escaped.appendSlice("\\r"),
            '\t' => try escaped.appendSlice("\\t"),
            '\\' => try escaped.appendSlice("\\\\"),
            '"' => {
                if (quote_char == '"') {
                    try escaped.appendSlice("\\\"");
                } else {
                    try escaped.append(char);
                }
            },
            '\'' => {
                if (quote_char == '\'') {
                    try escaped.appendSlice("\\'");
                } else {
                    try escaped.append(char);
                }
            },
            else => try escaped.append(char),
        }
    }
    
    try escaped.append(quote_char);
    return escaped.toOwnedSlice();
}

/// Check if string needs quoting (contains special characters)
pub fn needsQuoting(input: []const u8) bool {
    for (input) |char| {
        switch (char) {
            'a'...'z', 'A'...'Z', '0'...'9', '_' => {},
            else => return true,
        }
    }
    return false;
}

/// Format number with appropriate precision
pub fn formatNumber(allocator: std.mem.Allocator, value: f64) ![]u8 {
    // Simple number formatting - could be enhanced
    if (value == @trunc(value) and value >= std.math.minInt(i64) and value <= std.math.maxInt(i64)) {
        // Integer
        return std.fmt.allocPrint(allocator, "{d}", .{@as(i64, @intFromFloat(value))});
    } else {
        // Float
        return std.fmt.allocPrint(allocator, "{d}", .{value});
    }
}

/// Common formatting configurations
pub const FormattingProfiles = struct {
    pub const compact = FormatOptions{
        .indent_size = 2,
        .line_width = 80,
        .preserve_newlines = false,
        .trailing_comma = false,
    };
    
    pub const standard = FormatOptions{
        .indent_size = 4,
        .line_width = 100,
        .preserve_newlines = true,
        .trailing_comma = false,
    };
    
    pub const verbose = FormatOptions{
        .indent_size = 4,
        .line_width = 120,
        .preserve_newlines = true,
        .trailing_comma = true,
    };
};