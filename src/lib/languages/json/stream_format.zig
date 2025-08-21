/// JSON formatter using DirectTokenStream
/// Zero-allocation streaming formatter with optimal performance
const std = @import("std");
const FormatOptions = @import("../../stream/format_options.zig").FormatOptions;
const FormatError = @import("../../stream/format.zig").FormatError;
const StreamToken = @import("../../token/mod.zig").StreamToken;
const JsonTokenKind = @import("stream_token.zig").JsonTokenKind;
const JsonToken = @import("stream_token.zig").JsonToken;
const packSpan = @import("../../span/mod.zig").packSpan;
const Span = @import("../../span/mod.zig").Span;

/// JSON formatter state machine
pub fn JsonFormatter(comptime Writer: type) type {
    return struct {
        writer: Writer,
        options: FormatOptions,
        depth: u8 = 0,
        need_comma: bool = false,
        in_array: [256]bool = [_]bool{false} ** 256,

        const Self = @This();

        pub fn init(writer: Writer, options: FormatOptions) Self {
            return .{
                .writer = writer,
                .options = options,
            };
        }

        /// Write a single token with appropriate formatting
        pub fn writeToken(self: *Self, token: StreamToken) !void {
            // Only handle JSON tokens
            if (token != .json) return FormatError.InvalidToken;

            const json_token = token.json;

            // Handle EOF
            if (json_token.kind == .eof) {
                return;
            }

            // Write comma if needed
            if (self.needsComma(json_token.kind)) {
                if (self.need_comma) {
                    try self.writer.writeAll(",");
                    if (!self.options.compact) {
                        try self.writeNewline();
                    }
                }
            }

            // Write the token
            switch (json_token.kind) {
                .object_start => {
                    try self.writer.writeAll("{");
                    self.depth = @min(self.depth + 1, 255);
                    self.in_array[self.depth] = false;
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
                    self.in_array[self.depth] = true;
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
                .string_value => {
                    if (!self.in_array[self.depth] and !self.options.compact) {
                        try self.writeIndent();
                    }
                    // TODO: Get actual string value from token data
                    try self.writer.writeAll("\"string\"");
                    self.need_comma = true;
                },
                .number_value => {
                    if (!self.in_array[self.depth] and !self.options.compact) {
                        try self.writeIndent();
                    }
                    // TODO: Get actual number value from token data
                    try self.writer.writeAll("0");
                    self.need_comma = true;
                },
                .boolean_true => {
                    if (!self.in_array[self.depth] and !self.options.compact) {
                        try self.writeIndent();
                    }
                    try self.writer.writeAll("true");
                    self.need_comma = true;
                },
                .boolean_false => {
                    if (!self.in_array[self.depth] and !self.options.compact) {
                        try self.writeIndent();
                    }
                    try self.writer.writeAll("false");
                    self.need_comma = true;
                },
                .null_value => {
                    if (!self.in_array[self.depth] and !self.options.compact) {
                        try self.writeIndent();
                    }
                    try self.writer.writeAll("null");
                    self.need_comma = true;
                },
                .colon => {
                    try self.writer.writeAll(":");
                    if (!self.options.compact) {
                        try self.writer.writeAll(" ");
                    }
                    self.need_comma = false;
                },
                .comma => {
                    // Handled above
                    self.need_comma = false;
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

        fn needsComma(self: *const Self, kind: JsonTokenKind) bool {
            _ = self;
            return switch (kind) {
                .object_end, .array_end, .comma, .colon => false,
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

test "JsonFormatter basic formatting" {
    const testing = std.testing;

    var buffer: [1024]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);

    var formatter = JsonFormatter(@TypeOf(stream.writer())).init(stream.writer(), .{
        .compact = true,
    });

    // Simulate tokens for: {"key": "value"}
    try formatter.writeToken(StreamToken{ .json = JsonToken{
        .span = packSpan(Span.init(0, 1)),
        .kind = .object_start,
        .depth = 0,
        .flags = .{},
        .data = 0,
    } });
    try formatter.writeToken(StreamToken{ .json = JsonToken{
        .span = packSpan(Span.init(1, 6)),
        .kind = .string_value,
        .depth = 1,
        .flags = .{},
        .data = 0,
    } });
    try formatter.writeToken(StreamToken{ .json = JsonToken{
        .span = packSpan(Span.init(6, 7)),
        .kind = .colon,
        .depth = 1,
        .flags = .{},
        .data = 0,
    } });
    try formatter.writeToken(StreamToken{ .json = JsonToken{
        .span = packSpan(Span.init(8, 15)),
        .kind = .string_value,
        .depth = 1,
        .flags = .{},
        .data = 0,
    } });
    try formatter.writeToken(StreamToken{ .json = JsonToken{
        .span = packSpan(Span.init(15, 16)),
        .kind = .object_end,
        .depth = 0,
        .flags = .{},
        .data = 0,
    } });
    try formatter.finish();

    const output = stream.getWritten();
    try testing.expect(std.mem.indexOf(u8, output, "{") != null);
    try testing.expect(std.mem.indexOf(u8, output, "}") != null);
}
