const std = @import("std");
const ExtractionFlags = @import("../../language/flags.zig").ExtractionFlags;
const extractWithPatterns = @import("../../extractor_base.zig").extractWithPatterns;
const LanguagePatterns = @import("../../extractor_base.zig").LanguagePatterns;

/// Extract HTML code using patterns
pub fn extract(allocator: std.mem.Allocator, source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) !void {
    _ = allocator; // Not needed for pattern-based extraction

    // If full flag is set, return full source
    if (flags.full) {
        try result.appendSlice(source);
        return;
    }

    // If no specific flags are set, return full source (backward compatibility)
    if (flags.isDefault()) {
        try result.appendSlice(source);
        return;
    }

    // Use pattern-based extraction for HTML
    const patterns = getHTMLPatterns();
    try extractWithPatterns(source, flags, result, patterns);
}

/// Get HTML-specific extraction patterns
fn getHTMLPatterns() LanguagePatterns {
    const function_patterns = [_][]const u8{ "function ", "onclick=", "onload=", "onchange=" };
    const type_patterns: []const []const u8 = &[_][]const u8{}; // HTML doesn't have types
    const import_patterns = [_][]const u8{ "<script src=", "<link href=", "@import" };
    const doc_patterns = [_][]const u8{"<!--"};
    const test_patterns: []const []const u8 = &[_][]const u8{}; // No tests in HTML
    const structure_patterns = [_][]const u8{ "<!DOCTYPE", "<html", "<head", "<body", "<title", "<h1", "<h2", "<h3", "<h4", "<h5", "<h6", "<div", "<p", "<span", "<nav", "<header", "<footer", "<section", "<article", "<aside", "<main" };

    return LanguagePatterns{
        .functions = function_patterns[0..],
        .types = type_patterns,
        .imports = import_patterns[0..],
        .docs = doc_patterns[0..],
        .tests = test_patterns,
        .structure = structure_patterns[0..],
        .custom_extract = htmlCustomExtract,
    };
}

/// Custom extraction logic for HTML-specific patterns
fn htmlCustomExtract(line: []const u8, flags: ExtractionFlags) bool {
    // Extract HTML tags (for structure flag)
    if (flags.structure) {
        if (std.mem.indexOf(u8, line, "<") != null) {
            return true;
        }
    }

    // Extract script content (for signatures flag)
    if (flags.signatures) {
        if (std.mem.indexOf(u8, line, "<script") != null or
            std.mem.indexOf(u8, line, "</script>") != null or
            std.mem.indexOf(u8, line, "onclick=") != null or
            std.mem.indexOf(u8, line, "function ") != null)
        {
            return true;
        }
    }

    return false;
}
