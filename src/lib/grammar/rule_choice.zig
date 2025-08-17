const std = @import("std");
const test_framework = @import("test_framework.zig");
const MatchResult = test_framework.MatchResult;
const TestContext = test_framework.TestContext;

/// Forward declaration for Rule
const Rule = @import("rule.zig").Rule;

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