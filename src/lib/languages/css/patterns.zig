const extractor_base = @import("../../extractor_base.zig");

/// CSS extraction patterns
pub const patterns = extractor_base.LanguagePatterns{
    .functions = null, // CSS doesn't have functions
    .types = &.{
        // CSS custom properties (variables)
        "--",
        // CSS classes and IDs
        ".",
        "#",
        // CSS pseudo-selectors
        ":",
        "::",
    },
    .imports = &.{
        "@import",
        "@use",
        "@forward",
        "url(",
    },
    .docs = &.{
        "/*",
        "//",
    },
    .structure = &.{
        "@media",
        "@keyframes",
        "@supports",
    },
};