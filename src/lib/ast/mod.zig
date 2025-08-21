/// AST Module - Bridge to ast_old during migration
///
/// This module temporarily re-exports from ast_old while we migrate
/// the AST implementation to the new architecture.
///
/// TODO: Phase 2.5 - Gradually move types here and delete ast_old

// For now, re-export everything from ast_old
// This allows code to import from ast/ instead of ast_old/
pub usingnamespace @import("../ast_old/mod.zig");

// Also export our new node types for progressive parser
pub const node = @import("node.zig");

// Eventually, we'll have:
// pub const AST = @import("ast.zig").AST;
// pub const Node = @import("node.zig").Node;
// pub const builder = @import("builder.zig");
// pub const factory = @import("factory.zig");
// pub const traversal = @import("traversal.zig");
// pub const query = @import("query.zig");
// etc.
