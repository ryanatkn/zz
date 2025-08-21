/// LexerBridge - Bridges old lexers to new StreamToken system
///
/// ⚠️ TEMPORARY MODULE - WILL BE DELETED IN PHASE 4 ⚠️
/// This entire module exists only to keep the system working during migration.
/// Once all lexers produce StreamToken directly, this bridge will be removed.
///
/// TODO: TEMPORARY IMPLEMENTATION for Phase 2 only
/// TODO: Replace with direct StreamToken production in Phase 4
/// TODO: Current vtable dispatch adds 3-5 cycles overhead per token
/// TODO: Consider batch conversion for better cache utilization
/// TODO: Performance metrics below are to measure migration urgency, not for long-term use
const std = @import("std");
const StreamToken = @import("../token/stream_token.zig").StreamToken;
const TokenStream = @import("../stream/mod.zig").Stream(StreamToken);
const DirectStream = @import("../stream/mod.zig").DirectStream;
const directFromSlice = @import("../stream/mod.zig").directFromSlice;
const AtomTable = @import("../memory/atom_table.zig").AtomTable;
const AtomId = @import("../memory/atom_table.zig").AtomId;
const Language = @import("../core/language.zig").Language;
const Span = @import("../span/mod.zig").Span;
const PackedSpan = @import("../span/mod.zig").PackedSpan;
const packSpan = @import("../span/mod.zig").packSpan;

// Import old token type for bridging
// TODO: Remove this dependency once all lexers are migrated
const OldToken = @import("../parser_old/foundation/types/token.zig").Token;
const OldTokenKind = @import("../parser_old/foundation/types/predicate.zig").TokenKind;

// Import language-specific tokens
const JsonToken = @import("../languages/json/stream_token.zig").JsonToken;
const ZonToken = @import("../languages/zon/stream_token.zig").ZonToken;

