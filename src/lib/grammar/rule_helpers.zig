const std = @import("std");
const rule = @import("rule.zig");

/// Helper functions for convenient rule creation

pub fn terminal(literal: []const u8) rule.Rule {
    return rule.Terminal.init(literal).toRule();
}

pub fn sequence(allocator: std.mem.Allocator, rules: []const rule.Rule) !rule.Rule {
    const seq = try rule.Sequence.init(allocator, rules);
    return seq.toRule();
}

pub fn choice(allocator: std.mem.Allocator, choices: []const rule.Rule) !rule.Rule {
    const ch = try rule.Choice.init(allocator, choices);
    return ch.toRule();
}

pub fn optional(rule_ptr: *const rule.Rule) rule.Rule {
    return rule.Optional.init(rule_ptr).toRule();
}

pub fn repeat(rule_ptr: *const rule.Rule) rule.Rule {
    return rule.Repeat.init(rule_ptr).toRule();
}

pub fn repeat1(rule_ptr: *const rule.Rule) rule.Rule {
    return rule.Repeat1.init(rule_ptr).toRule();
}