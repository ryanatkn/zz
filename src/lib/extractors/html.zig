const std = @import("std");
const ExtractionFlags = @import("../extraction_flags.zig").ExtractionFlags;

pub fn extract(source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) !void {
    // HTML doesn't have traditional code constructs
    if (flags.structure) {
        try result.appendSlice(source);
        return;
    }
    
    if (flags.docs) {
        // Extract comments
        var i: usize = 0;
        while (i < source.len) : (i += 1) {
            if (std.mem.startsWith(u8, source[i..], "<!--")) {
                const end = std.mem.indexOf(u8, source[i..], "-->");
                if (end) |e| {
                    try result.appendSlice(source[i..i + e + 3]);
                    try result.append('\n');
                    i += e + 2;
                }
            }
        }
        return;
    }
    
    try result.appendSlice(source);
}