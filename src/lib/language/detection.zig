const std = @import("std");

/// Language detection and mapping for core supported languages
pub const Language = enum {
    zig,
    css,
    html,
    json,
    typescript,
    svelte,
    zon,
    unknown,

    pub fn fromExtension(ext: []const u8) Language {
        if (std.mem.eql(u8, ext, ".zig")) return .zig;
        if (std.mem.eql(u8, ext, ".css")) return .css;
        if (std.mem.eql(u8, ext, ".html") or std.mem.eql(u8, ext, ".htm")) return .html;
        if (std.mem.eql(u8, ext, ".json")) return .json;
        if (std.mem.eql(u8, ext, ".ts")) return .typescript;
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
};

/// Detect language from file path
pub fn detectLanguage(path: []const u8) Language {
    const ext = std.fs.path.extension(path);
    return Language.fromExtension(ext);
}

test "language detection" {
    const testing = std.testing;

    try testing.expect(detectLanguage("test.zig") == .zig);
    try testing.expect(detectLanguage("style.css") == .css);
    try testing.expect(detectLanguage("index.html") == .html);
    try testing.expect(detectLanguage("data.json") == .json);
    try testing.expect(detectLanguage("app.ts") == .typescript);
    try testing.expect(detectLanguage("component.svelte") == .svelte);
    try testing.expect(detectLanguage("deps.zon") == .zon);
    try testing.expect(detectLanguage("unknown.xyz") == .unknown);
}
