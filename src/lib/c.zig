// Centralized C library imports to prevent type mismatches across modules
// All C imports should be added here to maintain type consistency

// NOTE: Currently we use the Zig tree-sitter bindings via @import("tree-sitter")
// This file is prepared for future direct C imports when needed

// Tree-sitter language grammars will be imported here when we add them:
// pub const ts_zig = @cImport({
//     @cInclude("tree-sitter-zig.h");
// });
//
// pub const ts_typescript = @cImport({
//     @cInclude("tree-sitter-typescript.h");
// });
//
// pub const ts_rust = @cImport({
//     @cInclude("tree-sitter-rust.h");
// });
//
// pub const ts_go = @cImport({
//     @cInclude("tree-sitter-go.h");
// });
//
// pub const ts_python = @cImport({
//     @cInclude("tree-sitter-python.h");
// });

// To use in parser.zig:
// const c = @import("c.zig");
// const language = c.ts_zig.tree_sitter_zig();
// try parser.setLanguage(language);

// Future C libraries can be added here as separate constants:
// pub const sqlite = @cImport({ @cInclude("sqlite3.h"); });
// pub const curl = @cImport({ @cInclude("curl/curl.h"); });
