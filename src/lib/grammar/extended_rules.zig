const std = @import("std");
const rule = @import("rule.zig");

/// Rule reference for forward/circular rule definitions
pub const RuleRef = struct {
    name: []const u8,
    
    pub fn init(name: []const u8) RuleRef {
        return .{ .name = name };
    }
};

/// Extended sequence that can contain rule references
pub const ExtendedSequence = struct {
    rules: []const ExtendedRule,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, rules: []const ExtendedRule) !ExtendedSequence {
        const rules_copy = try allocator.dupe(ExtendedRule, rules);
        return .{
            .rules = rules_copy,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *ExtendedSequence) void {
        self.allocator.free(self.rules);
    }
};

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

/// Extended optional that can contain rule references
pub const ExtendedOptional = struct {
    rule: *const ExtendedRule,
    
    pub fn init(inner_rule: *const ExtendedRule) ExtendedOptional {
        return .{ .rule = inner_rule };
    }
};

/// Extended repeat that can contain rule references
pub const ExtendedRepeat = struct {
    rule: *const ExtendedRule,
    
    pub fn init(inner_rule: *const ExtendedRule) ExtendedRepeat {
        return .{ .rule = inner_rule };
    }
};

/// Extended repeat1 that can contain rule references
pub const ExtendedRepeat1 = struct {
    rule: *const ExtendedRule,
    
    pub fn init(inner_rule: *const ExtendedRule) ExtendedRepeat1 {
        return .{ .rule = inner_rule };
    }
};

/// Extended Rule type that includes rule references
/// This is used during grammar building and gets resolved to basic Rules
pub const ExtendedRule = union(enum) {
    terminal: rule.Terminal,
    sequence: ExtendedSequence,
    choice: ExtendedChoice,
    optional: ExtendedOptional,
    repeat: ExtendedRepeat,
    repeat1: ExtendedRepeat1,
    rule_ref: RuleRef,
    
    /// Get a human-readable name for this rule
    pub fn name(self: ExtendedRule) []const u8 {
        return switch (self) {
            .terminal => "terminal",
            .sequence => "sequence",
            .choice => "choice",
            .optional => "optional",
            .repeat => "repeat",
            .repeat1 => "repeat1",
            .rule_ref => |r| r.name,
        };
    }
};

// Helper functions for convenient extended rule creation
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