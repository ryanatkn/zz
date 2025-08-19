# Language Module Template

**Created**: 2025-08-19  
**Purpose**: Standard structure and requirements for implementing new language support in zz

## Overview

This template provides the standard directory structure and implementation requirements for adding new language support. Following this template ensures consistency across all language modules and proper integration with the zz tooling ecosystem.

## Directory Structure

```
src/lib/languages/LANGUAGE_NAME/
├── mod.zig              # Required: Module exports and LanguageSupport implementation
├── lexer.zig            # Required: Tokenization implementation
├── parser.zig           # Required: AST parsing implementation
├── patterns.zig         # Optional: Language-specific pattern matching
├── formatter.zig        # Optional: Code formatting implementation  
├── linter.zig           # Optional: Code linting rules
├── analyzer.zig         # Optional: Semantic analysis
├── transform.zig        # Optional: Transform pipeline integration
├── test.zig             # Required: Comprehensive test suite
└── README.md            # Optional: Language-specific documentation
```

## Required Files

### 1. mod.zig - Module Exports

```zig
/// LANGUAGE_NAME language support for zz
const std = @import("std");

// Core types
const Language = @import("../../core/language.zig").Language;
const LanguageSupport = @import("../interface.zig").LanguageSupport;

// Language components
pub const Lexer = @import("lexer.zig").LanguageNameLexer;
pub const Parser = @import("parser.zig").LanguageNameParser;
pub const Formatter = @import("formatter.zig").LanguageNameFormatter; // Optional
pub const Linter = @import("linter.zig").LanguageNameLinter;         // Optional

/// Create LanguageSupport instance for this language
pub fn createLanguageSupport(allocator: std.mem.Allocator) LanguageSupport {
    return LanguageSupport{
        .language = .LANGUAGE_NAME,
        .lexer = createLexerInterface(allocator),
        .parser = createParserInterface(allocator),
        .formatter = createFormatterInterface(allocator), // Optional
        .linter = createLinterInterface(allocator),       // Optional
    };
}

// Interface creation functions
fn createLexerInterface(allocator: std.mem.Allocator) @import("../interface.zig").Lexer {
    // Implementation details...
}

fn createParserInterface(allocator: std.mem.Allocator) @import("../interface.zig").Parser {
    // Implementation details...
}
```

### 2. lexer.zig - Tokenization Implementation

```zig
const std = @import("std");
const Token = @import("../../parser/foundation/types/token.zig").Token;
const TokenKind = @import("../../parser/foundation/types/predicate.zig").TokenKind;
const Span = @import("../../parser/foundation/types/span.zig").Span;
const char = @import("../../char/mod.zig");

pub const LanguageNameLexer = struct {
    allocator: std.mem.Allocator,
    input: []const u8,
    position: usize,
    tokens: std.ArrayList(Token),
    
    // Language-specific options
    pub const LexerOptions = struct {
        preserve_comments: bool = false,
        // Add language-specific options
    };

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, input: []const u8, options: LexerOptions) Self {
        return Self{
            .allocator = allocator,
            .input = input,
            .position = 0,
            .tokens = std.ArrayList(Token).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.tokens.deinit();
    }

    /// Main tokenization function - must emit tokens according to token contract
    pub fn tokenize(self: *Self) ![]Token {
        while (!self.isAtEnd()) {
            // Skip whitespace
            self.skipWhitespace();
            if (self.isAtEnd()) break;

            // Tokenize next token
            try self.tokenizeNext();
        }

        // REQUIRED: Add EOF token
        const eof_span = Span.init(self.input.len, self.input.len);
        const eof_token = Token.simple(eof_span, .eof, "", 0);
        try self.tokens.append(eof_token);

        return self.tokens.toOwnedSlice();
    }

    /// Required helper functions
    fn isAtEnd(self: Self) bool {
        return self.position >= self.input.len;
    }

    fn advance(self: *Self) u8 {
        if (self.isAtEnd()) return 0;
        const ch = self.input[self.position];
        self.position += 1;
        return ch;
    }

    fn peek(self: Self) u8 {
        if (self.isAtEnd()) return 0;
        return self.input[self.position];
    }

    fn skipWhitespace(self: *Self) void {
        while (!self.isAtEnd() and char.isWhitespace(self.peek())) {
            _ = self.advance();
        }
    }

    fn tokenizeNext(self: *Self) !void {
        // Language-specific tokenization logic
        // Must emit tokens using foundation TokenKind values only
        // See docs/token-contracts.md for requirements
    }

    fn addToken(self: *Self, kind: TokenKind, span: Span, text: []const u8) !void {
        const token = Token.simple(span, kind, text, 0);
        try self.tokens.append(token);
    }
};

/// Convenience function for simple tokenization
pub fn tokenize(allocator: std.mem.Allocator, source: []const u8) ![]Token {
    var lexer = LanguageNameLexer.init(allocator, source, .{});
    defer lexer.deinit();
    return lexer.tokenize();
}
```

