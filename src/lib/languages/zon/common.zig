/// Internal common imports and utilities for ZON modules
///
/// This module centralizes frequently used imports to reduce redundancy
/// across ZON implementation modules. This is for internal use within the
/// ZON language implementation only.

// Standard library
pub const std = @import("std");

// Core AST and parser types
pub const Node = @import("../../ast/mod.zig").Node;
pub const NodeType = @import("../../ast/mod.zig").NodeType;
pub const AST = @import("../../ast/mod.zig").AST;
pub const ASTUtils = @import("../../ast/utils.zig").ASTUtils;
pub const ASTTraversal = @import("../../ast/traversal.zig").ASTTraversal;

// Parser foundation types
pub const Token = @import("../../parser/foundation/types/token.zig").Token;
pub const TokenKind = @import("../../parser/foundation/types/predicate.zig").TokenKind;
pub const TokenFlags = @import("../../parser/foundation/types/token.zig").TokenFlags;
pub const Span = @import("../../parser/foundation/types/span.zig").Span;

// Language interface types (for internal implementation)
pub const FormatOptions = @import("../interface.zig").FormatOptions;
pub const Rule = @import("../interface.zig").Rule;
pub const Symbol = @import("../interface.zig").Symbol;
pub const Diagnostic = @import("../interface.zig").Diagnostic;

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
