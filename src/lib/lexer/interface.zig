/// Unified Lexer Interface - Infrastructure for all language lexers
///
/// This interface defines the contract that all language lexers must implement,
/// supporting both streaming and batch tokenization modes.
const std = @import("std");
const Allocator = std.mem.Allocator;

// Import types from other modules
const token_mod = @import("../token/mod.zig");
const Token = token_mod.Token;
const StreamToken = token_mod.StreamToken;
const TokenStream = @import("streaming.zig").TokenStream;
const Edit = @import("incremental.zig").Edit;
const TokenDelta = @import("incremental.zig").TokenDelta;

/// Unified interface that all lexers must implement
pub const LexerInterface = struct {
    ptr: *anyopaque,

    // Core capability - all lexers must provide streaming tokens
    streamTokensFn: *const fn (ptr: *anyopaque, source: []const u8) TokenStream,

    // Batch tokenization when you need all tokens at once (for parser)
    batchTokenizeFn: *const fn (ptr: *anyopaque, allocator: Allocator, source: []const u8) anyerror![]Token,

    // Incremental updates for editors (optional)
    updateTokensFn: ?*const fn (ptr: *anyopaque, edit: Edit) TokenDelta,

    // Reset lexer state
    resetFn: *const fn (ptr: *anyopaque) void,

    // Public methods that delegate to function pointers
    pub fn streamTokens(self: LexerInterface, source: []const u8) TokenStream {
        return self.streamTokensFn(self.ptr, source);
    }

    pub fn batchTokenize(self: LexerInterface, allocator: Allocator, source: []const u8) ![]Token {
        return self.batchTokenizeFn(self.ptr, allocator, source);
    }

    pub fn updateTokens(self: LexerInterface, edit: Edit) ?TokenDelta {
        if (self.updateTokensFn) |updateFn| {
            return updateFn(self.ptr, edit);
        }
        return null;
    }

    pub fn reset(self: LexerInterface) void {
        self.resetFn(self.ptr);
    }
};

/// Helper to create a LexerInterface from any concrete lexer type
pub fn createInterface(lexer: anytype) LexerInterface {
    const T = @TypeOf(lexer);
    const ptr_info = @typeInfo(T);

    if (ptr_info != .pointer or ptr_info.pointer.size != .one) {
        @compileError("Lexer must be a single-item pointer");
    }

    const Impl = ptr_info.pointer.child;

    // Generate wrapper functions
    const gen = struct {
        fn streamTokens(ptr: *anyopaque, source: []const u8) TokenStream {
            const self: *Impl = @ptrCast(@alignCast(ptr));
            return self.streamTokens(source);
        }

        fn batchTokenize(ptr: *anyopaque, allocator: Allocator, source: []const u8) anyerror![]Token {
            const self: *Impl = @ptrCast(@alignCast(ptr));
            return self.batchTokenize(allocator, source);
        }

        fn updateTokens(ptr: *anyopaque, edit: Edit) TokenDelta {
            const self: *Impl = @ptrCast(@alignCast(ptr));
            if (@hasDecl(Impl, "updateTokens")) {
                return self.updateTokens(edit);
            }
            return TokenDelta{ .tokens = &.{}, .affected_range = edit.range };
        }

        fn reset(ptr: *anyopaque) void {
            const self: *Impl = @ptrCast(@alignCast(ptr));
            self.reset();
        }
    };

    return .{
        .ptr = lexer,
        .streamTokensFn = gen.streamTokens,
        .batchTokenizeFn = gen.batchTokenize,
        .updateTokensFn = if (@hasDecl(Impl, "updateTokens")) gen.updateTokens else null,
        .resetFn = gen.reset,
    };
}
