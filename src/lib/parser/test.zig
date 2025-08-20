const std = @import("std");
const testing = std.testing;
const Parser = @import("detailed/parser.zig").Parser;
const ParseResult = @import("detailed/parser.zig").ParseResult;

// Import submodule tests
test {
    _ = @import("foundation/test.zig");
    _ = @import("foundation/collections/test.zig");
    _ = @import("lexical/test.zig");
    _ = @import("structural/test.zig");
    _ = @import("detailed/test.zig");
}

// Import grammar module directly
const grammar_mod = @import("../grammar/mod.zig");
const Grammar = grammar_mod.Grammar;
const extended = grammar_mod.extended;
const terminal = extended.terminal;
const sequence = extended.sequence;
const choice = extended.choice;
const optional = extended.optional;
const repeat = extended.repeat;
const repeat1 = extended.repeat1;
const ref = extended.ref;

// Test helper to validate rule ID matches expected test rule
fn expectRuleId(node: anytype, expected_name: []const u8) !void {
    // For test rules, we can't easily map back to names since the builder
    // creates dynamic rule IDs. Instead, we'll just verify it's a valid test rule ID.
    const TestRules = @import("../ast/rules.zig").TestRules;
    const CommonRules = @import("../ast/rules.zig").CommonRules;

    // Check if it's a common rule first
    if (std.mem.eql(u8, expected_name, "root")) {
        try testing.expectEqual(@intFromEnum(CommonRules.root), node.rule_id);
    } else if (std.mem.eql(u8, expected_name, "object")) {
        try testing.expectEqual(@intFromEnum(CommonRules.object), node.rule_id);
    } else if (std.mem.eql(u8, expected_name, "array")) {
        try testing.expectEqual(@intFromEnum(CommonRules.array), node.rule_id);
    } else {
        // For custom test rules, just verify it's in the test range
        try testing.expect(TestRules.isTestRule(node.rule_id));
    }
}

test "simple terminal parsing" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Create simple grammar: just "hello"
    var builder = Grammar.builder(allocator);
    _ = try builder.define("greeting", terminal("hello"));
    _ = builder.start("greeting");
    const test_grammar = try builder.build();

    var parser = Parser.init(allocator, test_grammar);
    defer parser.deinit();

    const result = try parser.parse("hello");
    try testing.expect(result.isSuccess());

    switch (result) {
        .success => |node| {
            try expectRuleId(node, "greeting");
            try testing.expectEqualStrings("hello", node.text);
            try testing.expectEqual(@as(usize, 0), node.start_position);
            try testing.expectEqual(@as(usize, 5), node.end_position);
            defer node.deinit(allocator);
        },
        .failure => return error.UnexpectedFailure,
    }
}

test "sequence parsing" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Create grammar: "hello" + " " + "world"
    var builder = Grammar.builder(allocator);
    _ = try builder.define("greeting", try sequence(allocator, &.{
        terminal("hello"),
        terminal(" "),
        terminal("world"),
    }));
    _ = builder.start("greeting");
    const test_grammar = try builder.build();

    var parser = Parser.init(allocator, test_grammar);
    defer parser.deinit();

    const result = try parser.parse("hello world");
    try testing.expect(result.isSuccess());

    switch (result) {
        .success => |node| {
            try expectRuleId(node, "greeting");
            try testing.expectEqualStrings("hello world", node.text);
            try testing.expectEqual(@as(usize, 3), node.children.len);
            defer node.deinit(allocator);
        },
        .failure => return error.UnexpectedFailure,
    }
}

test "choice parsing" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Create grammar: "yes" | "no"
    var builder = Grammar.builder(allocator);
    _ = try builder.define("answer", try choice(allocator, &.{
        terminal("yes"),
        terminal("no"),
    }));
    _ = builder.start("answer");
    const test_grammar = try builder.build();

    var parser = Parser.init(allocator, test_grammar);
    defer parser.deinit();

    // Test "yes"
    {
        const result = try parser.parse("yes");
        try testing.expect(result.isSuccess());
        switch (result) {
            .success => |node| {
                try expectRuleId(node, "answer");
                try testing.expectEqualStrings("yes", node.text);
                defer node.deinit(allocator);
            },
            .failure => return error.UnexpectedFailure,
        }
    }

    // Test "no"
    {
        const result = try parser.parse("no");
        try testing.expect(result.isSuccess());
        switch (result) {
            .success => |node| {
                try expectRuleId(node, "answer");
                try testing.expectEqualStrings("no", node.text);
                defer node.deinit(allocator);
            },
            .failure => return error.UnexpectedFailure,
        }
    }
}

