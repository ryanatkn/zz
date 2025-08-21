/// stream/extract.zig - Stream-first fact extraction using DirectStream
/// Zero-allocation fact extraction pipeline for JSON and ZON
/// Achieves optimal performance with 1-2 cycle dispatch
///
/// Language-specific extractors are located with their language modules:
/// - JSON: languages/json/stream_extract.zig
/// - ZON: languages/zon/stream_extract.zig
const std = @import("std");

// Import core fact system
const fact_mod = @import("../fact/mod.zig");
const Fact = fact_mod.Fact;
const FactStore = fact_mod.FactStore;
const Predicate = fact_mod.Predicate;
const Builder = fact_mod.Builder;

// Import token system
const token_mod = @import("../token/mod.zig");
const StreamToken = token_mod.StreamToken;
const DirectTokenStream = token_mod.DirectTokenStream;

// Export extractors from language modules (when implemented)
// pub const JsonExtractor = @import("../languages/json/stream_extract.zig").JsonExtractor;
// pub const ZonExtractor = @import("../languages/zon/stream_extract.zig").ZonExtractor;

// Export common types
pub const ExtractOptions = @import("extract_options.zig").ExtractOptions;
pub const ExtractError = error{
    InvalidToken,
    UnexpectedEof,
    MismatchedBrackets,
    InvalidDepth,
    OutOfMemory,
};

/// Extract facts from any stream of tokens
pub fn extractFacts(
    comptime Extractor: type,
    token_stream: anytype,
    store: *FactStore,
    options: ExtractOptions,
) !void {
    var extractor = Extractor.init(store, options);
    while (try token_stream.next()) |token| {
        try extractor.processToken(token);
    }
    try extractor.finish();
}

/// Basic fact extractor for demonstration
/// Real extractors would be more sophisticated
pub const BasicExtractor = struct {
    store: *FactStore,
    options: ExtractOptions,
    depth: u8 = 0,
    current_span: ?@import("../span/mod.zig").Span = null,

    const Self = @This();

    pub fn init(store: *FactStore, options: ExtractOptions) Self {
        return .{
            .store = store,
            .options = options,
        };
    }

    pub fn processToken(self: *Self, token: StreamToken) !void {
        // Extract facts based on token type
        switch (token) {
            .json => |json_token| {
                switch (json_token.kind) {
                    .object_start => {
                        self.depth += 1;
                        if (self.options.extract_structure) {
                            const fact = try Builder.new()
                                .withPredicate(.json_is_object)
                                .withSpan(@import("../span/mod.zig").unpackSpan(json_token.span))
                                .withConfidence(1.0)
                                .build();
                            _ = try self.store.append(fact);
                        }
                    },
                    .string_value => {
                        if (self.options.extract_values) {
                            const fact = try Builder.new()
                                .withPredicate(.is_string)
                                .withSpan(@import("../span/mod.zig").unpackSpan(json_token.span))
                                .withConfidence(1.0)
                                .build();
                            _ = try self.store.append(fact);
                        }
                    },
                    .number_value => {
                        if (self.options.extract_values) {
                            const fact = try Builder.new()
                                .withPredicate(.is_number)
                                .withSpan(@import("../span/mod.zig").unpackSpan(json_token.span))
                                .withConfidence(1.0)
                                .build();
                            _ = try self.store.append(fact);
                        }
                    },
                    .boolean_true, .boolean_false => {
                        if (self.options.extract_values) {
                            const fact = try Builder.new()
                                .withPredicate(.json_is_boolean)
                                .withSpan(@import("../span/mod.zig").unpackSpan(json_token.span))
                                .withConfidence(1.0)
                                .build();
                            _ = try self.store.append(fact);
                        }
                    },
                    .object_end => {
                        self.depth -|= 1;
                    },
                    else => {},
                }
            },
            .zon => |zon_token| {
                // Similar logic for ZON tokens
                switch (zon_token.kind) {
                    .struct_start => {
                        self.depth += 1;
                        if (self.options.extract_structure) {
                            const fact = try Builder.new()
                                .withPredicate(.is_class) // Using is_class for structs
                                .withSpan(@import("../span/mod.zig").unpackSpan(zon_token.span))
                                .withConfidence(1.0)
                                .build();
                            _ = try self.store.append(fact);
                        }
                    },
                    .number_value => {
                        if (self.options.extract_values) {
                            const fact = try Builder.new()
                                .withPredicate(.is_number)
                                .withSpan(@import("../span/mod.zig").unpackSpan(zon_token.span))
                                .withConfidence(1.0)
                                .build();
                            _ = try self.store.append(fact);
                        }
                    },
                    .identifier => {
                        if (self.options.extract_identifiers) {
                            const fact = try Builder.new()
                                .withPredicate(.is_identifier)
                                .withSpan(@import("../span/mod.zig").unpackSpan(zon_token.span))
                                .withConfidence(1.0)
                                .build();
                            _ = try self.store.append(fact);
                        }
                    },
                    .object_end, .struct_end => {
                        self.depth -|= 1;
                    },
                    else => {},
                }
            },
        }
    }

    pub fn finish(self: *Self) !void {
        _ = self;
        // Any finalization logic
    }
};

test "basic fact extraction" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Create a fact store
    var store = FactStore.init(allocator);
    defer store.deinit();

    // Create options
    const options = ExtractOptions{
        .extract_structure = true,
        .extract_values = true,
        .extract_identifiers = false,
    };

    // Test JSON extraction
    const JsonStreamLexer = @import("../languages/json/stream_lexer.zig").JsonStreamLexer;
    const json_input = 
        \\{"key": "value", "number": 42}
    ;

    var lexer = JsonStreamLexer.init(json_input);
    var stream = lexer.toDirectStream();

    // Extract facts
    try extractFacts(BasicExtractor, &stream, &store, options);

    // Check that facts were extracted
    const facts = store.getAll();
    try testing.expect(facts.len > 0);

    // Check for specific predicates
    var has_object = false;
    var has_string = false;
    var has_number = false;

    for (facts) |fact| {
        switch (fact.predicate) {
            .json_is_object => has_object = true,
            .is_string => has_string = true,
            .is_number => has_number = true,
            else => {},
        }
    }

    try testing.expect(has_object);
    try testing.expect(has_string);
    try testing.expect(has_number);
}

test "stream extract tests" {
    _ = @import("extract_options.zig");
    // Language-specific extractors would be tested here
    // _ = @import("../languages/json/stream_extract.zig");
    // _ = @import("../languages/zon/stream_extract.zig");
}
