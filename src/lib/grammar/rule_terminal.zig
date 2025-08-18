const std = @import("std");
const test_framework = @import("test_framework.zig");
const MatchResult = test_framework.MatchResult;
const TestContext = test_framework.TestContext;

// Forward declaration for Rule
const Rule = @import("rule.zig").Rule;

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
