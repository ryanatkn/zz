const std = @import("std");
const rule = @import("rule.zig");
const extended_rules = @import("extended_rules.zig");
const ExtendedRule = extended_rules.ExtendedRule;
const ExtendedSequence = extended_rules.ExtendedSequence;
const ExtendedChoice = extended_rules.ExtendedChoice;
const ExtendedOptional = extended_rules.ExtendedOptional;
const ExtendedRepeat = extended_rules.ExtendedRepeat;
const ExtendedRepeat1 = extended_rules.ExtendedRepeat1;
const RuleRef = extended_rules.RuleRef;

/// Helper functions for convenient extended rule creation
pub fn terminal(literal: []const u8) ExtendedRule {
    return .{ .terminal = rule.Terminal.init(literal) };
}

pub fn sequence(allocator: std.mem.Allocator, rules: []const ExtendedRule) !ExtendedRule {
    const seq = try ExtendedSequence.init(allocator, rules);
    return .{ .sequence = seq };
}

pub fn choice(allocator: std.mem.Allocator, choices: []const ExtendedRule) !ExtendedRule {
    const ch = try ExtendedChoice.init(allocator, choices);
    return .{ .choice = ch };
}

pub fn optional(extended_rule: *const ExtendedRule) ExtendedRule {
    return .{ .optional = ExtendedOptional.init(extended_rule) };
}

pub fn repeat(extended_rule: *const ExtendedRule) ExtendedRule {
    return .{ .repeat = ExtendedRepeat.init(extended_rule) };
}

pub fn repeat1(extended_rule: *const ExtendedRule) ExtendedRule {
    return .{ .repeat1 = ExtendedRepeat1.init(extended_rule) };
}

pub fn ref(name: []const u8) ExtendedRule {
    return .{ .rule_ref = RuleRef.init(name) };
}
