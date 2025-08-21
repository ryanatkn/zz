/// Generic token stream infrastructure for composable language support
/// Users can create their own StreamToken unions by composing language tokens
const std = @import("std");
const TokenKind = @import("kind.zig").TokenKind;
const PackedSpan = @import("../span/mod.zig").PackedSpan;
const unpackSpan = @import("../span/mod.zig").unpackSpan;
const Span = @import("../span/mod.zig").Span;
const FactStore = @import("../fact/mod.zig").FactStore;

/// Generic token interface that all language tokens must satisfy
pub fn TokenInterface(comptime T: type) type {
    return struct {
        pub const Token = T;

        // Required fields
        comptime {
            if (!@hasField(T, "span")) @compileError("Token must have 'span: PackedSpan' field");
            if (!@hasField(T, "kind")) @compileError("Token must have 'kind' field");
            if (!@hasField(T, "depth")) @compileError("Token must have 'depth: u8' field");
        }

        // Required methods
        comptime {
            if (!@hasDecl(T, "isTrivia")) @compileError("Token must have 'isTrivia' method");
            if (!@hasDecl(T, "isOpenDelimiter")) @compileError("Token must have 'isOpenDelimiter' method");
            if (!@hasDecl(T, "isCloseDelimiter")) @compileError("Token must have 'isCloseDelimiter' method");
        }
    };
}

// TODO: Advanced @Type-based token generation
// This would allow dynamic union creation at compile time
// For now, users should use SimpleStreamToken with a manually defined union

/// Simpler approach: Direct tagged union without @Type magic
pub fn SimpleStreamToken(comptime langs: type) type {
    return struct {
        const Self = @This();

        /// The actual token union - user defines this
        token: langs,

        /// Get the packed span of this token
        pub inline fn span(self: Self) PackedSpan {
            return switch (self.token) {
                inline else => |tok| tok.span,
            };
        }

        /// Get the nesting depth
        pub inline fn depth(self: Self) u8 {
            return switch (self.token) {
                inline else => |tok| tok.depth,
            };
        }

        /// Check if token is trivia
        pub inline fn isTrivia(self: Self) bool {
            return switch (self.token) {
                inline else => |tok| tok.isTrivia(),
            };
        }

        /// Check if token opens a scope
        pub inline fn isOpenDelimiter(self: Self) bool {
            return switch (self.token) {
                inline else => |tok| tok.isOpenDelimiter(),
            };
        }

        /// Check if token closes a scope
        pub inline fn isCloseDelimiter(self: Self) bool {
            return switch (self.token) {
                inline else => |tok| tok.isCloseDelimiter(),
            };
        }

        /// Get string index if applicable
        pub inline fn getStringIndex(self: Self) ?u32 {
            return switch (self.token) {
                inline else => |tok| if (@hasDecl(@TypeOf(tok), "getStringIndex")) tok.getStringIndex() else null,
            };
        }
    };
}