/// Bridge between old lexer system and new stream-first architecture
pub const LexerBridge = struct {
    language: Language,
    atom_table: *AtomTable,
    allocator: std.mem.Allocator,
    
    // TODO: Replace with union(enum) of stream-first lexers
    // TODO: This indirection hurts performance - measure impact
    old_lexer: *anyopaque,
    tokenize_fn: *const fn (*anyopaque, []const u8) anyerror![]OldToken,
    
    // Statistics for monitoring bridge overhead
    // TODO: Add more detailed metrics (cache misses, atom conflicts, etc.)
    stats: BridgeStats = .{},
    
    pub const BridgeStats = struct {
        tokens_converted: u64 = 0,
        atoms_interned: u64 = 0,
        conversion_time_ns: u64 = 0,
    };
    
    /// Initialize a bridge for the given language
    pub fn init(
        allocator: std.mem.Allocator,
        language: Language,
        atom_table: *AtomTable,
    ) !LexerBridge {
        // TODO: This is ugly - replace with proper language dispatch
        // TODO: Consider compile-time generation of this switch
        switch (language) {
            .json => {
                const JsonLexer = @import("../languages/json/lexer.zig").JsonLexer;
                const lexer = try allocator.create(JsonLexer);
                lexer.* = JsonLexer.init(allocator, "", .{});
                
                return .{
                    .language = language,
                    .atom_table = atom_table,
                    .allocator = allocator,
                    .old_lexer = lexer,
                    .tokenize_fn = jsonTokenizeFn,
                };
            },
            .zon => {
                const ZonLexer = @import("../languages/zon/lexer.zig").ZonLexer;
                const lexer = try allocator.create(ZonLexer);
                lexer.* = ZonLexer.init(allocator, "", .{});  // Added options parameter
                
                return .{
                    .language = language,
                    .atom_table = atom_table,
                    .allocator = allocator,
                    .old_lexer = lexer,
                    .tokenize_fn = zonTokenizeFn,
                };
            },
            else => {
                // TODO: Implement bridges for other languages
                // TODO: TypeScript, Zig, CSS, HTML, Svelte
                return error.LanguageNotImplemented;
            },
        }
    }
    
    /// Clean up resources
    pub fn deinit(self: *LexerBridge) void {
        // TODO: Proper cleanup for each lexer type based on language
        // For now, just deallocate based on language type
        switch (self.language) {
            .json => {
                const JsonLexer = @import("../languages/json/lexer.zig").JsonLexer;
                const lexer = @as(*JsonLexer, @ptrCast(@alignCast(self.old_lexer)));
                lexer.deinit();
                self.allocator.destroy(lexer);
            },
            .zon => {
                const ZonLexer = @import("../languages/zon/lexer.zig").ZonLexer;
                const lexer = @as(*ZonLexer, @ptrCast(@alignCast(self.old_lexer)));
                lexer.deinit();
                self.allocator.destroy(lexer);
            },
            else => {},
        }
    }
    
    /// Convert source to stream tokens
    pub fn tokenize(self: *LexerBridge, source: []const u8) ![]StreamToken {
        const start_time = std.time.nanoTimestamp();
        defer {
            const elapsed = std.time.nanoTimestamp() - start_time;
            self.stats.conversion_time_ns += @intCast(elapsed);
        }
        
        // Get old tokens from legacy lexer
        // TODO: Avoid this intermediate allocation
        const old_tokens = try self.tokenize_fn(self.old_lexer, source);
        defer self.allocator.free(old_tokens);
        
        // Allocate space for new tokens
        // TODO: Use a ring buffer or streaming approach instead
        var new_tokens = try self.allocator.alloc(StreamToken, old_tokens.len);
        errdefer self.allocator.free(new_tokens);
        
        // Convert each token
        // TODO: Batch conversion for better performance
        // TODO: SIMD optimization for token conversion
        for (old_tokens, 0..) |old_token, i| {
            new_tokens[i] = try self.convertToken(old_token);
            self.stats.tokens_converted += 1;
        }
        
        return new_tokens;
    }
    
    /// Convert source to DirectStream of tokens (Phase 5 migration)
    /// TODO: This still allocates the full token array - true streaming in Phase 6
    /// TODO: Consider generator-based approach to avoid intermediate allocation
    pub fn tokenizeDirectStream(self: *LexerBridge, source: []const u8) !DirectStream(StreamToken) {
        // For now, tokenize to array then wrap in DirectStream
        // This is not ideal but maintains compatibility during migration
        const tokens = try self.tokenize(source);
        // Note: Caller is responsible for freeing tokens array when done
        return directFromSlice(StreamToken, tokens);
    }
    
    /// Convert a single old token to new StreamToken
    fn convertToken(self: *LexerBridge, old: OldToken) !StreamToken {
        // Intern the text if needed
        // TODO: Cache frequent strings (keywords, operators)
        // TODO: Skip interning for trivia tokens
        const atom_id = if (old.text.len > 0) blk: {
            self.stats.atoms_interned += 1;
            break :blk try self.atom_table.intern(old.text);
        } else 0;
        
        // Convert old span to new span and pack it
        const new_span = Span.init(@intCast(old.span.start), @intCast(old.span.end));
        const packed_span = packSpan(new_span);
        
        // Convert based on language
        // TODO: Use jump table instead of switch for performance
        return switch (self.language) {
            .json => StreamToken{ .json = self.convertJsonToken(old, packed_span, atom_id) },
            .zon => StreamToken{ .zon = self.convertZonToken(old, packed_span, atom_id) },
            else => error.LanguageNotImplemented,
        };
    }
    
    /// Convert old token to JSON token
    fn convertJsonToken(self: *LexerBridge, old: OldToken, span: PackedSpan, atom_id: AtomId) JsonToken {
        _ = self;
        
        // Map old TokenKind to JsonTokenKind
        // TODO: This mapping is lossy - preserve more information
        // TODO: Generate this mapping at compile time
        const JsonTokenKind = @import("../languages/json/stream_token.zig").JsonTokenKind;
        const kind = switch (old.kind) {
            .left_brace => JsonTokenKind.object_start,
            .right_brace => JsonTokenKind.object_end,
            .left_bracket => JsonTokenKind.array_start,
            .right_bracket => JsonTokenKind.array_end,
            .comma => JsonTokenKind.comma,
            .colon => JsonTokenKind.colon,
            .string_literal => JsonTokenKind.string_value,
            .number_literal => JsonTokenKind.number_value,
            .boolean_literal => JsonTokenKind.boolean_false, // TODO: Need to check actual value
            .null_literal => JsonTokenKind.null_value,
            .whitespace => JsonTokenKind.whitespace,
            .comment => JsonTokenKind.comment,
            else => JsonTokenKind.err,
        };
        
        // Create JSON token with atom ID
        // TODO: Preserve more flags from old token
        // TODO: Track escape sequences and other metadata
        return JsonToken{
            .span = span,
            .kind = kind,
            .depth = @intCast(old.bracket_depth),
            .flags = .{},
            .data = atom_id,
        };
    }
    
    /// Convert old token to ZON token
    fn convertZonToken(self: *LexerBridge, old: OldToken, span: PackedSpan, atom_id: AtomId) ZonToken {
        _ = self;
        
        // Map old TokenKind to ZonTokenKind
        // TODO: Better mapping for ZON-specific tokens
        const ZonTokenKind = @import("../languages/zon/stream_token.zig").ZonTokenKind;
        const kind = switch (old.kind) {
            .left_brace => ZonTokenKind.struct_start,
            .right_brace => ZonTokenKind.struct_end,
            .left_bracket => ZonTokenKind.array_start,
            .right_bracket => ZonTokenKind.array_end,
            .comma => ZonTokenKind.comma,
            .dot => ZonTokenKind.dot,
            .identifier => ZonTokenKind.identifier,
            .string_literal => ZonTokenKind.string_value,
            .number_literal => ZonTokenKind.number_value,
            .boolean_literal => ZonTokenKind.boolean_false, // TODO: Need to check actual value
            .null_literal => ZonTokenKind.null_value,
            .whitespace => ZonTokenKind.whitespace,
            .comment => ZonTokenKind.comment,
            else => ZonTokenKind.err,
        };
        
        return ZonToken{
            .span = span,
            .kind = kind,
            .depth = @intCast(old.bracket_depth),
            .flags = .{},
            .data = atom_id,
        };
    }
};

