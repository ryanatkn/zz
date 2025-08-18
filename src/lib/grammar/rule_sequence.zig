const std = @import("std");
const test_framework = @import("test_framework.zig");
const MatchResult = test_framework.MatchResult;
const TestContext = test_framework.TestContext;

/// Forward declaration for Rule
const Rule = @import("rule.zig").Rule;

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
