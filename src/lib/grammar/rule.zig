const std = @import("std");
const testing = std.testing;
const test_framework = @import("test_framework.zig");
const MatchResult = test_framework.MatchResult;
const TestContext = test_framework.TestContext;
const TestHelpers = test_framework.TestHelpers;

// Import all rule types
const rule_terminal = @import("rule_terminal.zig");
const rule_sequence = @import("rule_sequence.zig");
const rule_choice = @import("rule_choice.zig");
const rule_optional = @import("rule_optional.zig");
const rule_repeat = @import("rule_repeat.zig");
const rule_repeat1 = @import("rule_repeat1.zig");
const rule_helpers = @import("rule_helpers.zig");

// Re-export rule types
pub const Terminal = rule_terminal.Terminal;
pub const Sequence = rule_sequence.Sequence;
pub const Choice = rule_choice.Choice;
pub const Optional = rule_optional.Optional;
pub const Repeat = rule_repeat.Repeat;
pub const Repeat1 = rule_repeat1.Repeat1;

/// Base rule interface for grammar definitions
/// All rule types implement this pattern for matching input
pub const Rule = union(enum) {
    terminal: Terminal,
    sequence: Sequence,
    choice: Choice,
    optional: Optional,
    repeat: Repeat,
    repeat1: Repeat1,

    /// Attempt to match this rule against input at current position
    pub fn match(self: Rule, ctx: *TestContext) MatchResult {
        return switch (self) {
            .terminal => |t| t.match(ctx),
            .sequence => |s| s.match(ctx),
            .choice => |c| c.match(ctx),
            .optional => |o| o.match(ctx),
            .repeat => |r| r.match(ctx),
            .repeat1 => |r| r.match(ctx),
        };
    }

    /// Get a human-readable name for this rule
    pub fn name(self: Rule) []const u8 {
        return switch (self) {
            .terminal => "terminal",
            .sequence => "sequence",
            .choice => "choice",
            .optional => "optional",
            .repeat => "repeat",
            .repeat1 => "repeat1",
        };
    }
};

// Re-export helper functions
pub const terminal = rule_helpers.terminal;
pub const sequence = rule_helpers.sequence;
pub const choice = rule_helpers.choice;
pub const optional = rule_helpers.optional;
pub const repeat = rule_helpers.repeat;
pub const repeat1 = rule_helpers.repeat1;

// ============================================================================
// Tests - Keep these for compatibility
// ============================================================================

test "Terminal matches literal string" {
    const allocator = testing.allocator;
    var ctx = TestContext.init(allocator, "hello world");

    const rule = terminal("hello");
    const result = rule.match(&ctx);

    try TestHelpers.expectMatch(result, "hello");
    try TestHelpers.expectRemaining(result, " world");
}

test "Terminal fails on mismatch" {
    const allocator = testing.allocator;
    var ctx = TestContext.init(allocator, "world");

    const rule = terminal("hello");
    const result = rule.match(&ctx);

    try TestHelpers.expectNoMatch(result);
}

test "Terminal fails on partial match" {
    const allocator = testing.allocator;
    var ctx = TestContext.init(allocator, "hel");

    const rule = terminal("hello");
    const result = rule.match(&ctx);

    try TestHelpers.expectNoMatch(result);
}

test "Sequence matches rules in order" {
    const allocator = testing.allocator;
    var ctx = TestContext.init(allocator, "hello world");

    const rule = try sequence(allocator, &.{
        terminal("hello"),
        terminal(" "),
        terminal("world"),
    });
    defer {
        var seq = rule.sequence;
        seq.deinit();
    }

    const result = rule.match(&ctx);

    try TestHelpers.expectMatch(result, "hello world");
    try TestHelpers.expectConsumed(result, 11);
}

test "Sequence fails if any rule fails" {
    const allocator = testing.allocator;
    var ctx = TestContext.init(allocator, "hello");

    const rule = try sequence(allocator, &.{
        terminal("hello"),
        terminal(" "),
        terminal("world"),
    });
    defer {
        var seq = rule.sequence;
        seq.deinit();
    }

    const result = rule.match(&ctx);

    try TestHelpers.expectNoMatch(result);
    // Position should be restored on failure
    try testing.expectEqual(@as(usize, 0), ctx.position);
}

test "Choice matches first alternative" {
    const allocator = testing.allocator;
    var ctx = TestContext.init(allocator, "foo");

    const rule = try choice(allocator, &.{
        terminal("foo"),
        terminal("bar"),
        terminal("baz"),
    });
    defer {
        var ch = rule.choice;
        ch.deinit();
    }

    const result = rule.match(&ctx);

    try TestHelpers.expectMatch(result, "foo");
}

test "Choice matches second alternative" {
    const allocator = testing.allocator;
    var ctx = TestContext.init(allocator, "bar");

    const rule = try choice(allocator, &.{
        terminal("foo"),
        terminal("bar"),
        terminal("baz"),
    });
    defer {
        var ch = rule.choice;
        ch.deinit();
    }

    const result = rule.match(&ctx);

    try TestHelpers.expectMatch(result, "bar");
}

test "Choice fails if no alternatives match" {
    const allocator = testing.allocator;
    var ctx = TestContext.init(allocator, "qux");

    const rule = try choice(allocator, &.{
        terminal("foo"),
        terminal("bar"),
        terminal("baz"),
    });
    defer {
        var ch = rule.choice;
        ch.deinit();
    }

    const result = rule.match(&ctx);

    try TestHelpers.expectNoMatch(result);
}

test "Optional matches when present" {
    const allocator = testing.allocator;
    var ctx = TestContext.init(allocator, "foo");

    const foo_rule = terminal("foo");
    const rule = optional(&foo_rule);
    const result = rule.match(&ctx);

    try TestHelpers.expectMatch(result, "foo");
}

test "Optional succeeds when absent" {
    const allocator = testing.allocator;
    var ctx = TestContext.init(allocator, "bar");

    const foo_rule = terminal("foo");
    const rule = optional(&foo_rule);
    const result = rule.match(&ctx);

    try testing.expect(result.success);
    try TestHelpers.expectConsumed(result, 0);
}

test "Repeat matches multiple occurrences" {
    const allocator = testing.allocator;
    var ctx = TestContext.init(allocator, "aaabbb");

    const a_rule = terminal("a");
    const rule = repeat(&a_rule);
    const result = rule.match(&ctx);

    try testing.expect(result.success);
    try TestHelpers.expectConsumed(result, 3);
    try TestHelpers.expectRemaining(result, "bbb");
}

test "Repeat succeeds with zero matches" {
    const allocator = testing.allocator;
    var ctx = TestContext.init(allocator, "bbb");

    const a_rule = terminal("a");
    const rule = repeat(&a_rule);
    const result = rule.match(&ctx);

    try testing.expect(result.success);
    try TestHelpers.expectConsumed(result, 0);
}

test "Repeat1 matches one or more" {
    const allocator = testing.allocator;
    var ctx = TestContext.init(allocator, "aaabbb");

    const a_rule = terminal("a");
    const rule = repeat1(&a_rule);
    const result = rule.match(&ctx);

    try testing.expect(result.success);
    try TestHelpers.expectConsumed(result, 3);
}

test "Repeat1 fails with zero matches" {
    const allocator = testing.allocator;
    var ctx = TestContext.init(allocator, "bbb");

    const a_rule = terminal("a");
    const rule = repeat1(&a_rule);
    const result = rule.match(&ctx);

    try TestHelpers.expectNoMatch(result);
}
