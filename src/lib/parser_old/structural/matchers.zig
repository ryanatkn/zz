const std = @import("std");
const Token = @import("../lexical/mod.zig").Token;
const TokenKind = @import("../lexical/mod.zig").TokenKind;
const Language = @import("../lexical/mod.zig").Language;
const BoundaryKind = @import("../foundation/types/predicate.zig").BoundaryKind;
const Span = @import("../foundation/types/span.zig").Span;

/// Language-specific pattern matchers for boundary detection
pub const LanguageMatchers = struct {
    /// Current language
    language: Language,

    pub fn init(language: Language) LanguageMatchers {
        return .{
            .language = language,
        };
    }

    /// Check if token indicates a potential boundary start
    pub fn isBoundaryStart(self: LanguageMatchers, token: Token) bool {
        return switch (self.language) {
            .zig => ZigMatcher.isBoundaryStart(token),
            .typescript => TypeScriptMatcher.isBoundaryStart(token),
            .json => JSONMatcher.isBoundaryStart(token),
            else => GenericMatcher.isBoundaryStart(token),
        };
    }

    /// Get boundary kind for a token
    pub fn getBoundaryKind(self: LanguageMatchers, token: Token) ?BoundaryKind {
        return switch (self.language) {
            .zig => ZigMatcher.getBoundaryKind(token),
            .typescript => TypeScriptMatcher.getBoundaryKind(token),
            .json => JSONMatcher.getBoundaryKind(token),
            else => GenericMatcher.getBoundaryKind(token),
        };
    }

    /// Get confidence level for boundary detection
    pub fn getBoundaryConfidence(
        self: LanguageMatchers,
        tokens: []const Token,
        start_idx: usize,
        kind: BoundaryKind,
    ) f32 {
        return switch (self.language) {
            .zig => ZigMatcher.getBoundaryConfidence(tokens, start_idx, kind),
            .typescript => TypeScriptMatcher.getBoundaryConfidence(tokens, start_idx, kind),
            .json => JSONMatcher.getBoundaryConfidence(tokens, start_idx, kind),
            else => GenericMatcher.getBoundaryConfidence(tokens, start_idx, kind),
        };
    }
};

