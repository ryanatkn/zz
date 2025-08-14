const std = @import("std");
const ExtractionFlags = @import("../../language/flags.zig").ExtractionFlags;
const extractWithPatterns = @import("../../extractor_base.zig").extractWithPatterns;
const LanguagePatterns = @import("../../extractor_base.zig").LanguagePatterns;

/// Extract CSS code using patterns
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

    // Use pattern-based extraction for CSS
    const patterns = getCSSPatterns();
    try extractWithPatterns(source, flags, result, patterns);
}

/// Get CSS-specific extraction patterns
fn getCSSPatterns() LanguagePatterns {
    const function_patterns: []const []const u8 = &[_][]const u8{}; // CSS doesn't have functions
    const type_patterns = [_][]const u8{ ".", "#", ":", "@", ":root", ":before", ":after", ":hover", "::before", "::after" };
    const import_patterns = [_][]const u8{ "@import", "@use", "@forward" };
    const doc_patterns: []const []const u8 = &[_][]const u8{}; // Comments handled elsewhere
    const test_patterns: []const []const u8 = &[_][]const u8{}; // No tests in CSS
    const structure_patterns = [_][]const u8{ ".", "#", ":", "@", ":root" };

    return LanguagePatterns{
        .functions = function_patterns,
        .types = type_patterns[0..],
        .imports = import_patterns[0..],
        .docs = doc_patterns,
        .tests = test_patterns,
        .structure = structure_patterns[0..],
        .custom_extract = cssCustomExtract,
    };
}

/// Custom extraction logic for CSS-specific patterns
fn cssCustomExtract(line: []const u8, flags: ExtractionFlags) bool {
    // Extract CSS selectors and rules (for types flag)
    if (flags.types) {
        // Include lines containing CSS properties or selectors
        if (std.mem.indexOf(u8, line, ":") != null or
            std.mem.indexOf(u8, line, "{") != null or
            std.mem.indexOf(u8, line, "}") != null)
        {
            return true;
        }
    }

    // Extract selectors (for signatures flag)
    if (flags.signatures) {
        if (std.mem.indexOf(u8, line, "{") != null) {
            return true;
        }
    }

    return false;
}
