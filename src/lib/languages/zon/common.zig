/// Internal common imports and utilities for ZON modules
///
/// This module centralizes frequently used imports to reduce redundancy
/// across ZON implementation modules. This is for internal use within the
/// ZON language implementation only.

// Standard library
pub const std = @import("std");

// Core AST and parser types
const ast_mod = @import("../../ast/mod.zig");
pub const Node = ast_mod.Node;
pub const NodeType = ast_mod.NodeType;
pub const AST = ast_mod.AST;
pub const ASTUtils = @import("../../ast/utils.zig").ASTUtils;
pub const ASTTraversal = @import("../../ast/traversal.zig").ASTTraversal;

// Parser foundation types
const token_types = @import("../../parser/foundation/types/token.zig");
pub const Token = token_types.Token;
pub const TokenFlags = token_types.TokenFlags;
const predicate_types = @import("../../parser/foundation/types/predicate.zig");
pub const TokenKind = predicate_types.TokenKind;
pub const Span = @import("../../parser/foundation/types/span.zig").Span;

// Language interface types (for internal implementation)
const interface_types = @import("../interface.zig");
pub const FormatOptions = interface_types.FormatOptions;
pub const Rule = interface_types.Rule;
pub const Symbol = interface_types.Symbol;
pub const Diagnostic = interface_types.Diagnostic;

// ZON-specific internal modules
pub const utils = @import("utils.zig");
pub const ParseContext = @import("memory.zig").ParseContext;

/// Common error types for ZON operations
pub const ZonError = error{
    InvalidSyntax,
    UnexpectedToken,
    MissingField,
    InvalidFieldName,
    UnexpectedEndOfInput,
    InvalidFieldStructure,
} || std.mem.Allocator.Error;
