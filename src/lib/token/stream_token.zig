/// StreamToken - Tagged union for all language tokens
/// Eliminates vtable overhead with compile-time dispatch
///
/// Performance characteristics:
/// - Tagged union dispatch: 1-2 cycles (jump table)
/// - Memory size: ≤24 bytes (1 byte tag + 16 byte max variant + alignment)
/// - Zero allocations for token operations
///
/// TODO: Phase 3 - Add 'custom' variant for extensibility without impacting fast path
/// TODO: Benchmark actual dispatch performance vs vtable implementation
/// TODO: Measure impact of adding more language variants on code size
const std = @import("std");
const TokenKind = @import("kind.zig").TokenKind;
const PackedSpan = @import("../span/mod.zig").PackedSpan;
const unpackSpan = @import("../span/mod.zig").unpackSpan;
const Span = @import("../span/mod.zig").Span;
const FactStore = @import("../fact/mod.zig").FactStore;

// Import language-specific tokens
const JsonToken = @import("../languages/json/stream_token.zig").JsonToken;
const JsonTokenKind = @import("../languages/json/stream_token.zig").JsonTokenKind;
const ZonToken = @import("../languages/zon/stream_token.zig").ZonToken;
const ZonTokenKind = @import("../languages/zon/stream_token.zig").ZonTokenKind;

/// Universal stream token using tagged union
/// Compiler optimizes switch statements to jump tables (1-2 cycles)
pub const StreamToken = union(enum) {
    json: JsonToken,
    zon: ZonToken,
    // Future languages will be added here:
    // typescript: TsToken,
    // zig: ZigToken,
    // css: CssToken,
    // html: HtmlToken,
    // svelte: SvelteToken,
    
    /// Get the packed span of this token
    pub inline fn span(self: StreamToken) PackedSpan {
        return switch (self) {
            inline else => |token| token.span,
        };
    }
    
    /// Get the unpacked span of this token
    pub inline fn getSpan(self: StreamToken) Span {
        return unpackSpan(self.span());
    }
    
    /// Get the universal token kind
    pub inline fn kind(self: StreamToken) TokenKind {
        return switch (self) {
            .json => |t| mapJsonKind(t.kind),
            .zon => |t| mapZonKind(t.kind),
        };
    }
    
    /// Get the nesting depth
    pub inline fn depth(self: StreamToken) u8 {
        return switch (self) {
            inline else => |token| token.depth,
        };
    }
    
    /// Check if token is trivia (whitespace/comments)
    pub inline fn isTrivia(self: StreamToken) bool {
        return switch (self) {
            inline else => |token| token.isTrivia(),
        };
    }
    
    /// Check if token opens a scope
    pub inline fn isOpenDelimiter(self: StreamToken) bool {
        return switch (self) {
            inline else => |token| token.isOpenDelimiter(),
        };
    }
    
    /// Check if token closes a scope
    pub inline fn isCloseDelimiter(self: StreamToken) bool {
        return switch (self) {
            inline else => |token| token.isCloseDelimiter(),
        };
    }
    
    /// Extract facts from this token into the fact store
    pub fn extractFacts(self: StreamToken, store: *FactStore, source: []const u8) !void {
        return switch (self) {
            .json => |t| extractJsonFacts(t, store, source),
            .zon => |t| extractZonFacts(t, store, source),
        };
    }
    
    /// Get string table index if applicable
    pub inline fn getStringIndex(self: StreamToken) ?u32 {
        return switch (self) {
            inline else => |token| token.getStringIndex(),
        };
    }
};

/// Map JSON token kind to universal token kind
fn mapJsonKind(kind: JsonTokenKind) TokenKind {
    return switch (kind) {
        .object_start => .left_brace,
        .object_end => .right_brace,
        .array_start => .left_bracket,
        .array_end => .right_bracket,
        .comma => .comma,
        .colon => .colon,
        .property_name => .string,
        .string_value => .string,
        .number_value => .number,
        .boolean_true, .boolean_false => .boolean,
        .null_value => .null,
        .whitespace => .whitespace,
        .comment => .comment,
        .eof => .eof,
        .err => .err,
    };
}

/// Map ZON token kind to universal token kind
fn mapZonKind(kind: ZonTokenKind) TokenKind {
    return switch (kind) {
        .struct_start => .left_brace,
        .struct_end => .right_brace,
        .array_start => .left_bracket,
        .array_end => .right_bracket,
        .comma => .comma,
        .equals => .assign,
        .dot => .dot,
        .field_name => .identifier,
        .identifier => .identifier,
        .string_value => .string,
        .number_value => .number,
        .boolean_true, .boolean_false => .boolean,
        .null_value => .null,
        .undefined => .unknown,
        .enum_literal => .identifier,
        .import => .keyword_import,
        .whitespace => .whitespace,
        .comment => .comment,
        .eof => .eof,
        .err => .err,
    };
}

