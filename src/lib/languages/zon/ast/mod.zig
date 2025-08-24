/// AST Module - Abstract Syntax Tree for ZON
/// Re-exports from nodes.zig with clean naming

// Core AST types
pub const AST = @import("nodes.zig").AST;
pub const Node = @import("nodes.zig").Node;
pub const NodeKind = @import("nodes.zig").NodeKind;

// ZON-specific node types
pub const StringNode = @import("nodes.zig").StringNode;
pub const NumberNode = @import("nodes.zig").NumberNode;
pub const BooleanNode = @import("nodes.zig").BooleanNode;
pub const ObjectNode = @import("nodes.zig").ObjectNode;
pub const ArrayNode = @import("nodes.zig").ArrayNode;
pub const PropertyNode = @import("nodes.zig").PropertyNode;

// AST conversion utilities
pub const converter = @import("converter.zig");
pub const AstConverter = converter.AstConverter;
