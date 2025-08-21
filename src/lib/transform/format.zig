/// Formatting transforms
///
/// Transforms for code formatting and pretty-printing.
const std = @import("std");
const Token = @import("../token/token.zig").Token;
const StreamToken = @import("../token/stream_token.zig").StreamToken;

/// Format options
pub const FormatOptions = struct {
    indent_size: u8 = 4,
    indent_style: IndentStyle = .space,
    line_width: u32 = 100,
    preserve_newlines: bool = true,
    trailing_comma: bool = false,
    sort_keys: bool = false,
};

pub const IndentStyle = enum {
    space,
    tab,
};

/// Format transform for tokens
pub const FormatTransform = struct {
    allocator: std.mem.Allocator,
    options: FormatOptions,
    output: std.ArrayList(u8),
    indent_level: u32 = 0,
    current_line_width: u32 = 0,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, options: FormatOptions) Self {
        return .{
            .allocator = allocator,
            .options = options,
            .output = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.output.deinit();
    }

    /// Transform tokens to formatted string
    pub fn transform(self: *Self, tokens: []const Token) ![]u8 {
        self.output.clearRetainingCapacity();
        self.indent_level = 0;
        self.current_line_width = 0;

        for (tokens, 0..) |token, i| {
            try self.formatToken(token, i, tokens);
        }

        return self.output.toOwnedSlice();
    }

    fn formatToken(self: *Self, token: Token, index: usize, tokens: []const Token) !void {
        switch (token.kind) {
            .left_brace, .left_bracket => {
                try self.output.append(@intFromEnum(token.kind));
                self.indent_level += 1;

                // Check if should break line
                if (self.shouldBreakAfter(token, index, tokens)) {
                    try self.newline();
                }
            },

            .right_brace, .right_bracket => {
                if (self.indent_level > 0) self.indent_level -= 1;

                // Check if should break before
                if (index > 0 and self.shouldBreakBefore(token, index, tokens)) {
                    try self.newline();
                }

                try self.output.append(@intFromEnum(token.kind));
            },

            .comma => {
                try self.output.append(',');

                // Add trailing comma if configured
                if (self.options.trailing_comma and self.isLastItem(index, tokens)) {
                    // Already added
                } else if (self.shouldBreakAfter(token, index, tokens)) {
                    try self.newline();
                } else {
                    try self.output.append(' ');
                    self.current_line_width += 1;
                }
            },

            .colon => {
                try self.output.append(':');
                try self.output.append(' ');
                self.current_line_width += 2;
            },

            .string, .number, .identifier, .keyword => {
                // Would need actual token text here
                // For now, just append placeholder
                try self.output.appendSlice("value");
                self.current_line_width += 5;
            },

            .whitespace, .newline => {
                // Skip or preserve based on options
                if (self.options.preserve_newlines and token.kind == .newline) {
                    try self.newline();
                }
            },

            else => {},
        }
    }

    fn newline(self: *Self) !void {
        try self.output.append('\n');
        try self.appendIndent();
        self.current_line_width = self.indent_level * self.options.indent_size;
    }

    fn appendIndent(self: *Self) !void {
        const indent_char: u8 = if (self.options.indent_style == .tab) '\t' else ' ';
        const indent_count = if (self.options.indent_style == .tab)
            self.indent_level
        else
            self.indent_level * self.options.indent_size;

        var i: u32 = 0;
        while (i < indent_count) : (i += 1) {
            try self.output.append(indent_char);
        }
    }

    fn shouldBreakAfter(self: *Self, token: Token, index: usize, tokens: []const Token) bool {
        _ = token;

        // Check line width
        if (self.current_line_width > self.options.line_width) {
            return true;
        }

        // Check next token
        if (index + 1 < tokens.len) {
            const next = tokens[index + 1];
            if (next.kind == .right_brace or next.kind == .right_bracket) {
                // Don't break before closing
                return false;
            }
        }

        return false;
    }

    fn shouldBreakBefore(self: *Self, token: Token, index: usize, tokens: []const Token) bool {
        _ = self;
        _ = token;

        if (index > 0) {
            const prev = tokens[index - 1];
            if (prev.kind == .left_brace or prev.kind == .left_bracket) {
                // Don't break after opening
                return false;
            }
        }

        return false;
    }

    fn isLastItem(self: *Self, index: usize, tokens: []const Token) bool {
        _ = self;

        // Check if next non-whitespace token is closing delimiter
        var i = index + 1;
        while (i < tokens.len) : (i += 1) {
            const token = tokens[i];
            switch (token.kind) {
                .whitespace, .newline, .comment => continue,
                .right_brace, .right_bracket => return true,
                else => return false,
            }
        }

        return false;
    }
};

/// Stream-based formatting transform
pub const StreamFormatTransform = struct {
    writer: std.io.AnyWriter,
    options: FormatOptions,
    state: FormatState = .{},

    const Self = @This();

    const FormatState = struct {
        indent_level: u32 = 0,
        current_line_width: u32 = 0,
        last_token: ?Token = null,
    };

    pub fn init(writer: std.io.AnyWriter, options: FormatOptions) Self {
        return .{
            .writer = writer,
            .options = options,
        };
    }

    /// Process single token (streaming)
    pub fn processToken(self: *Self, token: StreamToken) !void {
        _ = self;
        _ = token;
        // TODO: Phase 2B - Implement streaming format processing
        // Will extract token kind and format appropriately
    }

    /// Flush any pending output
    pub fn flush(self: *Self) !void {
        _ = self;
        // Flush writer if needed
    }
};
