/// Lexer Registry - Centralized language lexer type management
/// SIMPLIFIED: Just a union for dispatch, no abstractions
/// Companion to token_registry.zig for lexer types
///
/// Design principles:
/// - All language lexer imports contained here
/// - Clean tagged union for optimal dispatch
/// - No methods, just data and factory function
const std = @import("std");
const StreamToken = @import("token_registry.zig").StreamToken;
const Language = @import("../core/language.zig").Language;

// Import all language lexers
const JsonStreamLexer = @import("json/stream_lexer.zig").JsonStreamLexer;
const ZonStreamLexer = @import("zon/stream_lexer.zig").ZonStreamLexer;

// Future language imports:
// const TsStreamLexer = @import("typescript/stream_lexer.zig").TsStreamLexer;
// const ZigStreamLexer = @import("zig/stream_lexer.zig").ZigStreamLexer;
// const CssStreamLexer = @import("css/stream_lexer.zig").CssStreamLexer;
// const HtmlStreamLexer = @import("html/stream_lexer.zig").HtmlStreamLexer;
// const SvelteStreamLexer = @import("svelte/stream_lexer.zig").SvelteStreamLexer;

/// Universal lexer type - tagged union of all language lexers
/// SIMPLIFIED: No methods. Users call lexer.json.next() directly
pub const LanguageLexer = union(enum) {
    json: JsonStreamLexer,
    zon: ZonStreamLexer,
    // typescript: TsStreamLexer,
    // zig: ZigStreamLexer,
    // css: CssStreamLexer,
    // html: HtmlStreamLexer,
    // svelte: SvelteStreamLexer,

    // That's it! No methods. Users access lexers directly:
    // switch (lexer) {
    //     .json => |*l| l.next(),
    //     .zon => |*l| l.next(),
    // }
};

/// Create a lexer for the given language and source
pub fn createLexer(source: []const u8, language: Language) !LanguageLexer {
    return switch (language) {
        .json => .{ .json = JsonStreamLexer.init(source) },
        .zon => .{ .zon = ZonStreamLexer.init(source) },
        // When we add more languages:
        // .typescript => .{ .typescript = TsStreamLexer.init(source) },
        // .zig => .{ .zig = ZigStreamLexer.init(source) },
        // .css => .{ .css = CssStreamLexer.init(source) },
        // .html => .{ .html = HtmlStreamLexer.init(source) },
        // .svelte => .{ .svelte = SvelteStreamLexer.init(source) },
        else => error.UnsupportedLanguage,
    };
}