### 3. parser.zig - AST Parsing Implementation

```zig
const std = @import("std");
const Token = @import("../../parser/foundation/types/token.zig").Token;
const TokenKind = @import("../../parser/foundation/types/predicate.zig").TokenKind;
const AST = @import("../../ast/mod.zig").AST;
const Node = @import("../../ast/node.zig").Node;

pub const LanguageNameParser = struct {
    allocator: std.mem.Allocator,
    tokens: []const Token,
    current: usize,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, tokens: []const Token) Self {
        return Self{
            .allocator = allocator,
            .tokens = tokens,
            .current = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
        // Cleanup if needed
    }

    /// Parse tokens into AST
    pub fn parse(self: *Self) !AST {
        const root_node = try self.parseRoot();
        return AST.init(self.allocator, root_node);
    }

    /// Required helper functions
    fn isAtEnd(self: Self) bool {
        return self.current >= self.tokens.len or self.peek().kind == .eof;
    }

    fn peek(self: Self) Token {
        if (self.current >= self.tokens.len) {
            return Token.simple(Span.init(0, 0), .eof, "", 0);
        }
        return self.tokens[self.current];
    }

    fn advance(self: *Self) Token {
        if (!self.isAtEnd()) {
            self.current += 1;
        }
        return self.previous();
    }

    fn previous(self: Self) Token {
        if (self.current > 0) {
            return self.tokens[self.current - 1];
        }
        return self.peek();
    }

    fn check(self: Self, kind: TokenKind) bool {
        return !self.isAtEnd() and self.peek().kind == kind;
    }

    fn match(self: *Self, kinds: []const TokenKind) bool {
        for (kinds) |kind| {
            if (self.check(kind)) {
                _ = self.advance();
                return true;
            }
        }
        return false;
    }

    /// Language-specific parsing methods
    fn parseRoot(self: *Self) !*Node {
        // Implement root parsing logic
    }
};

/// Convenience function for simple parsing
pub fn parse(allocator: std.mem.Allocator, tokens: []const Token) !AST {
    var parser = LanguageNameParser.init(allocator, tokens);
    defer parser.deinit();
    return parser.parse();
}
```

### 4. test.zig - Test Suite

