const std = @import("std");
const testing = std.testing;
const test_framework = @import("test_framework.zig");
const MatchResult = test_framework.MatchResult;
const TestContext = test_framework.TestContext;
const TestHelpers = test_framework.TestHelpers;

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

/// Terminal rule - matches a literal string
pub const Terminal = struct {
    literal: []const u8,
    
    pub fn init(literal: []const u8) Terminal {
        return .{ .literal = literal };
    }
    
    pub fn match(self: Terminal, ctx: *TestContext) MatchResult {
        const remaining = ctx.remaining();
        
        // Check if we have enough input
        if (remaining.len < self.literal.len) {
            return MatchResult.failure();
        }
        
        // Check if input starts with our literal
        if (std.mem.startsWith(u8, remaining, self.literal)) {
            ctx.advance(self.literal.len);
            return MatchResult.init(true, self.literal.len, remaining);
        }
        
        return MatchResult.failure();
    }
    
    pub fn toRule(self: Terminal) Rule {
        return .{ .terminal = self };
    }
};

/// Sequence rule - matches multiple rules in order
pub const Sequence = struct {
    rules: []const Rule,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, rules: []const Rule) !Sequence {
        const rules_copy = try allocator.dupe(Rule, rules);
        return .{
            .rules = rules_copy,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *Sequence) void {
        self.allocator.free(self.rules);
    }
    
    pub fn match(self: Sequence, ctx: *TestContext) MatchResult {
        const start_pos = ctx.position;
        var total_consumed: usize = 0;
        
        // Try to match each rule in sequence
        for (self.rules) |rule| {
            const result = rule.match(ctx);
            if (!result.success) {
                // Failed - restore position and return failure
                ctx.position = start_pos;
                return MatchResult.failure();
            }
            total_consumed += result.consumed;
        }
        
        // All rules matched successfully
        return MatchResult.init(true, total_consumed, ctx.input[start_pos..]);
    }
    
    pub fn toRule(self: Sequence) Rule {
        return .{ .sequence = self };
    }
};

/// Choice rule - matches one of several alternatives
pub const Choice = struct {
    choices: []const Rule,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, choices: []const Rule) !Choice {
        const choices_copy = try allocator.dupe(Rule, choices);
        return .{
            .choices = choices_copy,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *Choice) void {
        self.allocator.free(self.choices);
    }
    
    pub fn match(self: Choice, ctx: *TestContext) MatchResult {
        const start_pos = ctx.position;
        
        // Try each choice in order
        for (self.choices) |choice_rule| {
            const result = choice_rule.match(ctx);
            if (result.success) {
                return result;
            }
            // Reset position for next attempt
            ctx.position = start_pos;
        }
        
        // No choices matched
        return MatchResult.failure();
    }
    
    pub fn toRule(self: Choice) Rule {
        return .{ .choice = self };
    }
};

/// Optional rule - matches zero or one occurrence
pub const Optional = struct {
    rule: *const Rule,
    
    pub fn init(rule: *const Rule) Optional {
        return .{ .rule = rule };
    }
    
    pub fn match(self: Optional, ctx: *TestContext) MatchResult {
        const result = self.rule.match(ctx);
        if (result.success) {
            return result;
        }
        // Optional always succeeds, even if underlying rule doesn't match
        return MatchResult.init(true, 0, ctx.remaining());
    }
    
    pub fn toRule(self: Optional) Rule {
        return .{ .optional = self };
    }
};

/// Repeat rule - matches zero or more occurrences
pub const Repeat = struct {
    rule: *const Rule,
    
    pub fn init(rule: *const Rule) Repeat {
        return .{ .rule = rule };
    }
    
    pub fn match(self: Repeat, ctx: *TestContext) MatchResult {
        const start_pos = ctx.position;
        var total_consumed: usize = 0;
        
        // Keep matching while we can
        while (true) {
            const result = self.rule.match(ctx);
            if (!result.success) {
                break;
            }
            total_consumed += result.consumed;
            
            // Prevent infinite loops on zero-width matches
            if (result.consumed == 0) {
                break;
            }
        }
        
        // Repeat always succeeds (zero or more)
        return MatchResult.init(true, total_consumed, ctx.input[start_pos..]);
    }
    
    pub fn toRule(self: Repeat) Rule {
        return .{ .repeat = self };
    }
};

/// Repeat1 rule - matches one or more occurrences
pub const Repeat1 = struct {
    rule: *const Rule,
    
    pub fn init(rule: *const Rule) Repeat1 {
        return .{ .rule = rule };
    }
    
    pub fn match(self: Repeat1, ctx: *TestContext) MatchResult {
        const start_pos = ctx.position;
        
        // Must match at least once
        const first = self.rule.match(ctx);
        if (!first.success) {
            return MatchResult.failure();
        }
        
        var total_consumed = first.consumed;
        
        // Then match zero or more times
        while (true) {
            const result = self.rule.match(ctx);
            if (!result.success) {
                break;
            }
            total_consumed += result.consumed;
            
            // Prevent infinite loops
            if (result.consumed == 0) {
                break;
            }
        }
        
        return MatchResult.init(true, total_consumed, ctx.input[start_pos..]);
    }
    
    pub fn toRule(self: Repeat1) Rule {
        return .{ .repeat1 = self };
    }
};

// Helper functions for convenient rule creation
pub fn terminal(literal: []const u8) Rule {
    return Terminal.init(literal).toRule();
}

pub fn sequence(allocator: std.mem.Allocator, rules: []const Rule) !Rule {
    const seq = try Sequence.init(allocator, rules);
    return seq.toRule();
}

pub fn choice(allocator: std.mem.Allocator, choices: []const Rule) !Rule {
    const ch = try Choice.init(allocator, choices);
    return ch.toRule();
}

pub fn optional(rule: *const Rule) Rule {
    return Optional.init(rule).toRule();
}

pub fn repeat(rule: *const Rule) Rule {
    return Repeat.init(rule).toRule();
}

pub fn repeat1(rule: *const Rule) Rule {
    return Repeat1.init(rule).toRule();
}

// ============================================================================
// Tests
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