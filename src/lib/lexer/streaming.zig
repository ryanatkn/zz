/// Streaming tokenization infrastructure
///
/// Provides zero-allocation token streaming interface that all lexers implement.
const std = @import("std");
const Token = @import("../token/token.zig").Token;

/// Zero-allocation streaming interface for tokens
pub const TokenStream = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    const VTable = struct {
        nextFn: *const fn (ptr: *anyopaque) ?Token,
        peekFn: *const fn (ptr: *anyopaque) ?Token,
        resetFn: *const fn (ptr: *anyopaque) void,
        skipFn: *const fn (ptr: *anyopaque, n: usize) void,
    };

    /// Get next token, advancing the stream
    pub fn next(self: *TokenStream) ?Token {
        return self.vtable.nextFn(self.ptr);
    }

    /// Peek at next token without advancing
    pub fn peek(self: *TokenStream) ?Token {
        return self.vtable.peekFn(self.ptr);
    }

    /// Reset stream to beginning
    pub fn reset(self: *TokenStream) void {
        self.vtable.resetFn(self.ptr);
    }

    /// Skip n tokens forward
    pub fn skip(self: *TokenStream, n: usize) void {
        self.vtable.skipFn(self.ptr, n);
    }
};

/// Helper to create a TokenStream from any iterator-like type
pub fn createTokenStream(iterator: anytype) TokenStream {
    const T = @TypeOf(iterator);
    const ptr_info = @typeInfo(T);

    if (ptr_info != .Pointer or ptr_info.Pointer.size != .One) {
        @compileError("Iterator must be a single-item pointer");
    }

    const Impl = ptr_info.Pointer.child;

    const gen = struct {
        fn next(ptr: *anyopaque) ?Token {
            const self: *Impl = @ptrCast(@alignCast(ptr));
            return self.next();
        }

        fn peek(ptr: *anyopaque) ?Token {
            const self: *Impl = @ptrCast(@alignCast(ptr));
            if (@hasDecl(Impl, "peek")) {
                return self.peek();
            }
            // Default implementation: can't peek
            return null;
        }

        fn reset(ptr: *anyopaque) void {
            const self: *Impl = @ptrCast(@alignCast(ptr));
            if (@hasDecl(Impl, "reset")) {
                self.reset();
            }
        }

        fn skip(ptr: *anyopaque, n: usize) void {
            const self: *Impl = @ptrCast(@alignCast(ptr));
            if (@hasDecl(Impl, "skip")) {
                self.skip(n);
            } else {
                // Default: call next() n times
                var i: usize = 0;
                while (i < n) : (i += 1) {
                    _ = self.next();
                }
            }
        }

        const vtable = VTable{
            .nextFn = next,
            .peekFn = peek,
            .resetFn = reset,
            .skipFn = skip,
        };
    };

    return .{
        .ptr = iterator,
        .vtable = &gen.vtable,
    };
}
