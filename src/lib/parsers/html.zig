const std = @import("std");
const ExtractionFlags = @import("../parser.zig").ExtractionFlags;

pub fn extractSimple(source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) !void {
    var lines = std.mem.tokenizeScalar(u8, source, '\n');
    
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        
        // Skip empty lines
        if (trimmed.len == 0) continue;
        
        if (flags.structure or flags.types) {
            // HTML tags and structure
            if (std.mem.startsWith(u8, trimmed, "<") and !std.mem.startsWith(u8, trimmed, "<!--")) {
                try result.appendSlice(line);
                try result.append('\n');
            }
        }
        
        if (flags.signatures) {
            // Look for script tags and function definitions
            if (std.mem.indexOf(u8, line, "<script") != null or
                std.mem.indexOf(u8, line, "function") != null or
                std.mem.indexOf(u8, line, "onclick") != null or
                std.mem.indexOf(u8, line, "onload") != null) {
                try result.appendSlice(line);
                try result.append('\n');
            }
        }
        
        if (flags.docs) {
            // HTML comments
            if (std.mem.indexOf(u8, trimmed, "<!--") != null or
                std.mem.indexOf(u8, trimmed, "-->") != null) {
                try result.appendSlice(line);
                try result.append('\n');
            }
        }
    }
}