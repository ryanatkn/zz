const std = @import("std");

/// Language detection and mapping for all known languages
/// Currently only JSON and ZON are fully implemented
pub const Language = enum {
    zig,
    css,
    html,
    json,
    typescript,
    svelte,
    zon,
    unknown,

    // TODO: Languages other than JSON/ZON are not yet implemented
    // To implement a language:
    // 1. Create directory in src/lib/languages/<lang>/
    // 2. Implement: lexer.zig, parser.zig, ast.zig, formatter.zig, linter.zig
    // 3. Define language-specific RuleType enum for linter (enum(u8), max 256 rules)
    // 4. Export getSupport() function returning LanguageSupport(AST, RuleType)
    // 5. Register in languages/registry.zig getSupport() and getSupportedLanguages()

    pub fn fromExtension(ext: []const u8) Language {
        if (std.mem.eql(u8, ext, ".zig")) return .zig;
        if (std.mem.eql(u8, ext, ".css")) return .css;
        if (std.mem.eql(u8, ext, ".html") or std.mem.eql(u8, ext, ".htm")) return .html;
        if (std.mem.eql(u8, ext, ".json")) return .json;
        if (std.mem.eql(u8, ext, ".ts") or std.mem.eql(u8, ext, ".js")) return .typescript;
        if (std.mem.eql(u8, ext, ".svelte")) return .svelte;
        if (std.mem.eql(u8, ext, ".zon")) return .zon;
        return .unknown;
    }

    /// Detect language from file path
    pub fn fromPath(file_path: []const u8) Language {
        const ext = std.fs.path.extension(file_path);
        return fromExtension(ext);
    }

    pub fn toString(self: Language) []const u8 {
        return switch (self) {
            .zig => "zig",
            .css => "css",
            .html => "html",
            .json => "json",
            .typescript => "typescript",
            .svelte => "svelte",
            .zon => "zon",
            .unknown => "unknown",
        };
    }

    /// Get file extensions for this language
    pub fn getExtensions(self: Language) []const []const u8 {
        return switch (self) {
            .zig => &.{".zig"},
            .css => &.{".css"},
            .html => &.{ ".html", ".htm" },
            .json => &.{".json"},
            .typescript => &.{ ".ts", ".js" },
            .svelte => &.{".svelte"},
            .zon => &.{".zon"},
            .unknown => &.{},
        };
    }

    /// Check if this language supports formatting
    pub fn supportsFormatting(self: Language) bool {
        return switch (self) {
            .json, .zon => true,
            .zig, .css, .html, .typescript, .svelte => false, // Not yet implemented
            .unknown => false,
        };
    }

    /// Check if this language supports linting
    pub fn supportsLinting(self: Language) bool {
        return switch (self) {
            .json, .zon => true,
            .zig, .css, .html, .typescript, .svelte => false, // Not yet implemented
            .unknown => false,
        };
    }
};

/// Detect language from file path (convenience function)
pub fn detectLanguage(path: []const u8) Language {
    return Language.fromPath(path);
}

/// Check if a file extension is supported
pub fn isSupportedExtension(ext: []const u8) bool {
    return Language.fromExtension(ext) != .unknown;
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "language detection from extension" {
    try testing.expectEqual(Language.zig, Language.fromExtension(".zig"));
    try testing.expectEqual(Language.json, Language.fromExtension(".json"));
    try testing.expectEqual(Language.typescript, Language.fromExtension(".ts"));
    try testing.expectEqual(Language.typescript, Language.fromExtension(".js"));
    try testing.expectEqual(Language.html, Language.fromExtension(".html"));
    try testing.expectEqual(Language.html, Language.fromExtension(".htm"));
    try testing.expectEqual(Language.zon, Language.fromExtension(".zon"));
    try testing.expectEqual(Language.unknown, Language.fromExtension(".xyz"));
}

test "language detection from path" {
    try testing.expectEqual(Language.zig, Language.fromPath("src/main.zig"));
    try testing.expectEqual(Language.json, Language.fromPath("package.json"));
    try testing.expectEqual(Language.typescript, Language.fromPath("src/app.ts"));
    try testing.expectEqual(Language.zon, Language.fromPath("build.zig.zon"));
    try testing.expectEqual(Language.unknown, Language.fromPath("README.md"));
}

test "language string conversion" {
    try testing.expectEqualStrings("zig", Language.zig.toString());
    try testing.expectEqualStrings("json", Language.json.toString());
    try testing.expectEqualStrings("zon", Language.zon.toString());
    try testing.expectEqualStrings("unknown", Language.unknown.toString());
}

test "language capabilities" {
    try testing.expect(Language.json.supportsFormatting());
    try testing.expect(Language.zon.supportsLinting());
    try testing.expect(!Language.unknown.supportsFormatting());
}

test "supported extensions" {
    try testing.expect(isSupportedExtension(".zig"));
    try testing.expect(isSupportedExtension(".json"));
    try testing.expect(isSupportedExtension(".zon"));
    try testing.expect(!isSupportedExtension(".md"));
}
