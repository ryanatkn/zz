const ts = @import("tree-sitter");

/// Get tree-sitter grammar for Svelte
pub fn grammar() *ts.Language {
    return tree_sitter_svelte();
}

// External grammar function
extern fn tree_sitter_svelte() *ts.Language;
