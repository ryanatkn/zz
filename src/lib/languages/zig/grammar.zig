const ts = @import("tree-sitter");

/// Get tree-sitter grammar for Zig
pub fn grammar() *ts.Language {
    return tree_sitter_zig();
}

// External grammar function
extern fn tree_sitter_zig() *ts.Language;