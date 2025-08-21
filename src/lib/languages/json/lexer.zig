/// JSON Lexer - Clean implementation for progressive parser architecture
///
/// Implements LexerInterface with direct streaming and batch tokenization.
/// No legacy code, no adapters, pure implementation.
const std = @import("std");
const Allocator = std.mem.Allocator;

// Import new infrastructure
const token_mod = @import("../../token/mod.zig");
const Token = token_mod.Token;
const TokenKind = token_mod.TokenKind;
const TokenFlags = token_mod.TokenFlags;
const Span = @import("../../span/mod.zig").Span;
const LexerInterface = @import("../../lexer/interface.zig").LexerInterface;
const createInterface = @import("../../lexer/interface.zig").createInterface;
const TokenStream = @import("../../lexer/streaming.zig").TokenStream;
const createTokenStream = @import("../../lexer/streaming.zig").createTokenStream;

// Use character utilities
const char = @import("../../char/mod.zig");

/// JSON Lexer with streaming-first design
pub const JsonLexer = struct {
    allocator: Allocator,
    source: []const u8,
    position: usize,
    
    const Self = @This();
    
    pub fn init(allocator: Allocator) Self {
        return .{
            .allocator = allocator,
            .source = "",
            .position = 0,
        };
    }
    
    pub fn deinit(self: *Self) void {
        _ = self;
        // Nothing to clean up in basic implementation
    }
    
    /// Create a LexerInterface for this lexer
    pub fn interface(self: *Self) LexerInterface {
        return createInterface(self);
    }
    
    /// Stream tokens without allocation
    pub fn streamTokens(self: *Self, source: []const u8) TokenStream {
        self.source = source;
        self.position = 0;
        
        var iterator = StreamIterator.init(self);
        return createTokenStream(&iterator);
    }
    
    /// Batch tokenize - allocates all tokens
    pub fn batchTokenize(self: *Self, allocator: Allocator, source: []const u8) ![]Token {
        self.source = source;
        self.position = 0;
        
        var tokens = std.ArrayList(Token).init(allocator);
        defer tokens.deinit();
        
        var iterator = StreamIterator.init(self);
        while (iterator.next()) |token| {
            try tokens.append(token);
        }
        
        return tokens.toOwnedSlice();
    }
    
    /// Reset lexer state
    pub fn reset(self: *Self) void {
        self.position = 0;
        self.source = "";
    }
};

