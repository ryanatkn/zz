const ts = @import("tree-sitter");

/// ZON (Zig Object Notation) grammar stub
/// TODO: Tree-sitter grammar for ZON doesn't exist yet
/// ZON is similar to JSON but uses Zig-specific syntax
/// For now, we use text-based parsing in parser.zig

/// Placeholder for future tree-sitter grammar
pub fn grammar() *ts.Language {
    // When ZON tree-sitter grammar becomes available, this will return it
    // For now, return null to indicate no AST support
    @compileError("ZON tree-sitter grammar not yet available - use text-based parsing");
}