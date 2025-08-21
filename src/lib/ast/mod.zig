/// AST Utilities - Generic helpers for language-specific ASTs
///
/// This module provides generic utilities that work with any AST via comptime
/// duck typing. Each language defines its own Node types and AST structures
/// in languages/*/ast.zig and can use these utilities if needed.
///
/// No shared data types are exported - only generic helper functions.

// Generic walker that works with any Node type
pub const Walker = @import("walker.zig").Walker;
pub const walkAST = @import("walker.zig").walkAST;
pub const findInAST = @import("walker.zig").findInAST;
pub const collectInAST = @import("walker.zig").collectInAST;

// Generic arena builder patterns
pub const ArenaBuilder = @import("builder.zig").ArenaBuilder;
pub const createArenaBuilder = @import("builder.zig").createArenaBuilder;
pub const createNodeInArena = @import("builder.zig").createNodeInArena;
pub const ownStringInArena = @import("builder.zig").ownStringInArena;
pub const createArrayInArena = @import("builder.zig").createArrayInArena;

// Test utilities if they exist
pub const test_utils = @import("test.zig");
