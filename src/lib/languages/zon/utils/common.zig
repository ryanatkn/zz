/// Internal common imports and utilities for ZON modules
///
/// This module centralizes frequently used imports to reduce redundancy
/// across ZON implementation modules. This is for internal use within the
/// ZON language implementation only.

// Standard library
pub const std = @import("std");

// Span type (still used)
pub const Span = @import("../../../span/mod.zig").Span;

// ZON-specific AST (self-contained)
const zon_ast = @import("../ast/nodes.zig");
pub const AST = zon_ast.AST;
pub const Node = zon_ast.Node;
pub const NodeKind = zon_ast.NodeKind;

// Generic AST utilities (zero coupling)
pub const Walker = @import("../../../ast/walker.zig").Walker;
pub const Builder = @import("../../../ast/builder.zig").Builder;

// Language interface types (for internal implementation)
const interface_types = @import("../../interface.zig");
pub const FormatOptions = interface_types.FormatOptions;
pub const Rule = interface_types.Rule;
pub const Symbol = interface_types.Symbol;
pub const Diagnostic = interface_types.Diagnostic;

// ZON-specific internal modules
pub const utils = @import("helpers.zig");

// Direct memory system usage
pub const memory = @import("../../../memory/language_strategies/mod.zig");
pub const MemoryContext = memory.MemoryContext;

/// Common error types for ZON operations
pub const ZonError = error{
    InvalidSyntax,
    UnexpectedToken,
    MissingField,
    InvalidFieldName,
    UnexpectedEndOfInput,
    InvalidFieldStructure,
} || std.mem.Allocator.Error;
