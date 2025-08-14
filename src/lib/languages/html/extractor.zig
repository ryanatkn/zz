const std = @import("std");
const ExtractionFlags = @import("../../language/flags.zig").ExtractionFlags;
const extractWithPatterns = @import("../../extractor_base.zig").extractWithPatterns;
const patterns_mod = @import("patterns.zig");

/// Extract HTML code using patterns or AST
pub fn extract(allocator: std.mem.Allocator, source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) !void {
    _ = allocator; // Not needed for pattern-based extraction
    
    // If full flag is set, return full source
    if (flags.full) {
        try result.appendSlice(source);
        return;
    }
    
    // Handle structure flag specifically for HTML
    if (flags.structure) {
        var lines = std.mem.splitScalar(u8, source, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t");
            
            // Include DOCTYPE, main HTML tags, and structural elements
            if (std.mem.startsWith(u8, trimmed, "<!DOCTYPE") or
                std.mem.startsWith(u8, trimmed, "<html") or
                std.mem.startsWith(u8, trimmed, "<head") or
                std.mem.startsWith(u8, trimmed, "<body") or
                std.mem.startsWith(u8, trimmed, "<title") or
                std.mem.startsWith(u8, trimmed, "<div") or
                std.mem.startsWith(u8, trimmed, "</")) {
                try result.appendSlice(line);
                try result.append('\n');
            }
        }
        return;
    }
    
    // If no specific flags are set, return full source (backward compatibility)
    if (!flags.signatures and !flags.types and !flags.imports and !flags.docs and !flags.tests) {
        try result.appendSlice(source);
        return;
    }
    
    // Use pattern-based extraction for HTML
    const patterns = patterns_mod.getHtmlPatterns();
    try extractWithPatterns(source, flags, result, patterns);
}