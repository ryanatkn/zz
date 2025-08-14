const std = @import("std");
const ExtractionFlags = @import("../../language/flags.zig").ExtractionFlags;

/// Extract JSON code using tree-sitter AST
pub fn extract(_: std.mem.Allocator, source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) !void {
    // JSON is primarily data, so most extraction just returns the source
    if (flags.full) {
        try result.appendSlice(source);
        return;
    }
    
    // For specific flags, we could use tree-sitter to extract structure
    // but JSON is simple enough that returning source is usually what's wanted
    if (flags.types or flags.structure or flags.signatures) {
        try result.appendSlice(source);
        return;
    }
    
    // For other flags, return source (JSON doesn't have functions, imports, etc.)
    try result.appendSlice(source);
}