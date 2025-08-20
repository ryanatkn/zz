const std = @import("std");
const Token = @import("../../parser/foundation/types/token.zig").Token;
const Language = @import("../../core/language.zig").Language;
const LanguageRegistry = @import("../../languages/registry.zig").LanguageRegistry;
const LanguageSupport = @import("../../languages/interface.zig").LanguageSupport;
const Lexer = @import("../../languages/interface.zig").Lexer;

/// Generic lexer dispatch that uses LanguageRegistry to tokenize chunks
/// without knowing specific language implementations.
///
/// This eliminates hardcoded language dependencies in the transform layer
/// while maintaining performance through efficient dispatch.
pub const LexerDispatch = struct {
    allocator: std.mem.Allocator,
    language: Language,
    registry: *LanguageRegistry,
    cached_lexer: ?Lexer = null,

    const Self = @This();

    /// Initialize with language and registry
    pub fn init(allocator: std.mem.Allocator, language: Language, registry: *LanguageRegistry) Self {
        return Self{
            .allocator = allocator,
            .language = language,
            .registry = registry,
            .cached_lexer = null,
        };
    }

    /// Get lexer for this dispatch, caching the result
    fn getLexer(self: *Self) !Lexer {
        if (self.cached_lexer) |lexer| {
            return lexer;
        }

        const support = try self.registry.getSupport(self.language);
        self.cached_lexer = support.lexer;
        return support.lexer;
    }

    /// Tokenize a chunk of input generically
    /// This is the core method that transforms the hardcoded language switching
    /// into generic dispatch via the LanguageRegistry
    pub fn tokenizeChunk(self: *Self, input: []const u8, start_pos: usize) ![]Token {
        const lexer = try self.getLexer();
        return lexer.tokenizeChunk(self.allocator, input, start_pos);
    }

    /// Tokenize full input (convenience method)
    pub fn tokenize(self: *Self, input: []const u8) ![]Token {
        const lexer = try self.getLexer();
        return lexer.tokenize(self.allocator, input);
    }

    /// Check if language is supported for streaming
    pub fn isStreamingSupported(self: *Self) bool {
        return self.registry.isLanguageSupported(self.language);
    }

    /// Get language identifier
    pub fn getLanguage(self: *Self) Language {
        return self.language;
    }

    /// Create dispatch for detected language
    pub fn fromLanguage(allocator: std.mem.Allocator, language: Language, registry: *LanguageRegistry) !Self {
        if (!registry.isLanguageSupported(language)) {
            return error.UnsupportedLanguage;
        }
        return init(allocator, language, registry);
    }

    /// Create dispatch from file extension
    pub fn fromExtension(allocator: std.mem.Allocator, extension: []const u8, registry: *LanguageRegistry) !Self {
        const language = Language.fromExtension(extension);
        return fromLanguage(allocator, language, registry);
    }

    /// Create dispatch from file path
    pub fn fromPath(allocator: std.mem.Allocator, path: []const u8, registry: *LanguageRegistry) !Self {
        const language = Language.fromPath(path);
        return fromLanguage(allocator, language, registry);
    }

    /// Detect language from content and create dispatch
    pub fn fromContent(allocator: std.mem.Allocator, content: []const u8, registry: *LanguageRegistry) !Self {
        const language = detectLanguageFromContent(content);
        return fromLanguage(allocator, language, registry);
    }
};

/// Simple content-based language detection
/// This replaces the hardcoded detection logic from TokenIterator
fn detectLanguageFromContent(content: []const u8) Language {
    const trimmed = std.mem.trim(u8, content, " \t\n\r");

    // JSON detection
    if (std.mem.startsWith(u8, trimmed, "{") or std.mem.startsWith(u8, trimmed, "[")) {
        return .json;
    }

    // ZON detection
    if (std.mem.startsWith(u8, trimmed, ".{")) {
        return .zon;
    }

    // TypeScript/JS detection
    if (std.mem.indexOf(u8, trimmed, "function") != null or
        std.mem.indexOf(u8, trimmed, "const") != null or
        std.mem.indexOf(u8, trimmed, "let") != null or
        std.mem.indexOf(u8, trimmed, "var") != null)
    {
        return .typescript;
    }

    // CSS detection
    if (std.mem.indexOf(u8, trimmed, "{") != null and
        std.mem.indexOf(u8, trimmed, ":") != null and
        std.mem.indexOf(u8, trimmed, ";") != null)
    {
        return .css;
    }

    // HTML detection
    if (std.mem.startsWith(u8, trimmed, "<") and std.mem.indexOf(u8, trimmed, ">") != null) {
        return .html;
    }

    return .unknown;
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "LexerDispatch - initialization" {
    var registry = LanguageRegistry.init(testing.allocator);
    defer registry.deinit();

    var dispatch = LexerDispatch.init(testing.allocator, .json, &registry);
    try testing.expectEqual(Language.json, dispatch.getLanguage());
    try testing.expect(dispatch.isStreamingSupported());
}

test "LexerDispatch - language detection from content" {
    try testing.expectEqual(Language.json, detectLanguageFromContent("{ \"key\": \"value\" }"));
    try testing.expectEqual(Language.zon, detectLanguageFromContent(".{ key = \"value\" }"));
    try testing.expectEqual(Language.typescript, detectLanguageFromContent("function test() {}"));
    try testing.expectEqual(Language.css, detectLanguageFromContent("body { color: red; }"));
    try testing.expectEqual(Language.html, detectLanguageFromContent("<html><body></body></html>"));
    try testing.expectEqual(Language.unknown, detectLanguageFromContent("random text"));
}

test "LexerDispatch - factory methods" {
    var registry = LanguageRegistry.init(testing.allocator);
    defer registry.deinit();

    // From extension
    var dispatch = try LexerDispatch.fromExtension(testing.allocator, ".json", &registry);
    try testing.expectEqual(Language.json, dispatch.getLanguage());

    // From path
    dispatch = try LexerDispatch.fromPath(testing.allocator, "config.json", &registry);
    try testing.expectEqual(Language.json, dispatch.getLanguage());

    // From content
    dispatch = try LexerDispatch.fromContent(testing.allocator, "{ \"test\": true }", &registry);
    try testing.expectEqual(Language.json, dispatch.getLanguage());
}
