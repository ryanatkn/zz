/// Token Registry - Centralized language token type management
/// SIMPLIFIED: Token is now just a pure union with no methods
/// Each language owns its semantics completely
///
/// Design principles:
/// - Token is just data, no abstractions
/// - All language-specific imports contained here
/// - Other modules import Token from here
/// - Maintains 1-2 cycle dispatch for all languages
const std = @import("std");

// Import all language token types
const JsonToken = @import("json/token/mod.zig").Token;
const ZonToken = @import("zon/token/types.zig").Token;

// Future language imports will go here:
// const TsToken = @import("typescript/stream_token.zig").TsToken;
// const ZigToken = @import("zig/stream_token.zig").ZigToken;
// const CssToken = @import("css/stream_token.zig").CssToken;
// const HtmlToken = @import("html/stream_token.zig").HtmlToken;
// const SvelteToken = @import("svelte/stream_token.zig").SvelteToken;

/// Universal token - the tagged union of all language tokens
/// This is THE token type used throughout the system
/// SIMPLIFIED: No methods, no abstractions - just a union for dispatch
pub const Token = union(enum) {
    json: JsonToken,
    zon: ZonToken,
    // typescript: TsToken,
    // zig: ZigToken,
    // css: CssToken,
    // html: HtmlToken,
    // svelte: SvelteToken,

    // That's it! No methods. Parsers access fields directly:
    // switch (token) {
    //     .json => |t| if (t.kind == .whitespace) continue,
    //     .zon => |t| if (t.kind == .comment) continue,
    // }
};
