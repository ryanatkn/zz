const std = @import("std");
const extended_rules = @import("extended_rules.zig");
const ExtendedRule = extended_rules.ExtendedRule;

/// Extended repeat1 that can contain rule references
pub const ExtendedRepeat1 = struct {
    rule: *const ExtendedRule,

    pub fn init(rule: *const ExtendedRule) ExtendedRepeat1 {
        return .{ .rule = rule };
    }
};
