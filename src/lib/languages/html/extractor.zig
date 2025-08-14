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
    
    // If no specific flags are set, return full source (backward compatibility)
    if (!flags.signatures and !flags.types and !flags.imports and !flags.docs and !flags.tests and !flags.structure) {
        try result.appendSlice(source);
        return;
    }
    
    // Use pattern-based extraction for HTML
    const patterns = patterns_mod.getHtmlPatterns();
    try extractWithPatterns(source, flags, result, patterns);
}