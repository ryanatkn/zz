/// Lexer Registry - Centralized language lexer type management
/// SIMPLIFIED: Just a union for dispatch, no abstractions
/// Companion to token_registry.zig for lexer types
///
/// Design principles:
/// - All language lexer imports contained here
/// - Clean tagged union for optimal dispatch
/// - No methods, just data and factory function
const std = @import("std");
const Token = @import("token_registry.zig").Token;
const Language = @import("../core/language.zig").Language;

// Import all language lexers
const JsonLexer = @import("json/lexer/mod.zig").Lexer;
const ZonLexer = @import("zon/stream_lexer.zig").ZonLexer;

// Future language imports:
// const TsLexer = @import("typescript/stream_lexer.zig").TsLexer;
// const ZigLexer = @import("zig/stream_lexer.zig").ZigLexer;
// const CssLexer = @import("css/stream_lexer.zig").CssLexer;
// const HtmlLexer = @import("html/stream_lexer.zig").HtmlLexer;
// const SvelteLexer = @import("svelte/stream_lexer.zig").SvelteLexer;

/// Universal lexer type - tagged union of all language lexers
/// SIMPLIFIED: No methods. Users call lexer.json.next() directly
pub const LanguageLexer = union(enum) {
    json: JsonLexer,
    zon: ZonLexer,
    // typescript: TsLexer,
    // zig: ZigLexer,
    // css: CssLexer,
    // html: HtmlLexer,
    // svelte: SvelteLexer,

    // That's it! No methods. Users access lexers directly:
    // switch (lexer) {
    //     .json => |*l| l.next(),
    //     .zon => |*l| l.next(),
    // }
};

/// Create a lexer for the given language and source
pub fn createLexer(source: []const u8, language: Language) !LanguageLexer {
    return switch (language) {
        .json => .{ .json = JsonLexer.init(source) },
        .zon => .{ .zon = ZonLexer.init(source) },
        // When we add more languages:
        // .typescript => .{ .typescript = TsLexer.init(source) },
        // .zig => .{ .zig = ZigLexer.init(source) },
        // .css => .{ .css = CssLexer.init(source) },
        // .html => .{ .html = HtmlLexer.init(source) },
        // .svelte => .{ .svelte = SvelteLexer.init(source) },
        else => error.UnsupportedLanguage,
    };
}
