const std = @import("std");
const ExtractionFlags = @import("../parser.zig").ExtractionFlags;

pub fn extractSimple(source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) !void {
    var lines = std.mem.tokenizeScalar(u8, source, '\n');
    
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        
        // Skip empty lines
        if (trimmed.len == 0) continue;
        
        // For CSS, we want to extract based on flags
        if (flags.types or flags.structure) {
            // Always include the line for CSS when types or structure is requested
            try result.appendSlice(line);
            try result.append('\n');
        } else if (flags.signatures) {
            // CSS selectors only (class names, IDs, elements)
            if ((std.mem.startsWith(u8, trimmed, ".") or
                 std.mem.startsWith(u8, trimmed, "#") or
                 std.mem.indexOf(u8, line, "{") != null) and
                !std.mem.startsWith(u8, trimmed, "/*")) {
                try result.appendSlice(line);
                try result.append('\n');
            }
        } else if (flags.imports) {
            if (std.mem.startsWith(u8, trimmed, "@import") or 
                std.mem.startsWith(u8, trimmed, "@use")) {
                try result.appendSlice(line);
                try result.append('\n');
            }
        } else if (flags.docs) {
            if (std.mem.startsWith(u8, trimmed, "/*") or
                std.mem.startsWith(u8, trimmed, "*")) {
                try result.appendSlice(line);
                try result.append('\n');
            }
        }
    }
}