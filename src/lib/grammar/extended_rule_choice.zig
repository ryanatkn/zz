const std = @import("std");
const extended_rules = @import("extended_rules.zig");
const ExtendedRule = extended_rules.ExtendedRule;

/// Extended choice that can contain rule references
pub const ExtendedChoice = struct {
    choices: []const ExtendedRule,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, choices: []const ExtendedRule) !ExtendedChoice {
        const choices_copy = try allocator.dupe(ExtendedRule, choices);
        return .{
            .choices = choices_copy,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *ExtendedChoice) void {
        self.allocator.free(self.choices);
    }
};