const std = @import("std");
const ExtractionFlags = @import("../parser.zig").ExtractionFlags;

pub fn extractSimple(source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) !void {
    // JSON is structural, so we extract based on structure
    if (flags.structure or flags.types) {
        // For JSON, extract all structural elements
        var lines = std.mem.tokenizeScalar(u8, source, '\n');
        
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t");
            
            // Skip empty lines
            if (trimmed.len == 0) continue;
            
            // Include all JSON structure
            try result.appendSlice(line);
            try result.append('\n');
        }
    } else if (flags.signatures) {
        // For signatures, just extract keys
        var lines = std.mem.tokenizeScalar(u8, source, '\n');
        
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t");
            if (std.mem.indexOf(u8, trimmed, "\":") != null) {
                try result.appendSlice(line);
                try result.append('\n');
            }
        }
    }
}