/// Zig-specific pattern matcher
pub const ZigMatcher = struct {
    /// Check if token indicates boundary start
    pub fn isBoundaryStart(token: Token) bool {
        if (token.kind != .keyword) return false;

        return std.mem.eql(u8, token.text, "fn") or
            std.mem.eql(u8, token.text, "struct") or
            std.mem.eql(u8, token.text, "enum") or
            std.mem.eql(u8, token.text, "union") or
            std.mem.eql(u8, token.text, "test") or
            std.mem.eql(u8, token.text, "pub");
    }

    /// Get boundary kind for token
    pub fn getBoundaryKind(token: Token) ?BoundaryKind {
        if (token.kind != .keyword) return null;

        if (std.mem.eql(u8, token.text, "fn")) return .function;
        if (std.mem.eql(u8, token.text, "struct")) return .struct_;
        if (std.mem.eql(u8, token.text, "enum")) return .enum_;
        if (std.mem.eql(u8, token.text, "union")) return .struct_; // Treat union as struct-like
        if (std.mem.eql(u8, token.text, "test")) return .function; // Test is function-like

        return null;
    }

    /// Get confidence for boundary detection
    pub fn getBoundaryConfidence(
        tokens: []const Token,
        start_idx: usize,
        kind: BoundaryKind,
    ) f32 {
        if (start_idx >= tokens.len) return 0.0;

        const start_token = tokens[start_idx];
        var confidence: f32 = 0.5; // Base confidence

        // Higher confidence for exact keyword matches
        switch (kind) {
            .function => {
                if (std.mem.eql(u8, start_token.text, "fn")) {
                    confidence = 0.95;
                } else if (std.mem.eql(u8, start_token.text, "test")) {
                    confidence = 0.9;
                }
            },
            .struct_ => {
                if (std.mem.eql(u8, start_token.text, "struct")) {
                    confidence = 0.95;
                } else if (std.mem.eql(u8, start_token.text, "union")) {
                    confidence = 0.9;
                }
            },
            .enum_ => {
                if (std.mem.eql(u8, start_token.text, "enum")) {
                    confidence = 0.95;
                }
            },
            else => {},
        }

        // Look ahead for confirmation patterns
        confidence += analyzeZigLookahead(tokens, start_idx, kind);

        return @min(confidence, 1.0);
    }

    /// Check if this looks like a function signature
    pub fn isLikelyFunction(tokens: []const Token, start_idx: usize) bool {
        if (start_idx + 2 >= tokens.len) return false;

        // Pattern: [pub] fn name(...) [return_type] {
        var idx = start_idx;

        // Skip "pub" if present
        if (std.mem.eql(u8, tokens[idx].text, "pub")) {
            idx += 1;
            if (idx >= tokens.len) return false;
        }

        // Expect "fn"
        if (!std.mem.eql(u8, tokens[idx].text, "fn")) return false;
        idx += 1;
        if (idx >= tokens.len) return false;

        // Expect identifier (function name)
        if (tokens[idx].kind != .identifier) return false;
        idx += 1;
        if (idx >= tokens.len) return false;

        // Expect opening parenthesis
        if (tokens[idx].kind != .delimiter or !std.mem.eql(u8, tokens[idx].text, "(")) return false;

        return true;
    }

    /// Check if this looks like a struct definition
    pub fn isLikelyStruct(tokens: []const Token, start_idx: usize) bool {
        if (start_idx + 2 >= tokens.len) return false;

        var idx = start_idx;

        // Skip "pub" if present
        if (std.mem.eql(u8, tokens[idx].text, "pub")) {
            idx += 1;
            if (idx >= tokens.len) return false;
        }

        // Expect "struct"
        if (!std.mem.eql(u8, tokens[idx].text, "struct")) return false;
        idx += 1;
        if (idx >= tokens.len) return false;

        // Can have optional name, then {
        // Look ahead for opening brace within reasonable distance
        for (tokens[idx..@min(idx + 5, tokens.len)]) |token| {
            if (token.kind == .delimiter and std.mem.eql(u8, token.text, "{")) {
                return true;
            }
        }

        return false;
    }

    /// Analyze lookahead for Zig patterns
    fn analyzeZigLookahead(tokens: []const Token, start_idx: usize, kind: BoundaryKind) f32 {
        _ = kind; // For now, generic lookahead

        var confidence_boost: f32 = 0.0;
        const lookahead_limit = @min(start_idx + 10, tokens.len);

        for (tokens[start_idx..lookahead_limit]) |token| {
            switch (token.kind) {
                .delimiter => {
                    if (std.mem.eql(u8, token.text, "(")) {
                        confidence_boost += 0.1; // Parameter list
                    } else if (std.mem.eql(u8, token.text, "{")) {
                        confidence_boost += 0.2; // Body start
                        break; // Found body, stop looking
                    }
                },
                .operator => {
                    if (std.mem.eql(u8, token.text, "->")) {
                        confidence_boost += 0.1; // Return type indicator
                    }
                },
                .keyword => {
                    if (std.mem.eql(u8, token.text, "pub")) {
                        confidence_boost += 0.05; // Visibility modifier
                    }
                },
                else => {},
            }
        }

        return confidence_boost;
    }
};

