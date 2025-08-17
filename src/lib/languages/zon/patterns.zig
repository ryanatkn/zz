const extractor_base = @import("../../extractor_base.zig");

/// ZON (Zig Object Notation) extraction patterns
/// ZON is Zig's native configuration format, similar to JSON but with Zig syntax
pub const patterns = extractor_base.LanguagePatterns{
    .functions = null, // ZON is data-only, no functions
    .types = &.{
        // Field definitions
        ".",
        ".@\"", // Quoted field names
    },
    .imports = null, // ZON doesn't have imports
    .docs = &.{
        "//", // Line comments
    },
    .tests = null, // ZON is configuration data, no tests
    .structure = &.{
        ".{", // Struct literals
        "= .{", // Field assignments to structs
        ".dependencies", // Common ZON sections
        ".settings",
        ".format",
        ".prompt",
        ".tree",
    },
};