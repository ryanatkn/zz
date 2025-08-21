/// Parser Interface - Contract for all language parsers
///
/// Parsers consume tokens to produce AST or structural information.
const std = @import("std");
const Allocator = std.mem.Allocator;

// Import dependencies
const Token = @import("../token/token.zig").Token;
const TokenDelta = @import("../lexer/incremental.zig").TokenDelta;
const AST = @import("../ast/node.zig").AST;
const Boundary = @import("structural.zig").Boundary;

/// Unified interface that all parsers must implement
pub const ParserInterface = struct {
    ptr: *anyopaque,

    // Parser CONSUMES tokens from lexer to produce AST
    parseASTFn: *const fn (ptr: *anyopaque, allocator: Allocator, tokens: []const Token) anyerror!AST,

    // Incremental parsing for editors (optional)
    updateASTFn: ?*const fn (ptr: *anyopaque, ast: *AST, delta: TokenDelta) anyerror!void,

    // Structural analysis without full AST
    detectBoundariesFn: *const fn (ptr: *anyopaque, tokens: []const Token) anyerror![]Boundary,

    // Reset parser state
    resetFn: *const fn (ptr: *anyopaque) void,

    // Public methods
    pub fn parseAST(self: ParserInterface, allocator: Allocator, tokens: []const Token) !AST {
        return self.parseASTFn(self.ptr, allocator, tokens);
    }

    pub fn updateAST(self: ParserInterface, ast: *AST, delta: TokenDelta) !void {
        if (self.updateASTFn) |updateFn| {
            return updateFn(self.ptr, ast, delta);
        }
        return error.IncrementalNotSupported;
    }

    pub fn detectBoundaries(self: ParserInterface, tokens: []const Token) ![]Boundary {
        return self.detectBoundariesFn(self.ptr, tokens);
    }

    pub fn reset(self: ParserInterface) void {
        self.resetFn(self.ptr);
    }
};

/// Helper to create ParserInterface from concrete parser type
pub fn createInterface(parser: anytype) ParserInterface {
    const T = @TypeOf(parser);
    const ptr_info = @typeInfo(T);

    if (ptr_info != .Pointer or ptr_info.Pointer.size != .One) {
        @compileError("Parser must be a single-item pointer");
    }

    const Impl = ptr_info.Pointer.child;

    const gen = struct {
        fn parseAST(ptr: *anyopaque, allocator: Allocator, tokens: []const Token) anyerror!AST {
            const self: *Impl = @ptrCast(@alignCast(ptr));
            return self.parseAST(allocator, tokens);
        }

        fn updateAST(ptr: *anyopaque, ast: *AST, delta: TokenDelta) anyerror!void {
            const self: *Impl = @ptrCast(@alignCast(ptr));
            if (@hasDecl(Impl, "updateAST")) {
                return self.updateAST(ast, delta);
            }
            return error.IncrementalNotSupported;
        }

        fn detectBoundaries(ptr: *anyopaque, tokens: []const Token) anyerror![]Boundary {
            const self: *Impl = @ptrCast(@alignCast(ptr));
            return self.detectBoundaries(tokens);
        }

        fn reset(ptr: *anyopaque) void {
            const self: *Impl = @ptrCast(@alignCast(ptr));
            self.reset();
        }
    };

    return .{
        .ptr = parser,
        .parseASTFn = gen.parseAST,
        .updateASTFn = if (@hasDecl(Impl, "updateAST")) gen.updateAST else null,
        .detectBoundariesFn = gen.detectBoundaries,
        .resetFn = gen.reset,
    };
}