/// TypeScript pattern matcher
pub const TypeScriptMatcher = struct {
    /// Check if token indicates boundary start
    pub fn isBoundaryStart(token: Token) bool {
        if (token.kind != .keyword) return false;

        return std.mem.eql(u8, token.text, "function") or
            std.mem.eql(u8, token.text, "class") or
            std.mem.eql(u8, token.text, "interface") or
            std.mem.eql(u8, token.text, "namespace") or
            std.mem.eql(u8, token.text, "module") or
            std.mem.eql(u8, token.text, "export") or
            std.mem.eql(u8, token.text, "declare");
    }

    /// Get boundary kind for token
    pub fn getBoundaryKind(token: Token) ?BoundaryKind {
        if (token.kind != .keyword) return null;

        if (std.mem.eql(u8, token.text, "function")) return .function;
        if (std.mem.eql(u8, token.text, "class")) return .class;
        if (std.mem.eql(u8, token.text, "interface")) return .class; // Interface is class-like
        if (std.mem.eql(u8, token.text, "namespace")) return .namespace;
        if (std.mem.eql(u8, token.text, "module")) return .module;

        return null;
    }

    /// Get confidence for boundary detection
    pub fn getBoundaryConfidence(
        tokens: []const Token,
        start_idx: usize,
        kind: BoundaryKind,
    ) f32 {
        if (start_idx >= tokens.len) return 0.0;

        const start_token = tokens[start_idx];
        var confidence: f32 = 0.5;

        // Higher confidence for exact matches
        switch (kind) {
            .function => {
                if (std.mem.eql(u8, start_token.text, "function")) {
                    confidence = 0.9;
                }
            },
            .class => {
                if (std.mem.eql(u8, start_token.text, "class")) {
                    confidence = 0.95;
                } else if (std.mem.eql(u8, start_token.text, "interface")) {
                    confidence = 0.9;
                }
            },
            .namespace => {
                if (std.mem.eql(u8, start_token.text, "namespace")) {
                    confidence = 0.95;
                }
            },
            .module => {
                if (std.mem.eql(u8, start_token.text, "module")) {
                    confidence = 0.9;
                }
            },
            else => {},
        }

        // Look ahead for TypeScript patterns
        confidence += analyzeTypeScriptLookahead(tokens, start_idx, kind);

        return @min(confidence, 1.0);
    }

    /// Analyze TypeScript-specific lookahead patterns
    fn analyzeTypeScriptLookahead(tokens: []const Token, start_idx: usize, kind: BoundaryKind) f32 {
        _ = kind;

        var confidence_boost: f32 = 0.0;
        const lookahead_limit = @min(start_idx + 8, tokens.len);

        for (tokens[start_idx..lookahead_limit]) |token| {
            switch (token.kind) {
                .delimiter => {
                    if (std.mem.eql(u8, token.text, "(")) {
                        confidence_boost += 0.1; // Parameter list
                    } else if (std.mem.eql(u8, token.text, "{")) {
                        confidence_boost += 0.15; // Body start
                        break;
                    }
                },
                .operator => {
                    if (std.mem.eql(u8, token.text, ":")) {
                        confidence_boost += 0.05; // Type annotation
                    } else if (std.mem.eql(u8, token.text, "=>")) {
                        confidence_boost += 0.1; // Arrow function
                    }
                },
                .keyword => {
                    if (std.mem.eql(u8, token.text, "export")) {
                        confidence_boost += 0.05;
                    }
                },
                else => {},
            }
        }

        return confidence_boost;
    }
};

/// JSON pattern matcher (simple)
pub const JSONMatcher = struct {
    /// Check if token indicates boundary start
    pub fn isBoundaryStart(token: Token) bool {
        return token.kind == .delimiter and std.mem.eql(u8, token.text, "{");
    }

    /// Get boundary kind for token
    pub fn getBoundaryKind(token: Token) ?BoundaryKind {
        if (token.kind == .delimiter and std.mem.eql(u8, token.text, "{")) {
            return .block;
        }
        return null;
    }

    /// Get confidence for boundary detection
    pub fn getBoundaryConfidence(
        tokens: []const Token,
        start_idx: usize,
        kind: BoundaryKind,
    ) f32 {
        _ = tokens;
        _ = start_idx;

        return switch (kind) {
            .block => 0.95, // JSON objects are very clear
            else => 0.0,
        };
    }
};

/// Generic pattern matcher for unknown languages
pub const GenericMatcher = struct {
    /// Check if token indicates boundary start
    pub fn isBoundaryStart(token: Token) bool {
        // Generic: look for opening braces
        return token.kind == .delimiter and
            (std.mem.eql(u8, token.text, "{") or std.mem.eql(u8, token.text, "("));
    }

    /// Get boundary kind for token
    pub fn getBoundaryKind(token: Token) ?BoundaryKind {
        if (token.kind == .delimiter) {
            if (std.mem.eql(u8, token.text, "{")) {
                return .block;
            }
        }
        return null;
    }

    /// Get confidence for boundary detection
    pub fn getBoundaryConfidence(
        tokens: []const Token,
        start_idx: usize,
        kind: BoundaryKind,
    ) f32 {
        _ = tokens;
        _ = start_idx;

        return switch (kind) {
            .block => 0.6, // Lower confidence for generic matching
            else => 0.3,
        };
    }
};

// ============================================================================
// Utility Functions
// ============================================================================

/// Check if a sequence of tokens matches a specific pattern
pub fn matchTokenSequence(
    tokens: []const Token,
    start_idx: usize,
    pattern: []const TokenKind,
    literals: []const []const u8,
) bool {
    if (start_idx + pattern.len > tokens.len) return false;
    if (pattern.len != literals.len) return false;

    for (pattern, literals, 0..) |expected_kind, expected_literal, i| {
        const token = tokens[start_idx + i];
        if (token.kind != expected_kind) return false;
        if (!std.mem.eql(u8, token.text, expected_literal)) return false;
    }

    return true;
}

