/// Parser Interface - Contract for all language parsers
///
/// Parsers consume tokens to produce AST or structural information.
const std = @import("std");
const Allocator = std.mem.Allocator;

// Import dependencies
const Token = @import("../token/token.zig").Token;
const TokenDelta = @import("../lexer/incremental.zig").TokenDelta;
const Boundary = @import("structural.zig").Boundary;

/// Generic parser interface factory - creates interface for specific AST type
pub fn ParserInterface(comptime ASTType: type) type {
    return struct {
        ptr: *anyopaque,

        // Parser CONSUMES tokens from lexer to produce AST
        parseASTFn: *const fn (ptr: *anyopaque, allocator: Allocator, tokens: []const Token) anyerror!ASTType,

        // Incremental parsing for editors (optional)
        updateASTFn: ?*const fn (ptr: *anyopaque, ast: *ASTType, delta: TokenDelta) anyerror!void,

        // Structural analysis without full AST
        detectBoundariesFn: *const fn (ptr: *anyopaque, tokens: []const Token) anyerror![]Boundary,

        // Reset parser state
        resetFn: *const fn (ptr: *anyopaque) void,

        const Self = @This();

        // Public methods
        pub fn parseAST(self: Self, allocator: Allocator, tokens: []const Token) !ASTType {
            return self.parseASTFn(self.ptr, allocator, tokens);
        }

        pub fn updateAST(self: Self, ast: *ASTType, delta: TokenDelta) !void {
            if (self.updateASTFn) |updateFn| {
                return updateFn(self.ptr, ast, delta);
            }
            return error.IncrementalNotSupported;
        }

        pub fn detectBoundaries(self: Self, tokens: []const Token) ![]Boundary {
            return self.detectBoundariesFn(self.ptr, tokens);
        }

        pub fn reset(self: Self) void {
            self.resetFn(self.ptr);
        }
    };
}

/// Helper to create ParserInterface from concrete parser type
pub fn createInterface(comptime ASTType: type, parser: anytype) ParserInterface(ASTType) {
    const T = @TypeOf(parser);
    const ptr_info = @typeInfo(T);

    if (ptr_info != .Pointer or ptr_info.Pointer.size != .One) {
        @compileError("Parser must be a single-item pointer");
    }

    const Impl = ptr_info.Pointer.child;

    const gen = struct {
        fn parseAST(ptr: *anyopaque, allocator: Allocator, tokens: []const Token) anyerror!ASTType {
            const self: *Impl = @ptrCast(@alignCast(ptr));
            return self.parseAST(allocator, tokens);
        }

        fn updateAST(ptr: *anyopaque, ast: *ASTType, delta: TokenDelta) anyerror!void {
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
