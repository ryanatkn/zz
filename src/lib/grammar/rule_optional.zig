const std = @import("std");
const test_framework = @import("test_framework.zig");
const MatchResult = test_framework.MatchResult;
const TestContext = test_framework.TestContext;

/// Forward declaration for Rule
const Rule = @import("rule.zig").Rule;

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
