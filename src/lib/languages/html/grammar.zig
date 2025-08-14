const ts = @import("tree-sitter");

/// External tree-sitter grammar function for HTML
extern fn tree_sitter_html() *ts.Language;

/// Get tree-sitter grammar for HTML
pub fn grammar() *ts.Language {
    return tree_sitter_html();
}