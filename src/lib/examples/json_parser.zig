const std = @import("std");
const Grammar = @import("../grammar/mod.zig").Grammar;
const grammar = @import("../grammar/mod.zig");
const Parser = @import("../parser/mod.zig").Parser;
const ParseResult = @import("../parser/mod.zig").ParseResult;
const CommonRules = @import("../ast/rules.zig").CommonRules;
const JsonRules = @import("../ast/rules.zig").JsonRules;

/// Complete JSON parser using our grammar system
pub const JsonParser = struct {
    allocator: std.mem.Allocator,
    grammar: Grammar,
    parser: Parser,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !Self {
        const json_grammar = try createJsonGrammar(allocator);
        const parser = Parser.init(allocator, json_grammar);

        return Self{
            .allocator = allocator,
            .grammar = json_grammar,
            .parser = parser,
        };
    }

    pub fn deinit(self: *Self) void {
        self.parser.deinit();
        self.grammar.deinit();
    }

    pub fn parse(self: Self, input: []const u8) !ParseResult {
        return self.parser.parse(input);
    }
};

/// Create a complete JSON grammar
fn createJsonGrammar(allocator: std.mem.Allocator) !Grammar {
    var builder = Grammar.builder(allocator);

    // Basic tokens
    _ = try builder.define("ws", grammar.optional(grammar.choice(&.{
        grammar.terminal(" "),
        grammar.terminal("\t"),
        grammar.terminal("\n"),
        grammar.terminal("\r"),
    })));

    _ = try builder.define("quote", grammar.terminal("\""));
    _ = try builder.define("comma", grammar.terminal(","));
    _ = try builder.define("colon", grammar.terminal(":"));
    _ = try builder.define("lbrace", grammar.terminal("{"));
    _ = try builder.define("rbrace", grammar.terminal("}"));
    _ = try builder.define("lbracket", grammar.terminal("["));
    _ = try builder.define("rbracket", grammar.terminal("]"));

    // Digits and numbers (simplified)
    _ = try builder.define("digit", grammar.choice(&.{
        grammar.terminal("0"), grammar.terminal("1"), grammar.terminal("2"),
        grammar.terminal("3"), grammar.terminal("4"), grammar.terminal("5"),
        grammar.terminal("6"), grammar.terminal("7"), grammar.terminal("8"),
        grammar.terminal("9"),
    }));

    _ = try builder.define("number", grammar.sequence(&.{
        grammar.optional(grammar.terminal("-")),
        grammar.repeat1(grammar.ref("digit")),
        grammar.optional(grammar.sequence(&.{
            grammar.terminal("."),
            grammar.repeat1(grammar.ref("digit")),
        })),
    }));

    // Strings (simplified - no escape sequences)
    _ = try builder.define("string_char", grammar.choice(&.{
        grammar.terminal("a"), grammar.terminal("b"), grammar.terminal("c"),
        grammar.terminal("d"), grammar.terminal("e"), grammar.terminal("f"),
        grammar.terminal("g"), grammar.terminal("h"), grammar.terminal("i"),
        grammar.terminal("j"), grammar.terminal("k"), grammar.terminal("l"),
        grammar.terminal("m"), grammar.terminal("n"), grammar.terminal("o"),
        grammar.terminal("p"), grammar.terminal("q"), grammar.terminal("r"),
        grammar.terminal("s"), grammar.terminal("t"), grammar.terminal("u"),
        grammar.terminal("v"), grammar.terminal("w"), grammar.terminal("x"),
        grammar.terminal("y"), grammar.terminal("z"), grammar.terminal("A"),
        grammar.terminal("B"), grammar.terminal("C"), grammar.terminal("D"),
        grammar.terminal("E"), grammar.terminal("F"), grammar.terminal("G"),
        grammar.terminal("H"), grammar.terminal("I"), grammar.terminal("J"),
        grammar.terminal("K"), grammar.terminal("L"), grammar.terminal("M"),
        grammar.terminal("N"), grammar.terminal("O"), grammar.terminal("P"),
        grammar.terminal("Q"), grammar.terminal("R"), grammar.terminal("S"),
        grammar.terminal("T"), grammar.terminal("U"), grammar.terminal("V"),
        grammar.terminal("W"), grammar.terminal("X"), grammar.terminal("Y"),
        grammar.terminal("Z"), grammar.terminal(" "), grammar.terminal("_"),
    }));

    _ = try builder.define("string", grammar.sequence(&.{
        grammar.ref("quote"),
        grammar.repeat(grammar.ref("string_char")),
        grammar.ref("quote"),
    }));

    // Literals
    _ = try builder.define("true", grammar.terminal("true"));
    _ = try builder.define("false", grammar.terminal("false"));
    _ = try builder.define("null", grammar.terminal("null"));

    // Values
    _ = try builder.define("value", grammar.choice(&.{
        grammar.ref("string"),
        grammar.ref("number"),
        grammar.ref("object"),
        grammar.ref("array"),
        grammar.ref("true"),
        grammar.ref("false"),
        grammar.ref("null"),
    }));

    // Arrays
    _ = try builder.define("array_elements", grammar.sequence(&.{
        grammar.ref("value"),
        grammar.repeat(grammar.sequence(&.{
            grammar.ref("ws"),
            grammar.ref("comma"),
            grammar.ref("ws"),
            grammar.ref("value"),
        })),
    }));

    _ = try builder.define("array", grammar.sequence(&.{
        grammar.ref("lbracket"),
        grammar.ref("ws"),
        grammar.optional(grammar.ref("array_elements")),
        grammar.ref("ws"),
        grammar.ref("rbracket"),
    }));

    // Objects
    _ = try builder.define("object_pair", grammar.sequence(&.{
        grammar.ref("string"),
        grammar.ref("ws"),
        grammar.ref("colon"),
        grammar.ref("ws"),
        grammar.ref("value"),
    }));

    _ = try builder.define("object_pairs", grammar.sequence(&.{
        grammar.ref("object_pair"),
        grammar.repeat(grammar.sequence(&.{
            grammar.ref("ws"),
            grammar.ref("comma"),
            grammar.ref("ws"),
            grammar.ref("object_pair"),
        })),
    }));

    _ = try builder.define("object", grammar.sequence(&.{
        grammar.ref("lbrace"),
        grammar.ref("ws"),
        grammar.optional(grammar.ref("object_pairs")),
        grammar.ref("ws"),
        grammar.ref("rbrace"),
    }));

    // Start with value
    _ = builder.start("value");

    return builder.build();
}

