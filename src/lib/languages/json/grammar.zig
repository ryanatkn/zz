const ts = @import("tree-sitter");

/// External tree-sitter grammar function for JSON
extern fn tree_sitter_json() *ts.Language;

/// Get tree-sitter grammar for JSON
pub fn grammar() *ts.Language {
    return tree_sitter_json();
}
