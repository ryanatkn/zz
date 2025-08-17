const std = @import("std");
const extended_rules = @import("extended_rules.zig");
const ExtendedRule = extended_rules.ExtendedRule;

/// Extended repeat that can contain rule references
pub const ExtendedRepeat = struct {
    rule: *const ExtendedRule,
    
    pub fn init(rule: *const ExtendedRule) ExtendedRepeat {
        return .{ .rule = rule };
    }
};