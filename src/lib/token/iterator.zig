/// TokenIterator - Streaming tokenization with lookahead
/// Converts source text into a stream of tokens on-demand
///
/// TODO: Wire up to actual language lexers from languages/*/lexer.zig
/// TODO: Create LexerRegistry for dynamic language selection
/// TODO: Implement proper position tracking using token spans
/// TODO: Phase 3 - Convert TokenIterator to proper Stream(StreamToken) adapter
const std = @import("std");
const StreamToken = @import("stream_token.zig").StreamToken;
const Stream = @import("../stream/mod.zig").Stream;
const DirectStream = @import("../stream/mod.zig").DirectStream;
const RingBuffer = @import("../stream/mod.zig").RingBuffer;

// TODO: Import actual language lexers when implemented
// For now, these are placeholders showing the expected interface
const JsonLexer = struct {
    pub fn nextToken(self: *JsonLexer, source: []const u8, pos: usize) ?StreamToken {
        _ = self;
        _ = source;
        _ = pos;
        // TODO: Implement actual JSON lexing
        return null;
    }
};

const ZonLexer = struct {
    pub fn nextToken(self: *ZonLexer, source: []const u8, pos: usize) ?StreamToken {
        _ = self;
        _ = source;
        _ = pos;
        // TODO: Implement actual ZON lexing
        return null;
    }
};

/// Language-specific lexer dispatch
pub const LanguageLexer = union(enum) {
    json: JsonLexer,
    zon: ZonLexer,
    // TODO: Add more language lexers:
    // typescript: TsLexer,
    // zig: ZigLexer,
    // css: CssLexer,
    // html: HtmlLexer,
    // svelte: SvelteLexer,

    pub fn nextToken(self: *LanguageLexer, source: []const u8, pos: usize) ?StreamToken {
        return switch (self.*) {
            inline else => |*lexer| lexer.nextToken(source, pos),
        };
    }
};

/// Streaming token iterator with small lookahead buffer
pub const TokenIterator = struct {
    source: []const u8,
    lexer: LanguageLexer,
    position: usize,
    buffer: RingBuffer(StreamToken, 16), // Small lookahead for peek operations
    atom_table: ?*AtomTable = null, // Optional atom table for string interning

    // TODO: Batch atom interning for better performance
    // atom_batch: [32][]const u8,
    // batch_count: u8,

    // TODO: Consider thread-local atom tables for parallelism
    // thread_local_atoms: ?*ThreadLocalAtomTable,

    const Self = @This();
    const AtomTable = @import("../memory/atom_table.zig").AtomTable;

    /// Initialize a token iterator for the given source and language
    pub fn init(source: []const u8, language: Language) TokenIterator {
        return .{
            .source = source,
            .lexer = createLexer(language),
            .position = 0,
            .buffer = RingBuffer(StreamToken, 16).init(),
        };
    }

    /// Initialize with atom table for string interning
    pub fn initWithAtoms(source: []const u8, language: Language, atom_table: *AtomTable) TokenIterator {
        var iter = init(source, language);
        iter.atom_table = atom_table;
        return iter;
    }

    /// Get the next token, advancing the position
    pub fn next(self: *Self) ?StreamToken {
        // Check buffer first
        if (self.buffer.pop()) |token| {
            return token;
        }

        // Lex next token from source
        if (self.lexer.nextToken(self.source, self.position)) |token| {
            // TODO: Update position based on token span
            // self.position = token.getSpan().end;
            return token;
        }

        return null;
    }

    /// Peek at the next token without consuming it
    pub fn peek(self: *Self) ?StreamToken {
        // Check buffer first
        if (self.buffer.peek()) |token| {
            return token;
        }

        // Lex and buffer the next token
        if (self.lexer.nextToken(self.source, self.position)) |token| {
            _ = self.buffer.push(token) catch return null;
            return token;
        }

        return null;
    }

    /// Skip n tokens
    pub fn skip(self: *Self, n: usize) void {
        var i: usize = 0;
        while (i < n) : (i += 1) {
            _ = self.next();
        }
    }

    /// Convert to a Stream for composable operations
    pub fn toStream(self: *Self) Stream(StreamToken) {
        // TODO: Implement Stream adapter
        // This would wrap the iterator in a Stream interface
        _ = self;
        return undefined;
    }

    /// Convert to a DirectStream for optimal performance (Phase 5)
    pub fn toDirectStream(self: *Self) DirectStream(StreamToken) {
        // Create a generator-based DirectStream
        const GeneratorStream = @import("../stream/direct_stream.zig").GeneratorStream;

        return DirectStream(StreamToken){
            .generator = GeneratorStream(StreamToken).init(self, struct {
                fn generate(iter: *anyopaque) ?StreamToken {
                    const it = @as(*TokenIterator, @ptrCast(@alignCast(iter)));
                    return it.next();
                }
            }.generate),
        };
    }

    // TODO: Phase 5 - Remove toStream once all consumers migrated to toDirectStream
};

/// Language enumeration for lexer creation
pub const Language = enum {
    json,
    zon,
    typescript,
    zig,
    css,
    html,
    svelte,
};

/// Create a language-specific lexer
fn createLexer(language: Language) LanguageLexer {
    return switch (language) {
        .json => .{ .json = JsonLexer{} },
        .zon => .{ .zon = ZonLexer{} },
        // TODO: Implement other language lexers
        else => .{ .json = JsonLexer{} }, // Default to JSON for now
    };
}
