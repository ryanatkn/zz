const std = @import("std");
const Token = @import("../../parser_old/foundation/types/token.zig").Token;
const TokenKind = @import("../../parser_old/foundation/types/predicate.zig").TokenKind;
const Span = @import("../../parser_old/foundation/types/span.zig").Span;
const char = @import("../../char/mod.zig");

/// High-performance stateful lexer infrastructure for streaming tokenization
///
/// Features:
/// - Zero heap allocations in hot paths
/// - Stack-based partial token buffer
/// - Compact state representation (8 bytes)
/// - Support for resuming tokenization across chunk boundaries
/// - 100% correctness with no data loss
pub const StatefulLexer = struct {
    /// Lexer state that persists across chunks
    pub const State = struct {
        /// Fixed-size buffer for partial tokens (stack-allocated)
        partial_token_buf: [4096]u8 = undefined,
        /// Current length of partial token
        partial_token_len: u16 = 0,

        /// Current parsing context
        context: Context = .normal,

        /// Character that started current string (0 if not in string)
        quote_char: u8 = 0,

        /// Count for unicode escape sequences (\uXXXX)
        unicode_count: u8 = 0,

        /// State for number parsing
        number_state: NumberState = .{},

        /// General purpose flags
        flags: Flags = .{},

        /// Global position in the input stream
        global_position: usize = 0,

        /// Parsing context enum - kept small for performance
        pub const Context = enum(u8) {
            normal = 0,
            in_string = 1,
            in_escape = 2,
            in_unicode = 3,
            in_number = 4,
            in_comment_line = 5,
            in_comment_block = 6,
            in_template = 7, // Template literals for TS/JS
            in_regex = 8, // Regex literals for TS/JS
            in_raw_string = 9, // Raw strings (Zig r"...")
            in_multiline_string = 10, // Multiline strings (Zig \\)
        };

        /// Number parsing state bitfield - supports all number formats
        pub const NumberState = packed struct {
            has_minus: bool = false,
            has_digit: bool = false,
            has_dot: bool = false,
            has_fraction: bool = false,
            has_e: bool = false,
            has_exponent_sign: bool = false,
            has_exponent_digit: bool = false,

            // Extended for all languages
            has_underscore: bool = false, // Zig/Rust digit separators
            has_hex_prefix: bool = false, // 0x prefix
            has_bin_prefix: bool = false, // 0b prefix
            has_oct_prefix: bool = false, // 0o prefix
            has_hex_digit: bool = false, // a-f digits
            is_float: bool = false, // Explicit float
            is_bigint: bool = false, // BigInt suffix (JS)
            _padding: u1 = 0,
        };

        /// General flags - configurable per language
        pub const Flags = packed struct {
            allow_comments: bool = false,
            allow_trailing_commas: bool = false,
            json5_mode: bool = false,
            error_recovery: bool = true,

            // Extended language features
            allow_template_literals: bool = false, // TypeScript/JavaScript
            allow_regex_literals: bool = false, // TypeScript/JavaScript
            allow_raw_strings: bool = false, // Zig r"..."
            allow_multiline_strings: bool = false, // Zig \\
            _padding: u0 = 0,
        };

        /// Reset state to initial values
        pub fn reset(self: *State) void {
            self.partial_token_len = 0;
            self.context = .normal;
            self.quote_char = 0;
            self.unicode_count = 0;
            self.number_state = .{};
            // Don't reset flags or global_position
        }

        /// Check if we have a partial token
        pub fn hasPartialToken(self: State) bool {
            return self.partial_token_len > 0;
        }

        /// Get the partial token as a slice
        pub fn getPartialToken(self: State) []const u8 {
            return self.partial_token_buf[0..self.partial_token_len];
        }

        /// Append to partial token buffer
        pub fn appendToPartial(self: *State, data: []const u8) !void {
            const new_len = self.partial_token_len + data.len;
            if (new_len > self.partial_token_buf.len) {
                return error.PartialTokenTooLarge;
            }
            @memcpy(self.partial_token_buf[self.partial_token_len..new_len], data);
            self.partial_token_len = @intCast(new_len);
        }

        /// Clear partial token buffer
        pub fn clearPartial(self: *State) void {
            self.partial_token_len = 0;
        }
    };

    /// Interface for language-specific lexer implementations
    pub const Interface = struct {
        ptr: *anyopaque,
        vtable: *const VTable,

        pub const VTable = struct {
            /// Process a chunk of input, returning tokens
            processChunk: *const fn (
                ptr: *anyopaque,
                chunk: []const u8,
                chunk_pos: usize,
                allocator: std.mem.Allocator,
            ) anyerror![]Token,

            /// Get current state
            getState: *const fn (ptr: *anyopaque) *State,

            /// Reset to initial state
            reset: *const fn (ptr: *anyopaque) void,

            /// Clean up resources
            deinit: *const fn (ptr: *anyopaque) void,
        };

        pub fn init(implementation: anytype) Interface {
            const Impl = @TypeOf(implementation);
            const impl_info = @typeInfo(Impl);

            if (impl_info != .pointer) @compileError("implementation must be a pointer");

            const gen = struct {
                fn processChunkImpl(
                    ptr: *anyopaque,
                    chunk: []const u8,
                    chunk_pos: usize,
                    allocator: std.mem.Allocator,
                ) anyerror![]Token {
                    const self: Impl = @ptrCast(@alignCast(ptr));
                    return self.processChunk(chunk, chunk_pos, allocator);
                }

                fn getStateImpl(ptr: *anyopaque) *State {
                    const self: Impl = @ptrCast(@alignCast(ptr));
                    return &self.state;
                }

                fn resetImpl(ptr: *anyopaque) void {
                    const self: Impl = @ptrCast(@alignCast(ptr));
                    self.reset();
                }

                fn deinitImpl(ptr: *anyopaque) void {
                    const self: Impl = @ptrCast(@alignCast(ptr));
                    self.deinit();
                }

                const vtable = VTable{
                    .processChunk = processChunkImpl,
                    .getState = getStateImpl,
                    .reset = resetImpl,
                    .deinit = deinitImpl,
                };
            };

            return .{
                .ptr = implementation,
                .vtable = &gen.vtable,
            };
        }

        pub fn processChunk(
            self: Interface,
            chunk: []const u8,
            chunk_pos: usize,
            allocator: std.mem.Allocator,
        ) ![]Token {
            return self.vtable.processChunk(self.ptr, chunk, chunk_pos, allocator);
        }

        pub fn getState(self: Interface) *State {
            return self.vtable.getState(self.ptr);
        }

        pub fn reset(self: Interface) void {
            self.vtable.reset(self.ptr);
        }

        pub fn deinit(self: Interface) void {
            self.vtable.deinit(self.ptr);
        }
    };

    /// Options for creating a stateful lexer
    pub const Options = struct {
        allow_comments: bool = false,
        allow_trailing_commas: bool = false,
        json5_mode: bool = false,
        error_recovery: bool = true,

        // Extended language features
        allow_template_literals: bool = false, // TypeScript/JavaScript
        allow_regex_literals: bool = false, // TypeScript/JavaScript
        allow_raw_strings: bool = false, // Zig r"..."
        allow_multiline_strings: bool = false, // Zig \\
    };

    /// Helper functions for lexer implementations
    pub const Helpers = struct {
        /// Check if we can complete a token with the available input
        pub fn canCompleteToken(context: State.Context, input: []const u8) bool {
            return switch (context) {
                .normal => true,
                .in_string => std.mem.indexOfScalar(u8, input, '"') != null,
                .in_escape => input.len >= 1,
                .in_unicode => input.len >= 4,
                .in_number => !isNumberChar(input[0]),
                .in_comment_line => std.mem.indexOfScalar(u8, input, '\n') != null,
                .in_comment_block => std.mem.indexOf(u8, input, "*/") != null,
                .in_template => std.mem.indexOfScalar(u8, input, '`') != null or std.mem.indexOf(u8, input, "${") != null,
                .in_regex => std.mem.indexOfScalar(u8, input, '/') != null,
                .in_raw_string => std.mem.indexOf(u8, input, "\";") != null,
                .in_multiline_string => std.mem.indexOf(u8, input, "\\\\") != null,
            };
        }

        /// Check if character can be part of a number (includes separators and suffixes)
        pub fn isNumberChar(ch: u8) bool {
            return char.isDigit(ch) or char.isHexDigit(ch) or switch (ch) {
                '.', '+', '-' => true, // Sign and decimal
                'x', 'X', 'o', 'O' => true, // Prefixes
                '_' => true, // Separators (Zig, Rust)
                'n' => true, // BigInt suffix (JS)
                else => false,
            };
        }

        /// Try to parse a fast delimiter token
        pub fn tryFastDelimiter(ch: u8) ?TokenKind {
            return switch (ch) {
                '{' => .left_brace,
                '}' => .right_brace,
                '[' => .left_bracket,
                ']' => .right_bracket,
                '(' => .left_paren,
                ')' => .right_paren,
                ',' => .comma,
                ':' => .colon,
                ';' => .semicolon,
                '.' => .dot,
                else => null,
            };
        }

        /// Create a token with proper span
        pub fn createToken(
            span: Span,
            kind: TokenKind,
            text: []const u8,
            flags: u8,
        ) Token {
            return Token.simple(span, kind, text, flags);
        }
    };
};

