const std = @import("std");
const test_framework = @import("test_framework.zig");
const MatchResult = test_framework.MatchResult;
const TestContext = test_framework.TestContext;

/// Forward declaration for Rule
const Rule = @import("rule.zig").Rule;

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