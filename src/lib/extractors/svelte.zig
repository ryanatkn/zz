const std = @import("std");
const ExtractionFlags = @import("../extraction_flags.zig").ExtractionFlags;
const patterns = @import("../text_patterns.zig");

pub fn extract(source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) !void {
    // For structure flag, return full source
    if (flags.structure) {
        try result.appendSlice(source);
        return;
    }
    
    // Extract script sections for code-related flags (including types for variable declarations)
    if (flags.signatures or flags.imports or flags.types) {
        // Use extractAllBetween to find all script sections
        const allocator = std.heap.page_allocator; // Use temporary allocator
        var scripts = try patterns.extractAllBetween(allocator, source, "<script", "</script>");
        defer scripts.deinit();
        
        for (scripts.items) |script_content| {
            // Find the closing > of the opening tag
            if (std.mem.indexOf(u8, script_content, ">")) |tag_end| {
                const actual_content = script_content[tag_end + 1..];
                try result.appendSlice("<script>");
                try result.append('\n');
                try result.appendSlice(actual_content);
                try result.append('\n');
                try result.appendSlice("</script>");
                try result.append('\n');
            }
        }
    }
    
    // Extract style sections for types flag
    if (flags.types) {
        // Use extractAllBetween to find all style sections
        const allocator = std.heap.page_allocator; // Use temporary allocator
        var styles = try patterns.extractAllBetween(allocator, source, "<style", "</style>");
        defer styles.deinit();
        
        for (styles.items) |style_content| {
            // Find the closing > of the opening tag
            if (std.mem.indexOf(u8, style_content, ">")) |tag_end| {
                const actual_content = style_content[tag_end + 1..];
                try result.appendSlice("<style>");
                try result.append('\n');
                try result.appendSlice(actual_content);
                try result.append('\n');
                try result.appendSlice("</style>");
                try result.append('\n');
            }
        }
    }
}