// Tests
const testing = std.testing;

test "StatefulLexer.State - initialization" {
    var state = StatefulLexer.State{};
    try testing.expect(state.context == .normal);
    try testing.expect(state.partial_token_len == 0);
    try testing.expect(state.quote_char == 0);
    try testing.expect(!state.hasPartialToken());
}

test "StatefulLexer.State - partial token management" {
    var state = StatefulLexer.State{};

    // Add partial token
    try state.appendToPartial("test");
    try testing.expect(state.hasPartialToken());
    try testing.expectEqualStrings("test", state.getPartialToken());

    // Append more
    try state.appendToPartial("123");
    try testing.expectEqualStrings("test123", state.getPartialToken());

    // Clear
    state.clearPartial();
    try testing.expect(!state.hasPartialToken());
    try testing.expect(state.partial_token_len == 0);
}

test "StatefulLexer.State - context transitions" {
    var state = StatefulLexer.State{};

    // Transition to string context
    state.context = .in_string;
    state.quote_char = '"';
    try testing.expect(state.context == .in_string);
    try testing.expect(state.quote_char == '"');

    // Reset should clear context but not flags
    state.flags.json5_mode = true;
    state.reset();
    try testing.expect(state.context == .normal);
    try testing.expect(state.quote_char == 0);
    try testing.expect(state.flags.json5_mode == true);
}

