/// ZON formatter using DirectTokenStream
/// Zero-allocation streaming formatter for Zig Object Notation

const std = @import("std");
const FormatOptions = @import("../../stream/format_options.zig").FormatOptions;
const FormatError = @import("../../stream/format.zig").FormatError;
const StreamToken = @import("../../token/mod.zig").StreamToken;
const ZonTokenKind = @import("stream_token.zig").ZonTokenKind;
const ZonToken = @import("stream_token.zig").ZonToken;
const packSpan = @import("../../span/mod.zig").packSpan;
const Span = @import("../../span/mod.zig").Span;

/// ZON formatter state machine
pub fn ZonFormatter(comptime Writer: type) type {
    return struct {
        writer: Writer,
        options: FormatOptions,
        depth: u8 = 0,
        need_comma: bool = false,
        in_struct: [256]bool = [_]bool{false} ** 256,
        
        const Self = @This();
        
        pub fn init(writer: Writer, options: FormatOptions) Self {
            return .{
                .writer = writer,
                .options = options,
            };
        }
    
    /// Write a single token with appropriate formatting
    pub fn writeToken(self: *Self, token: StreamToken) !void {
        // Only handle ZON tokens
        if (token != .zon) return FormatError.InvalidToken;
        
        const zon_token = token.zon;
        
        // Handle EOF
        if (zon_token.kind == .eof) {
            return;
        }
        
        // Write comma if needed
        if (self.needsComma(zon_token.kind)) {
            if (self.need_comma) {
                try self.writer.writeAll(",");
                if (!self.options.compact) {
                    try self.writeNewline();
                }
            }
        }
        
        // Write the token
        switch (zon_token.kind) {
            .struct_start => {
                try self.writer.writeAll(".{");
                self.depth = @min(self.depth + 1, 255);
                self.in_struct[self.depth] = true;
                self.need_comma = false;
                if (!self.options.compact) {
                    try self.writeNewline();
                }
            },
            .object_start => {
                try self.writer.writeAll("{");
                self.depth = @min(self.depth + 1, 255);
                self.in_struct[self.depth] = false;
                self.need_comma = false;
                if (!self.options.compact) {
                    try self.writeNewline();
                }
            },
            .object_end => {
                self.depth -|= 1;
                if (!self.options.compact and !self.need_comma) {
                    try self.writeIndent();
                }
                try self.writer.writeAll("}");
                self.need_comma = true;
            },
            .array_start => {
                try self.writer.writeAll("[");
                self.depth = @min(self.depth + 1, 255);
                self.need_comma = false;
                if (!self.options.compact) {
                    try self.writeNewline();
                }
            },
            .array_end => {
                self.depth -|= 1;
                if (!self.options.compact and !self.need_comma) {
                    try self.writeIndent();
                }
                try self.writer.writeAll("]");
                self.need_comma = true;
            },
            .field_name => {
                if (!self.options.compact) {
                    try self.writeIndent();
                }
                // TODO: Get actual field name from token data
                try self.writer.writeAll(".field");
                self.need_comma = false;
            },
            .identifier => {
                if (!self.in_struct[self.depth] and !self.options.compact) {
                    try self.writeIndent();
                }
                // TODO: Get actual identifier from token data
                try self.writer.writeAll("identifier");
                self.need_comma = true;
            },
            .string_value => {
                if (!self.in_struct[self.depth] and !self.options.compact) {
                    try self.writeIndent();
                }
                // TODO: Get actual string value from token data
                try self.writer.writeAll("\"string\"");
                self.need_comma = true;
            },
            .number_value => {
                if (!self.in_struct[self.depth] and !self.options.compact) {
                    try self.writeIndent();
                }
                // TODO: Get actual number value from token data
                try self.writer.writeAll("0");
                self.need_comma = true;
            },
            .import => {
                if (!self.in_struct[self.depth] and !self.options.compact) {
                    try self.writeIndent();
                }
                // TODO: Get actual import from token data
                try self.writer.writeAll("@import(\"module\")");
                self.need_comma = true;
            },
            .enum_literal => {
                if (!self.in_struct[self.depth] and !self.options.compact) {
                    try self.writeIndent();
                }
                // TODO: Get actual enum literal from token data
                try self.writer.writeAll(".EnumValue");
                self.need_comma = true;
            },
            .equals => {
                if (!self.options.compact) {
                    try self.writer.writeAll(" = ");
                } else {
                    try self.writer.writeAll("=");
                }
                self.need_comma = false;
            },
            .comma => {
                // Handled above
                self.need_comma = false;
            },
            .paren_open => {
                try self.writer.writeAll("(");
                self.need_comma = false;
            },
            .paren_close => {
                try self.writer.writeAll(")");
                self.need_comma = true;
            },
            else => {},
        }
    }
    
    /// Finish formatting and ensure valid output
    pub fn finish(self: *Self) !void {
        if (self.depth != 0) {
            return FormatError.MismatchedBrackets;
        }
        if (!self.options.compact) {
            try self.writer.writeAll("\n");
        }
    }
    
    // Helper functions
    
    fn needsComma(self: *const Self, kind: ZonTokenKind) bool {
        _ = self;
        return switch (kind) {
            .object_end, .array_end, .comma, .equals, .paren_close => false,
            else => true,
        };
    }
    
    fn writeIndent(self: *Self) !void {
        if (self.options.compact) return;
        
        const indent_level = if (self.depth > 0) self.depth - 1 else 0;
        const total_indent = @as(usize, indent_level) * self.options.indent_width;
        
        switch (self.options.indent_style) {
            .spaces => {
                for (0..total_indent) |_| {
                    try self.writer.writeAll(" ");
                }
            },
            .tabs => {
                for (0..indent_level) |_| {
                    try self.writer.writeAll("\t");
                }
            },
            .none => {},
        }
    }
    
    fn writeNewline(self: *Self) !void {
        if (!self.options.compact) {
            try self.writer.writeAll("\n");
        }
    }
    };
}

test "ZonFormatter basic formatting" {
    const testing = std.testing;
    
    var buffer: [1024]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    
    var formatter = ZonFormatter(@TypeOf(stream.writer())).init(stream.writer(), .{
        .compact = true,
    });
    
    // Simulate tokens for: .{ .field = "value" }
    try formatter.writeToken(StreamToken{ .zon = ZonToken{
        .span = packSpan(Span.init(0, 2)),
        .kind = .struct_start,
        .depth = 0,
        .flags = .{},
        .data = 0,
    }});
    try formatter.writeToken(StreamToken{ .zon = ZonToken{
        .span = packSpan(Span.init(3, 9)),
        .kind = .field_name,
        .depth = 1,
        .flags = .{},
        .data = 0,
    }});
    try formatter.writeToken(StreamToken{ .zon = ZonToken{
        .span = packSpan(Span.init(10, 11)),
        .kind = .equals,
        .depth = 1,
        .flags = .{},
        .data = 0,
    }});
    try formatter.writeToken(StreamToken{ .zon = ZonToken{
        .span = packSpan(Span.init(12, 19)),
        .kind = .string_value,
        .depth = 1,
        .flags = .{},
        .data = 0,
    }});
    try formatter.writeToken(StreamToken{ .zon = ZonToken{
        .span = packSpan(Span.init(20, 21)),
        .kind = .object_end,
        .depth = 0,
        .flags = .{},
        .data = 0,
    }});
    try formatter.finish();
    
    const output = stream.getWritten();
    try testing.expect(std.mem.indexOf(u8, output, ".{") != null);
    try testing.expect(std.mem.indexOf(u8, output, "}") != null);
}