const ts = @import("tree-sitter");

/// External tree-sitter grammar function for TypeScript
extern fn tree_sitter_typescript() *ts.Language;

/// Get tree-sitter grammar for TypeScript
pub fn grammar() *ts.Language {
    return tree_sitter_typescript();
}