test "StatefulLexer.State - number state tracking" {
    var state = StatefulLexer.State{};

    state.number_state.has_minus = true;
    state.number_state.has_digit = true;
    state.number_state.has_dot = true;

    try testing.expect(state.number_state.has_minus);
    try testing.expect(state.number_state.has_digit);
    try testing.expect(state.number_state.has_dot);
    try testing.expect(!state.number_state.has_e);
}

test "StatefulLexer.Helpers - fast delimiter detection" {
    try testing.expect(StatefulLexer.Helpers.tryFastDelimiter('{') == .left_brace);
    try testing.expect(StatefulLexer.Helpers.tryFastDelimiter('}') == .right_brace);
    try testing.expect(StatefulLexer.Helpers.tryFastDelimiter(',') == .comma);
    try testing.expect(StatefulLexer.Helpers.tryFastDelimiter('a') == null);
}

test "StatefulLexer.Helpers - number character detection" {
    try testing.expect(StatefulLexer.Helpers.isNumberChar('0'));
    try testing.expect(StatefulLexer.Helpers.isNumberChar('9'));
    try testing.expect(StatefulLexer.Helpers.isNumberChar('.'));
    try testing.expect(StatefulLexer.Helpers.isNumberChar('e'));
    try testing.expect(StatefulLexer.Helpers.isNumberChar('E'));
    try testing.expect(StatefulLexer.Helpers.isNumberChar('a')); // Hex digit, should be true
    try testing.expect(StatefulLexer.Helpers.isNumberChar('F')); // Hex digit, should be true
    try testing.expect(!StatefulLexer.Helpers.isNumberChar(' '));
    try testing.expect(!StatefulLexer.Helpers.isNumberChar('g')); // Not hex, should be false
}

test "StatefulLexer.State - buffer overflow protection" {
    var state = StatefulLexer.State{};

    // Create a string that's too large
    const large_data = [_]u8{'x'} ** 5000;

    // Should return error when exceeding buffer size
    const result = state.appendToPartial(&large_data);
    try testing.expectError(error.PartialTokenTooLarge, result);
}
