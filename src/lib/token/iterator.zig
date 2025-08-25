/// TokenIterator - Generic streaming tokenization interface
/// SIMPLIFIED: Direct access to language lexers, no abstraction
/// Achieves 1-2 cycle dispatch, zero allocations
const std = @import("std");
const Token = @import("stream_token.zig").Token;
const Language = @import("../core/language.zig").Language;

// Import the centralized lexer registry
const lexer_registry = @import("../languages/lexer_registry.zig");
const LanguageLexer = lexer_registry.LanguageLexer;

/// Generic streaming token iterator
/// Zero-allocation design with direct dispatch
pub const TokenIterator = struct {
    lexer: LanguageLexer,

    const Self = @This();

    /// Initialize a token iterator for the given source and language
    pub fn init(source: []const u8, language: Language) !TokenIterator {
        return .{
            .lexer = try lexer_registry.createLexer(source, language),
        };
    }

    /// Initialize a token iterator with specific lexer options
    pub fn initWithOptions(source: []const u8, language: Language, options: lexer_registry.LexerOptions) !TokenIterator {
        return .{
            .lexer = try lexer_registry.createLexerWithOptions(source, language, options),
        };
    }

    /// Get the next token - now users must switch on lexer type
    /// This pushes language handling to the caller, as designed
    pub fn next(self: *Self) ?Token {
        return switch (self.lexer) {
            .json => |*l| l.next(),
            .zon => |*l| l.next(),
        };
    }

    /// Peek at the next token without consuming it
    /// Returns null if at end of stream
    pub fn peek(self: *Self) ?Token {
        return switch (self.lexer) {
            .json => |*l| l.peek(),
            .zon => |*l| l.peek(),
        };
    }

    // No reset or getPosition - let callers access lexer directly if needed:
    // iterator.lexer.json.reset() or similar
};