// Tests
const testing = std.testing;

test "JSON parser - simple string" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var json_parser = try JsonParser.init(allocator);
    defer json_parser.deinit();

    const result = try json_parser.parse("\"hello\"");
    try testing.expect(result.isSuccess());

    switch (result) {
        .success => |node| {
            // TODO: Replace with specific JSON rule ID when available
            try testing.expect(node.rule_id != 0); // Basic sanity check
            try testing.expectEqualStrings("\"hello\"", node.text);
            defer node.deinit(allocator);
        },
        .failure => return error.UnexpectedFailure,
    }
}

test "JSON parser - simple number" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var json_parser = try JsonParser.init(allocator);
    defer json_parser.deinit();

    const result = try json_parser.parse("42");
    try testing.expect(result.isSuccess());

    switch (result) {
        .success => |node| {
            // TODO: Replace with specific JSON rule ID when available
            try testing.expect(node.rule_id != 0); // Basic sanity check
            try testing.expectEqualStrings("42", node.text);
            defer node.deinit(allocator);
        },
        .failure => return error.UnexpectedFailure,
    }
}

test "JSON parser - boolean values" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var json_parser = try JsonParser.init(allocator);
    defer json_parser.deinit();

    // Test true
    {
        const result = try json_parser.parse("true");
        try testing.expect(result.isSuccess());
        switch (result) {
            .success => |node| {
                // TODO: Replace with specific JSON rule ID when available
                try testing.expect(node.rule_id != 0); // Basic sanity check
                try testing.expectEqualStrings("true", node.text);
                defer node.deinit(allocator);
            },
            .failure => return error.UnexpectedFailure,
        }
    }

    // Test false
    {
        const result = try json_parser.parse("false");
        try testing.expect(result.isSuccess());
        switch (result) {
            .success => |node| {
                // TODO: Replace with specific JSON rule ID when available
                try testing.expect(node.rule_id != 0); // Basic sanity check
                try testing.expectEqualStrings("false", node.text);
                defer node.deinit(allocator);
            },
            .failure => return error.UnexpectedFailure,
        }
    }
}

test "JSON parser - null value" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var json_parser = try JsonParser.init(allocator);
    defer json_parser.deinit();

    const result = try json_parser.parse("null");
    try testing.expect(result.isSuccess());

    switch (result) {
        .success => |node| {
            // TODO: Replace with specific JSON rule ID when available
            try testing.expect(node.rule_id != 0); // Basic sanity check
            try testing.expectEqualStrings("null", node.text);
            defer node.deinit(allocator);
        },
        .failure => return error.UnexpectedFailure,
    }
}

test "JSON parser - simple array" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var json_parser = try JsonParser.init(allocator);
    defer json_parser.deinit();

    const result = try json_parser.parse("[1, 2, 3]");
    try testing.expect(result.isSuccess());

    switch (result) {
        .success => |node| {
            // TODO: Replace with specific JSON rule ID when available
            try testing.expect(node.rule_id != 0); // Basic sanity check
            try testing.expectEqualStrings("[1, 2, 3]", node.text);
            defer node.deinit(allocator);
        },
        .failure => return error.UnexpectedFailure,
    }
}

test "JSON parser - simple object" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var json_parser = try JsonParser.init(allocator);
    defer json_parser.deinit();

    const result = try json_parser.parse("{\"key\": \"value\"}");
    try testing.expect(result.isSuccess());

    switch (result) {
        .success => |node| {
            // TODO: Replace with specific JSON rule ID when available
            try testing.expect(node.rule_id != 0); // Basic sanity check
            try testing.expectEqualStrings("{\"key\": \"value\"}", node.text);
            defer node.deinit(allocator);
        },
        .failure => return error.UnexpectedFailure,
    }
}
