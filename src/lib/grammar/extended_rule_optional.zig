const std = @import("std");
const extended_rules = @import("extended_rules.zig");
const ExtendedRule = extended_rules.ExtendedRule;

/// Extended optional that can contain rule references
pub const ExtendedOptional = struct {
    rule: *const ExtendedRule,

    pub fn init(rule: *const ExtendedRule) ExtendedOptional {
        return .{ .rule = rule };
    }
};
