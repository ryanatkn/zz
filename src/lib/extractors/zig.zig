const std = @import("std");
const ExtractionFlags = @import("../language/flags.zig").ExtractionFlags;
const extractor_base = @import("../extractor_base.zig");
// ResultBuilder now accessed through extractor_base

pub fn extract(source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) !void {
    // Special handling for Zig imports (uses @import which needs custom logic)
    var modified_flags = flags;
    const handle_imports = flags.imports;
    modified_flags.imports = false;

    // Use base extractor with local Zig patterns
    const zig_functions = [_][]const u8{ "pub fn ", "fn ", "export fn ", "inline fn ", "test " };
    const zig_types = [_][]const u8{ "struct", "enum", "union", "error", "packed struct", "extern struct", "opaque" };
    const zig_docs = [_][]const u8{ "///", "//!" };
    const zig_imports = [_][]const u8{ "@import(", "const std = " };

    var patterns = extractor_base.LanguagePatterns{
        .functions = &zig_functions,
        .types = &zig_types,
        .docs = &zig_docs,
        .imports = &zig_imports,
        .tests = &zig_functions, // tests use same patterns as functions
        .structure = null,
        .custom_extract = null,
    };

    // Add custom extraction for @import
    if (handle_imports) {
        patterns.custom_extract = zigImportExtractor;
    }

    try extractor_base.extractWithPatterns(source, modified_flags, result, patterns);
}

// Custom extractor for Zig @import patterns
fn zigImportExtractor(line: []const u8, flags: ExtractionFlags) bool {
    _ = flags;
    return std.mem.indexOf(u8, line, "@import(") != null;
}