/// Streaming iterator for zero-allocation tokenization
const StreamIterator = struct {
    lexer: *JsonLexer,
    
    const Self = @This();
    
    pub fn init(lexer: *JsonLexer) Self {
        return .{ .lexer = lexer };
    }
    
    pub fn next(self: *Self) ?Token {
        const lexer = self.lexer;
        
        // Skip whitespace
        while (lexer.position < lexer.source.len) {
            const c = lexer.source[lexer.position];
            if (!char.isWhitespace(c)) break;
            lexer.position += 1;
        }
        
        // Check for EOF
        if (lexer.position >= lexer.source.len) {
            return Token{
                .span = Span.init(@intCast(lexer.position), @intCast(lexer.position)),
                .kind = .eof,
                .depth = 0,
                .flags = .{},
            };
        }
        
        const start = lexer.position;
        const c = lexer.source[lexer.position];
        
        // Single character tokens
        const token_kind: ?TokenKind = switch (c) {
            '{' => blk: {
                lexer.position += 1;
                break :blk .left_brace;
            },
            '}' => blk: {
                lexer.position += 1;
                break :blk .right_brace;
            },
            '[' => blk: {
                lexer.position += 1;
                break :blk .left_bracket;
            },
            ']' => blk: {
                lexer.position += 1;
                break :blk .right_bracket;
            },
            ',' => blk: {
                lexer.position += 1;
                break :blk .comma;
            },
            ':' => blk: {
                lexer.position += 1;
                break :blk .colon;
            },
            else => null,
        };
        
        if (token_kind) |kind| {
            return Token{
                .span = Span.init(@intCast(start), @intCast(lexer.position)),
                .kind = kind,
                .depth = 0, // TODO: Track nesting depth
                .flags = .{},
            };
        }
        
        // String
        if (c == '"') {
            lexer.position += 1; // Skip opening quote
            while (lexer.position < lexer.source.len) {
                const ch = lexer.source[lexer.position];
                lexer.position += 1;
                if (ch == '"') break;
                if (ch == '\\' and lexer.position < lexer.source.len) {
                    lexer.position += 1; // Skip escaped character
                }
            }
            
            return Token{
                .span = Span.init(@intCast(start), @intCast(lexer.position)),
                .kind = .string,
                .depth = 0,
                .flags = .{ .has_escapes = std.mem.indexOfScalar(u8, lexer.source[start..lexer.position], '\\') != null },
            };
        }
        
        // Number
        if (char.isDigit(c) or c == '-') {
            lexer.position += 1;
            while (lexer.position < lexer.source.len) {
                const ch = lexer.source[lexer.position];
                if (!char.isDigit(ch) and ch != '.' and ch != 'e' and ch != 'E' and ch != '+' and ch != '-') {
                    break;
                }
                lexer.position += 1;
            }
            
            return Token{
                .span = Span.init(@intCast(start), @intCast(lexer.position)),
                .kind = .number,
                .depth = 0,
                .flags = .{},
            };
        }
        
        // Keywords: true, false, null
        if (char.isAlpha(c)) {
            while (lexer.position < lexer.source.len and char.isAlpha(lexer.source[lexer.position])) {
                lexer.position += 1;
            }
            
            const text = lexer.source[start..lexer.position];
            const kind: TokenKind = if (std.mem.eql(u8, text, "true") or std.mem.eql(u8, text, "false"))
                .boolean
            else if (std.mem.eql(u8, text, "null"))
                .null
            else
                .identifier;
            
            return Token{
                .span = Span.init(@intCast(start), @intCast(lexer.position)),
                .kind = kind,
                .depth = 0,
                .flags = .{},
            };
        }
        
        // Unknown character
        lexer.position += 1;
        return Token{
            .span = Span.init(@intCast(start), @intCast(lexer.position)),
            .kind = .unknown,
            .depth = 0,
            .flags = .{},
        };
    }
    
    pub fn reset(self: *Self) void {
        self.lexer.position = 0;
    }
};

// Tests
const testing = std.testing;

test "JsonLexer - basic object" {
    var lexer = JsonLexer.init(testing.allocator);
    defer lexer.deinit();
    
    const source = "{\"key\": \"value\"}";
    const tokens = try lexer.batchTokenize(testing.allocator, source);
    defer testing.allocator.free(tokens);
    
    try testing.expect(tokens.len >= 5);
    try testing.expect(tokens[0].kind == .left_brace);
    try testing.expect(tokens[1].kind == .string);
    try testing.expect(tokens[2].kind == .colon);
    try testing.expect(tokens[3].kind == .string);
    try testing.expect(tokens[4].kind == .right_brace);
}

test "JsonLexer - array" {
    var lexer = JsonLexer.init(testing.allocator);
    defer lexer.deinit();
    
    const source = "[1, 2, 3]";
    const tokens = try lexer.batchTokenize(testing.allocator, source);
    defer testing.allocator.free(tokens);
    
    try testing.expect(tokens[0].kind == .left_bracket);
    try testing.expect(tokens[1].kind == .number);
    try testing.expect(tokens[2].kind == .comma);
    try testing.expect(tokens[3].kind == .number);
}

test "JsonLexer - keywords" {
    var lexer = JsonLexer.init(testing.allocator);
    defer lexer.deinit();
    
    const source = "[true, false, null]";
    const tokens = try lexer.batchTokenize(testing.allocator, source);
    defer testing.allocator.free(tokens);
    
    try testing.expect(tokens[1].kind == .boolean);
    try testing.expect(tokens[3].kind == .boolean);
    try testing.expect(tokens[5].kind == .null);
}

test "JsonLexer - streaming" {
    var lexer = JsonLexer.init(testing.allocator);
    defer lexer.deinit();
    
    const source = "{}";
    var stream = lexer.streamTokens(source);
    
    const token1 = stream.next();
    try testing.expect(token1.?.kind == .left_brace);
    
    const token2 = stream.next();
    try testing.expect(token2.?.kind == .right_brace);
    
    const token3 = stream.next();
    try testing.expect(token3.?.kind == .eof);
}