const std = @import("std");
const ExtractionFlags = @import("../../language/flags.zig").ExtractionFlags;
const extractWithPatterns = @import("../../extractor_base.zig").extractWithPatterns;
const LanguagePatterns = @import("../../extractor_base.zig").LanguagePatterns;

/// Extract Zig code using patterns or AST
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

    // Use pattern-based extraction for Zig
    const patterns = getZigPatterns();
    try extractWithPatterns(source, flags, result, patterns);
}

/// Get Zig-specific extraction patterns
fn getZigPatterns() LanguagePatterns {
    const function_patterns = [_][]const u8{ "pub fn ", "fn ", "export fn ", "extern fn ", "test " };
    const type_patterns = [_][]const u8{ "const ", "var ", "struct {", "enum {", "union {", "error{", "pub const ", "pub var " };
    // For imports, we'll use custom logic since they can be in const declarations
    const import_patterns: []const []const u8 = &[_][]const u8{};
    const doc_patterns = [_][]const u8{"///"};
    const test_patterns = [_][]const u8{"test "};
    const structure_patterns = [_][]const u8{ "pub const ", "pub var ", "pub fn ", "struct", "enum", "union" };

    return LanguagePatterns{
        .functions = function_patterns[0..],
        .types = type_patterns[0..],
        .imports = import_patterns[0..],
        .docs = doc_patterns[0..],
        .tests = test_patterns[0..],
        .structure = structure_patterns[0..],
        .custom_extract = zigCustomExtract,
    };
}

/// Custom extraction logic for Zig-specific patterns
fn zigCustomExtract(line: []const u8, flags: ExtractionFlags) bool {
    const trimmed = std.mem.trim(u8, line, " \t");

    // Extract imports (lines containing @import or @cImport)
    if (flags.imports) {
        if (std.mem.indexOf(u8, line, "@import(") != null or
            std.mem.indexOf(u8, line, "@cImport(") != null)
        {
            return true;
        }
    }

    // Extract error definitions
    if (flags.errors) {
        if (std.mem.startsWith(u8, trimmed, "error{") or
            std.mem.indexOf(u8, trimmed, "error.") != null or
            std.mem.indexOf(u8, trimmed, "try ") != null or
            std.mem.indexOf(u8, trimmed, "catch") != null or
            std.mem.indexOf(u8, trimmed, "orelse") != null)
        {
            return true;
        }
    }

    // Extract comptime blocks for structure
    if (flags.structure) {
        if (std.mem.startsWith(u8, trimmed, "comptime") or
            std.mem.indexOf(u8, trimmed, "@") != null)
        {
            return true;
        }
    }

    // Include more function-like patterns for signatures
    if (flags.signatures) {
        // Catch async functions, function pointers, etc.
        if (std.mem.indexOf(u8, trimmed, "async fn") != null or
            std.mem.indexOf(u8, trimmed, "*const fn") != null or
            std.mem.indexOf(u8, trimmed, "*fn") != null)
        {
            return true;
        }
    }

    return false;
}