test "optional parsing" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Create grammar: "maybe"?
    var builder = Grammar.builder(allocator);
    const maybe_terminal = terminal("maybe");
    _ = try builder.define("optional_word", optional(&maybe_terminal));
    _ = builder.start("optional_word");
    const test_grammar = try builder.build();

    var parser = Parser.init(allocator, test_grammar);
    defer parser.deinit();

    // Test with "maybe"
    {
        const result = try parser.parse("maybe");
        try testing.expect(result.isSuccess());
        switch (result) {
            .success => |node| {
                try expectRuleId(node, "optional_word");
                try testing.expectEqualStrings("maybe", node.text);
                try testing.expectEqual(@as(usize, 1), node.children.len);
                defer node.deinit(allocator);
            },
            .failure => return error.UnexpectedFailure,
        }
    }

    // Test with empty input
    {
        const result = try parser.parse("");
        try testing.expect(result.isSuccess());
        switch (result) {
            .success => |node| {
                try expectRuleId(node, "optional_word");
                try testing.expectEqualStrings("", node.text);
                try testing.expectEqual(@as(usize, 0), node.children.len);
                defer node.deinit(allocator);
            },
            .failure => return error.UnexpectedFailure,
        }
    }
}

test "repeat parsing" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Create grammar: "a"*
    var builder = Grammar.builder(allocator);
    const a_terminal = terminal("a");
    _ = try builder.define("many_a", repeat(&a_terminal));
    _ = builder.start("many_a");
    const test_grammar = try builder.build();

    var parser = Parser.init(allocator, test_grammar);
    defer parser.deinit();

    // Test with "aaa"
    {
        const result = try parser.parse("aaa");
        try testing.expect(result.isSuccess());
        switch (result) {
            .success => |node| {
                try expectRuleId(node, "many_a");
                try testing.expectEqualStrings("aaa", node.text);
                try testing.expectEqual(@as(usize, 3), node.children.len);
                defer node.deinit(allocator);
            },
            .failure => return error.UnexpectedFailure,
        }
    }

    // Test with empty (should succeed with 0 matches)
    {
        const result = try parser.parse("");
        try testing.expect(result.isSuccess());
        switch (result) {
            .success => |node| {
                try expectRuleId(node, "many_a");
                try testing.expectEqualStrings("", node.text);
                try testing.expectEqual(@as(usize, 0), node.children.len);
                defer node.deinit(allocator);
            },
            .failure => return error.UnexpectedFailure,
        }
    }
}

test "repeat1 parsing" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Create grammar: "b"+
    var builder = Grammar.builder(allocator);
    const b_terminal = terminal("b");
    _ = try builder.define("some_b", repeat1(&b_terminal));
    _ = builder.start("some_b");
    const test_grammar = try builder.build();

    var parser = Parser.init(allocator, test_grammar);
    defer parser.deinit();

    // Test with "bbb"
    {
        const result = try parser.parse("bbb");
        try testing.expect(result.isSuccess());
        switch (result) {
            .success => |node| {
                try expectRuleId(node, "some_b");
                try testing.expectEqualStrings("bbb", node.text);
                try testing.expectEqual(@as(usize, 3), node.children.len);
                defer node.deinit(allocator);
            },
            .failure => return error.UnexpectedFailure,
        }
    }

    // Test with empty (should fail)
    {
        const result = try parser.parse("");
        try testing.expect(!result.isSuccess());
    }
}

test "parse failure with error reporting" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Create simple grammar expecting "hello"
    var builder = Grammar.builder(allocator);
    _ = try builder.define("greeting", terminal("hello"));
    _ = builder.start("greeting");
    const test_grammar = try builder.build();

    var parser = Parser.init(allocator, test_grammar);
    defer parser.deinit();

    const result = try parser.parse("hi");
    try testing.expect(!result.isSuccess());

    switch (result) {
        .success => return error.UnexpectedSuccess,
        .failure => |errors| {
            try testing.expect(errors.len > 0);
        },
    }
}

test "rule references with builder" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Create grammar with references: number = digit+, expr = number
    var builder = Grammar.builder(allocator);
    _ = try builder.define("digit", try choice(allocator, &.{
        terminal("0"), terminal("1"), terminal("2"),
        terminal("3"), terminal("4"), terminal("5"),
        terminal("6"), terminal("7"), terminal("8"),
        terminal("9"),
    }));
    const digit_ref = ref("digit");
    _ = try builder.define("number", repeat1(&digit_ref));
    _ = try builder.define("expr", ref("number"));
    _ = builder.start("expr");
    const test_grammar = try builder.build();

    var parser = Parser.init(allocator, test_grammar);
    defer parser.deinit();

    const result = try parser.parse("123");
    try testing.expect(result.isSuccess());

    switch (result) {
        .success => |node| {
            try expectRuleId(node, "expr");
            try testing.expectEqualStrings("123", node.text);
            defer node.deinit(allocator);
        },
        .failure => return error.UnexpectedFailure,
    }
}