/// Extract facts from JSON token
fn extractJsonFacts(token: JsonToken, store: *FactStore, source: []const u8) !void {
    _ = source; // TODO: Use for text extraction when atom not available
    const Builder = @import("../fact/mod.zig").Builder;
    const Predicate = @import("../fact/mod.zig").Predicate;
    
    // Extract basic token fact
    const token_fact = try Builder.new()
        .withSubject(token.span)
        .withPredicate(switch (token.kind) {
            .object_start, .object_end => Predicate.json_is_object,
            .array_start, .array_end => Predicate.json_is_array,
            .property_name => Predicate.json_is_key,
            .string_value => Predicate.is_string,
            .number_value => Predicate.is_number,
            .boolean_true, .boolean_false => Predicate.json_is_boolean,
            .null_value => Predicate.json_is_null,
            else => Predicate.is_token,
        })
        .build();
    
    _ = try store.append(token_fact);
    
    // Extract depth fact for structural tokens
    if (token.isOpenDelimiter() or token.isCloseDelimiter()) {
        const depth_fact = try Builder.new()
            .withSubject(token.span)
            .withPredicate(Predicate.indent_level) // Using indent_level for depth
            .withNumber(@intCast(token.depth))
            .build();
        _ = try store.append(depth_fact);
    }
    
    // Extract text content for strings and properties
    // TODO: Cache atom lookups for hot paths
    // TODO: Consider inline small string optimization (SSO)
    if (token.kind == .property_name or token.kind == .string_value) {
        if (token.getAtomId()) |atom_id| {
            const text_fact = try Builder.new()
                .withSubject(token.span)
                .withPredicate(Predicate.has_text)
                .withAtom(atom_id)
                .build();
            _ = try store.append(text_fact);
        }
    }
}

/// Extract facts from ZON token
fn extractZonFacts(token: ZonToken, store: *FactStore, source: []const u8) !void {
    _ = source; // TODO: Use for text extraction
    const Builder = @import("../fact/mod.zig").Builder;
    const Predicate = @import("../fact/mod.zig").Predicate;
    
    // Extract basic token fact  
    const token_fact = try Builder.new()
        .withSubject(token.span)
        .withPredicate(switch (token.kind) {
            .struct_start, .struct_end => Predicate.is_class, // Using is_class for structs
            .array_start, .array_end => Predicate.json_is_array, // Reuse JSON array predicate
            .field_name => Predicate.is_field,
            .identifier => Predicate.is_identifier,
            .string_value => Predicate.is_string,
            .number_value => Predicate.is_number,
            .boolean_true, .boolean_false => Predicate.json_is_boolean,
            .null_value => Predicate.json_is_null,
            .enum_literal => Predicate.is_identifier, // Treat enum literals as identifiers
            .import => Predicate.is_keyword, // Treat import as keyword
            else => Predicate.is_token,
        })
        .build();
    
    _ = try store.append(token_fact);
    
    // Extract depth fact for structural tokens
    if (token.isOpenDelimiter() or token.isCloseDelimiter()) {
        const depth_fact = try Builder.new()
            .withSubject(token.span)
            .withPredicate(Predicate.indent_level) // Using indent_level for depth
            .withNumber(@intCast(token.depth))
            .build();
        _ = try store.append(depth_fact);
    }
    
    // Extract text content for identifiers and strings
    if (token.getStringIndex()) |_| {
        // TODO: Look up string from string table and get atom ID
        const text_fact = try Builder.new()
            .withSubject(token.span)
            .withPredicate(Predicate.has_text)
            .withAtom(0) // TODO: Get actual atom ID from string table
            .build();
        _ = try store.append(text_fact);
    }
}

// Size checks
comptime {
    // StreamToken should be reasonably sized (target: ≤24 bytes)
    // With tagged union overhead: 1 byte tag + 16 byte largest variant = 17 bytes
    // Rounded up to alignment: likely 24 bytes
    const token_size = @sizeOf(StreamToken);
    if (token_size > 24) {
        @compileError(std.fmt.comptimePrint("StreamToken too large: {} bytes (target: ≤24)", .{token_size}));
    }
}

test "StreamToken operations" {
    const span = Span.init(10, 20);
    
    // Test JSON token
    const json_tok = JsonToken.structural(span, .object_start, 0);
    const stream_tok_json = StreamToken{ .json = json_tok };
    
    try std.testing.expectEqual(json_tok.span, stream_tok_json.span());
    try std.testing.expectEqual(@as(u8, 0), stream_tok_json.depth());
    try std.testing.expectEqual(TokenKind.left_brace, stream_tok_json.kind());
    try std.testing.expect(stream_tok_json.isOpenDelimiter());
    try std.testing.expect(!stream_tok_json.isCloseDelimiter());
    
    // Test ZON token
    const zon_tok = ZonToken.field(span, 1, 42, false);
    const stream_tok_zon = StreamToken{ .zon = zon_tok };
    
    try std.testing.expectEqual(zon_tok.span, stream_tok_zon.span());
    try std.testing.expectEqual(@as(u8, 1), stream_tok_zon.depth());
    try std.testing.expectEqual(TokenKind.identifier, stream_tok_zon.kind());
    try std.testing.expectEqual(@as(?u32, 42), stream_tok_zon.getStringIndex());
}

test "StreamToken size" {
    const size = @sizeOf(StreamToken);
    std.debug.print("\nStreamToken size: {} bytes\n", .{size});
    try std.testing.expect(size <= 24);
}