```zig
const std = @import("std");
const testing = std.testing;
const Lexer = @import("lexer.zig").LanguageNameLexer;
const Parser = @import("parser.zig").LanguageNameParser;

// REQUIRED: Basic lexer tests
test "lexer - empty input" {
    var lexer = Lexer.init(testing.allocator, "", .{});
    defer lexer.deinit();

    const tokens = try lexer.tokenize();
    defer testing.allocator.free(tokens);

    try testing.expect(tokens.len == 1); // Only EOF token
    try testing.expect(tokens[0].kind == .eof);
}

test "lexer - single token of each type" {
    // Test each required TokenKind from contract
}

test "lexer - EOF token standard" {
    const input = "example";
    var lexer = Lexer.init(testing.allocator, input, .{});
    defer lexer.deinit();

    const tokens = try lexer.tokenize();
    defer testing.allocator.free(tokens);

    const eof_token = tokens[tokens.len - 1];
    try testing.expect(eof_token.kind == .eof);
    try testing.expect(eof_token.span.start == input.len);
    try testing.expect(eof_token.span.end == input.len);
    try testing.expect(eof_token.text.len == 0);
}

test "lexer - round trip" {
    const input = "example input";
    var lexer = Lexer.init(testing.allocator, input, .{});
    defer lexer.deinit();

    const tokens = try lexer.tokenize();
    defer testing.allocator.free(tokens);

    // Verify tokens cover entire input
    var reconstructed = std.ArrayList(u8).init(testing.allocator);
    defer reconstructed.deinit();

    for (tokens[0..tokens.len-1]) |token| { // Exclude EOF
        try reconstructed.appendSlice(token.text);
    }

    try testing.expectEqualStrings(input, reconstructed.items);
}

// REQUIRED: Basic parser tests
test "parser - empty input" {
    const tokens = &[_]Token{
        Token.simple(Span.init(0, 0), .eof, "", 0)
    };

    var parser = Parser.init(testing.allocator, tokens);
    defer parser.deinit();

    const ast = try parser.parse();
    defer ast.deinit();

    try testing.expect(ast.root != null);
}

test "parser - basic structure" {
    // Test parsing of basic language constructs
}

// REQUIRED: Integration tests
test "integration - lexer to parser" {
    const input = "example";
    
    var lexer = Lexer.init(testing.allocator, input, .{});
    defer lexer.deinit();

    const tokens = try lexer.tokenize();
    defer testing.allocator.free(tokens);

    var parser = Parser.init(testing.allocator, tokens);
    defer parser.deinit();

    const ast = try parser.parse();
    defer ast.deinit();

    try testing.expect(ast.root != null);
}

// REQUIRED: Performance tests
test "performance - 10KB tokenization under 10ms" {
    // Generate 10KB of valid language input
    const large_input = "..."; // TODO: Generate appropriate test data

    var timer = try std.time.Timer.start();
    var lexer = Lexer.init(testing.allocator, large_input, .{});
    defer lexer.deinit();

    const tokens = try lexer.tokenize();
    defer testing.allocator.free(tokens);

    const elapsed_ns = timer.read();
    const elapsed_ms = elapsed_ns / 1_000_000;

    try testing.expect(elapsed_ms < 10); // Must complete in under 10ms
}
```

## Optional Files

### patterns.zig - Language-Specific Patterns

```zig
/// Language-specific character and pattern matching utilities
const char = @import("../../char/mod.zig");

pub fn isIdentifierStart(ch: u8) bool {
    // Language-specific identifier rules
}

pub fn isIdentifierContinue(ch: u8) bool {
    // Language-specific identifier rules
}

pub fn isKeyword(text: []const u8) bool {
    // Language-specific keyword detection
}
```

### formatter.zig, linter.zig, analyzer.zig

Follow similar patterns with appropriate interfaces and test coverage.

## Implementation Checklist

**Phase 1: Core Implementation**
- [ ] Create directory structure
- [ ] Implement lexer.zig with token contract compliance
- [ ] Implement parser.zig with basic AST generation
- [ ] Write comprehensive test.zig
- [ ] Add mod.zig with proper exports

**Phase 2: Integration**
- [ ] Add to language registry
- [ ] Test with existing tooling (prompt, format, etc.)
- [ ] Verify streaming support via TokenIterator
- [ ] Add to build system tests

**Phase 3: Optional Features**
- [ ] Add formatter if needed
- [ ] Add linter rules if needed
- [ ] Add semantic analyzer if needed
- [ ] Add transform pipeline integration

## Testing Requirements

**All language implementations must:**
1. Pass token contract compliance tests
2. Complete 10KB tokenization in <10ms
3. Support round-trip (tokens → text = original)
4. Handle malformed input gracefully
5. Integrate with TokenIterator streaming
6. Pass all standard corpus tests

## Performance Targets

- **Lexer**: <10ms for 10KB input
- **Parser**: <50ms for 10KB input  
- **Memory**: <5MB peak for 100KB input
- **Streaming**: <100MB memory for 1GB input (via TokenIterator)

## Documentation

Each language should document:
- Supported syntax subset
- Known limitations
- Performance characteristics
- Configuration options
- Integration notes

---

**Note**: Following this template ensures your language implementation integrates seamlessly with zz's tooling ecosystem and maintains consistency with existing language modules.