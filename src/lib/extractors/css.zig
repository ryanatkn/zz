const std = @import("std");
const ExtractionFlags = @import("../language/flags.zig").ExtractionFlags;
const line_processing = @import("../text/line_processing.zig");
const patterns = @import("../text/patterns.zig");
const builders = @import("../text/builders.zig");

pub fn extract(source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) !void {
    // For CSS, structure extraction includes entire rules
    if (flags.structure) {
        // Use line_processing for filtering empty lines
        try line_processing.filterNonEmpty(source, result);
        return;
    }
    
    // For types flag, return full source
    if (flags.types) {
        try result.appendSlice(source);
        return;
    }
    
    // Extract selectors for signatures flag
    if (flags.signatures) {
        var lines = std.mem.splitScalar(u8, source, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t");
            
            // Check for @media queries using patterns
            if (std.mem.startsWith(u8, trimmed, "@media")) {
                // Use line_processing helper for extracting before brace
                if (line_processing.extractBeforeBrace(trimmed)) |selector| {
                    try builders.appendLine(result, selector);
                }
            }
            // Check for CSS selectors (ends with '{')
            else if (std.mem.indexOf(u8, trimmed, "{") != null) {
                // Use line_processing helper for extracting before brace
                if (line_processing.extractBeforeBrace(trimmed)) |selector| {
                    try builders.appendLine(result, selector);
                }
            }
        }
        return;
    }
    
    // Extract imports using patterns utilities
    if (flags.imports) {
        const import_prefixes = [_][]const u8{ "@import", "@use" };
        try line_processing.extractLinesWithPrefixes(source, &import_prefixes, result);
        return;
    }
    
    try result.appendSlice(source);
}