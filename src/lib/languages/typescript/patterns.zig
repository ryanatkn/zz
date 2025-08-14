const extractor_base = @import("../../extractor_base.zig");

/// TypeScript extraction patterns
pub const patterns = extractor_base.LanguagePatterns{
    .functions = &.{
        "function ",
        "async function ",
        "const " // for arrow functions
    },
    .types = &.{
        "interface ",
        "type ",
        "class ",
        "enum ",
        "declare "
    },
    .imports = &.{
        "import ",
        "export ",
        "require(",
        "from '",
        "from \""
    },
    .docs = &.{
        "/**",
        "//"
    },
    .structure = &.{
        "module ",
        "namespace ",
        "declare "
    },
};