/// Get the most likely boundary kind from multiple matchers
pub fn getBestBoundaryMatch(
    tokens: []const Token,
    start_idx: usize,
    language: Language,
) ?struct { kind: BoundaryKind, confidence: f32 } {
    const matchers = LanguageMatchers.init(language);

    if (!matchers.isBoundaryStart(tokens[start_idx])) return null;

    const kind = matchers.getBoundaryKind(tokens[start_idx]) orelse return null;
    const confidence = matchers.getBoundaryConfidence(tokens, start_idx, kind);

    return .{ .kind = kind, .confidence = confidence };
}

/// Analyze pattern complexity for performance optimization
pub fn analyzePatternComplexity(tokens: []const Token, start_idx: usize, max_lookahead: usize) u32 {
    var complexity: u32 = 1;
    const lookahead_limit = @min(start_idx + max_lookahead, tokens.len);

    for (tokens[start_idx..lookahead_limit]) |token| {
        switch (token.kind) {
            .keyword => complexity += 2,
            .identifier => complexity += 1,
            .delimiter => complexity += 3, // Delimiters are important for structure
            .operator => complexity += 1,
            else => {},
        }
    }

    return complexity;
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "zig matcher functions" {

    // Test function detection
    const fn_token = Token.simple(Span.init(0, 2), .keyword, "fn", 0);
    try testing.expect(ZigMatcher.isBoundaryStart(fn_token));
    try testing.expectEqual(BoundaryKind.function, ZigMatcher.getBoundaryKind(fn_token).?);

    // Test struct detection
    const struct_token = Token.simple(Span.init(0, 6), .keyword, "struct", 0);
    try testing.expect(ZigMatcher.isBoundaryStart(struct_token));
    try testing.expectEqual(BoundaryKind.struct_, ZigMatcher.getBoundaryKind(struct_token).?);
}

test "typescript matcher" {

    // Test function detection
    const fn_token = Token.simple(Span.init(0, 8), .keyword, "function", 0);
    try testing.expect(TypeScriptMatcher.isBoundaryStart(fn_token));
    try testing.expectEqual(BoundaryKind.function, TypeScriptMatcher.getBoundaryKind(fn_token).?);

    // Test class detection
    const class_token = Token.simple(Span.init(0, 5), .keyword, "class", 0);
    try testing.expect(TypeScriptMatcher.isBoundaryStart(class_token));
    try testing.expectEqual(BoundaryKind.class, TypeScriptMatcher.getBoundaryKind(class_token).?);
}

test "json matcher" {

    // Test object boundary
    const brace_token = Token.simple(Span.init(0, 1), .delimiter, "{", 1);
    try testing.expect(JSONMatcher.isBoundaryStart(brace_token));
    try testing.expectEqual(BoundaryKind.block, JSONMatcher.getBoundaryKind(brace_token).?);
}

test "language matchers integration" {

    // Test Zig integration
    const zig_matchers = LanguageMatchers.init(.zig);
    const fn_token = Token.simple(Span.init(0, 2), .keyword, "fn", 0);

    try testing.expect(zig_matchers.isBoundaryStart(fn_token));
    try testing.expectEqual(BoundaryKind.function, zig_matchers.getBoundaryKind(fn_token).?);

    // Test confidence calculation
    const tokens = [_]Token{
        fn_token,
        Token.simple(Span.init(3, 7), .identifier, "test", 0),
        Token.simple(Span.init(7, 8), .delimiter, "(", 1),
    };

    const confidence = zig_matchers.getBoundaryConfidence(&tokens, 0, .function);
    try testing.expect(confidence > 0.9); // Should be high confidence
}

test "pattern complexity analysis" {
    const tokens = [_]Token{
        Token.simple(Span.init(0, 2), .keyword, "fn", 0),
        Token.simple(Span.init(3, 7), .identifier, "test", 0),
        Token.simple(Span.init(7, 8), .delimiter, "(", 1),
        Token.simple(Span.init(8, 9), .delimiter, ")", 0),
        Token.simple(Span.init(10, 11), .delimiter, "{", 1),
    };

    const complexity = analyzePatternComplexity(&tokens, 0, 5);
    try testing.expect(complexity > 5); // Should reflect the complexity of the pattern
}
