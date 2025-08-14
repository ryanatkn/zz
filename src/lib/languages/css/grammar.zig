const ts = @import("tree-sitter");

/// External tree-sitter grammar function for CSS
extern fn tree_sitter_css() *ts.Language;

/// Get tree-sitter grammar for CSS
pub fn grammar() *ts.Language {
    return tree_sitter_css();
}