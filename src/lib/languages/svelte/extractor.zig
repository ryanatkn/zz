const std = @import("std");
const ExtractionFlags = @import("../../language/flags.zig").ExtractionFlags;
const extractWithPatterns = @import("../../extractor_base.zig").extractWithPatterns;
const LanguagePatterns = @import("../../extractor_base.zig").LanguagePatterns;

/// Extract Svelte code using patterns
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
    
    // Use pattern-based extraction for Svelte
    const patterns = getSveltePatterns();
    try extractWithPatterns(source, flags, result, patterns);
}

/// Get Svelte-specific extraction patterns
fn getSveltePatterns() LanguagePatterns {
    // Svelte combines JavaScript functions with HTML structure
    const function_patterns = [_][]const u8{ "function ", "export let ", "let ", "const ", "export function ", "export const " };
    const type_patterns = [_][]const u8{ "<style", "</style>", ":global", "@media" };
    const import_patterns = [_][]const u8{ "import ", "export " };
    const doc_patterns: []const []const u8 = &[_][]const u8{}; // Comments handled elsewhere
    const test_patterns: []const []const u8 = &[_][]const u8{}; // No tests in Svelte
    const structure_patterns = [_][]const u8{ "<script", "</script>", "<style", "</style>", "<div", "<p", "<section" };
    
    return LanguagePatterns{
        .functions = function_patterns[0..],
        .types = type_patterns[0..],
        .imports = import_patterns[0..],
        .docs = doc_patterns,
        .tests = test_patterns,
        .structure = structure_patterns[0..],
        .custom_extract = svelteCustomExtract,
    };
}

/// Custom extraction logic for Svelte-specific patterns
fn svelteCustomExtract(line: []const u8, flags: ExtractionFlags) bool {
    // Extract script sections (for signatures flag)
    if (flags.signatures) {
        if (std.mem.indexOf(u8, line, "<script") != null or
            std.mem.indexOf(u8, line, "</script>") != null)
        {
            return true;
        }
        // Include content inside script sections
        // This is a simple heuristic - real implementation would track sections
    }
    
    // Extract style sections (for types flag)
    if (flags.types) {
        if (std.mem.indexOf(u8, line, "<style") != null or
            std.mem.indexOf(u8, line, "</style>") != null)
        {
            return true;
        }
    }
    
    return false;
}