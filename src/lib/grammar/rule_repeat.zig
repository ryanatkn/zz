const std = @import("std");
const test_framework = @import("test_framework.zig");
const MatchResult = test_framework.MatchResult;
const TestContext = test_framework.TestContext;

/// Forward declaration for Rule
const Rule = @import("rule.zig").Rule;

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
