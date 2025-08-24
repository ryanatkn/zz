/// stream_format module - Stream-first formatting using DirectStream
/// Zero-allocation formatting pipeline for JSON and ZON
/// Achieves optimal performance with 1-2 cycle dispatch
///
/// Language-specific formatters are located with their language modules:
/// - JSON: languages/json/format/stream.zig
/// - ZON: languages/zon/stream_format.zig
const std = @import("std");

// Export formatter generator functions from language modules
pub const JsonFormatter = @import("../languages/json/format/stream.zig").Formatter;
pub const ZonFormatter = @import("../languages/zon/stream_format.zig").ZonFormatter;

// Export common types
pub const FormatOptions = @import("format_options.zig").FormatOptions;
pub const FormatError = error{
    InvalidToken,
    UnexpectedEof,
    MismatchedBrackets,
    InvalidDepth,
    BufferTooSmall,
};

/// Format any stream of tokens to output
pub fn formatStream(
    comptime FormatterGen: type,
    token_stream: anytype,
    writer: anytype,
    options: FormatOptions,
) !void {
    var formatter = FormatterGen(@TypeOf(writer)).init(writer, options);
    while (try token_stream.next()) |token| {
        try formatter.writeToken(token);
    }
    try formatter.finish();
}

test "stream format tests" {
    _ = @import("../languages/json/format/stream.zig");
    _ = @import("../languages/zon/stream_format.zig");
    _ = @import("format_options.zig");
}
