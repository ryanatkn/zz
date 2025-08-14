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
    if (!flags.signatures and !flags.types and !flags.imports and !flags.docs and !flags.tests and !flags.errors and !flags.structure) {
        try result.appendSlice(source);
        return;
    }
    
    // Use pattern-based extraction for Zig
    const patterns = getZigPatterns();
    try extractWithPatterns(source, flags, result, patterns);
}

/// Get Zig-specific extraction patterns
fn getZigPatterns() LanguagePatterns {
    const function_patterns = [_][]const u8{ "pub fn ", "fn ", "export fn ", "extern fn " };
    const type_patterns = [_][]const u8{ "const ", "var ", "struct {", "enum {", "union {", "error{" };
    const import_patterns = [_][]const u8{ "@import(", "@cImport(" };
    const doc_patterns = [_][]const u8{ "///" };
    const test_patterns = [_][]const u8{ "test " };
    const structure_patterns = [_][]const u8{ "pub const ", "pub var ", "pub fn ", "struct", "enum", "union" };
    
    return LanguagePatterns{
        .functions = &function_patterns,
        .types = &type_patterns,
        .imports = &import_patterns,
        .docs = &doc_patterns,
        .tests = &test_patterns,
        .structure = &structure_patterns,
        .custom_extract = zigCustomExtract,
    };
}

/// Custom extraction logic for Zig-specific patterns
fn zigCustomExtract(line: []const u8, flags: ExtractionFlags) bool {
    const trimmed = std.mem.trim(u8, line, " \t");
    
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
    
    return false;
}