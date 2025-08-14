const std = @import("std");
const ExtractionFlags = @import("../language/flags.zig").ExtractionFlags;

pub fn extract(source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) !void {
    _ = flags;

    // JSON is pure data, return as-is for any extraction
    try result.appendSlice(source);
}