// Type-erased wrapper functions for old lexers
// TODO: Remove these once we have proper stream lexers
fn jsonTokenizeFn(lexer: *anyopaque, source: []const u8) anyerror![]OldToken {
    const JsonLexer = @import("../languages/json/lexer.zig").JsonLexer;
    const typed_lexer = @as(*JsonLexer, @ptrCast(@alignCast(lexer)));
    typed_lexer.source = source;
    _ = try typed_lexer.tokenize();  // Discard returned value
    return typed_lexer.tokens.toOwnedSlice();
}

fn zonTokenizeFn(lexer: *anyopaque, source: []const u8) anyerror![]OldToken {
    const ZonLexer = @import("../languages/zon/lexer.zig").ZonLexer;
    const typed_lexer = @as(*ZonLexer, @ptrCast(@alignCast(lexer)));
    typed_lexer.source = source;
    _ = try typed_lexer.tokenize();  // Discard returned value
    return typed_lexer.tokens.toOwnedSlice();
}

test "LexerBridge basic conversion" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    // Create atom table
    var atom_table = AtomTable.init(allocator);
    defer atom_table.deinit();
    
    // Create bridge for JSON
    var bridge = try LexerBridge.init(allocator, .json, &atom_table);
    defer bridge.deinit();
    
    // Test simple JSON
    const source = "{\"key\": 123}";
    const tokens = try bridge.tokenize(source);
    defer allocator.free(tokens);
    
    // Verify we got tokens
    try testing.expect(tokens.len > 0);
    
    // Check statistics
    try testing.expect(bridge.stats.tokens_converted > 0);
    try testing.expect(bridge.stats.atoms_interned > 0);
    
    // TODO: Add more comprehensive tests
    // TODO: Test all token types
    // TODO: Test error cases
    // TODO: Performance benchmarks
}