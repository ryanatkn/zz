const std = @import("std");
const ExtractionFlags = @import("../../language/flags.zig").ExtractionFlags;

/// Extract JSON code using pattern-based extraction
pub fn extract(_: std.mem.Allocator, source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) !void {
    // JSON is primarily data, so most extraction just returns the source
    if (flags.full) {
        try result.appendSlice(source);
        return;
    }
    
    // For signatures flag in JSON, extract key-value pairs
    if (flags.signatures) {
        try extractJsonKeys(source, result);
        return;
    }
    
    // For other specific flags, return source (JSON is mostly structured data)
    if (flags.types or flags.structure or flags.imports or flags.docs or flags.tests) {
        try result.appendSlice(source);
        return;
    }
    
    // Default: return empty for unsupported extraction types
}

/// Extract JSON key-value pairs for signatures flag
fn extractJsonKeys(source: []const u8, result: *std.ArrayList(u8)) !void {
    var lines = std.mem.splitScalar(u8, source, '\n');
    
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        
        // Look for JSON key patterns: "key": 
        if (std.mem.indexOf(u8, trimmed, "\":") != null and std.mem.startsWith(u8, trimmed, "\"")) {
            try result.appendSlice(line);
            try result.append('\n');
        }
    }
}