const std = @import("std");
const extended_rules = @import("extended_rules.zig");
const ExtendedRule = extended_rules.ExtendedRule;

/// Grammar validation utilities
pub const Validator = struct {
    allocator: std.mem.Allocator,
    rules: *const std.StringHashMap(ExtendedRule),

    pub fn init(allocator: std.mem.Allocator, rules: *const std.StringHashMap(ExtendedRule)) Validator {
        return .{
            .allocator = allocator,
            .rules = rules,
        };
    }

    /// Validate that all rule references point to defined rules
    pub fn validateReferences(self: Validator) !void {
        var iterator = self.rules.iterator();
        while (iterator.next()) |entry| {
            try self.validateRuleReferences(entry.value_ptr.*);
        }
    }

    fn validateRuleReferences(self: Validator, extended_rule: ExtendedRule) !void {
        switch (extended_rule) {
            .rule_ref => |ref| {
                if (!self.rules.contains(ref.name)) {
                    return error.UndefinedRuleReference;
                }
            },
            .sequence => |seq| {
                for (seq.rules) |r| {
                    try self.validateRuleReferences(r);
                }
            },
            .choice => |choice| {
                for (choice.choices) |c| {
                    try self.validateRuleReferences(c);
                }
            },
            .optional => |opt| {
                try self.validateRuleReferences(opt.rule.*);
            },
            .repeat => |rep| {
                try self.validateRuleReferences(rep.rule.*);
            },
            .repeat1 => |rep| {
                try self.validateRuleReferences(rep.rule.*);
            },
            .terminal => {}, // No references to validate
        }
    }

    /// Check for circular dependencies in rule definitions
    pub fn checkCircularDependencies(self: Validator) !void {
        var visited = std.StringHashMap(void).init(self.allocator);
        defer visited.deinit();

        var in_progress = std.StringHashMap(void).init(self.allocator);
        defer in_progress.deinit();

        var iterator = self.rules.iterator();
        while (iterator.next()) |entry| {
            if (!visited.contains(entry.key_ptr.*)) {
                try self.visitRule(entry.key_ptr.*, &visited, &in_progress);
            }
        }
    }

    fn visitRule(self: Validator, rule_name: []const u8, visited: *std.StringHashMap(void), in_progress: *std.StringHashMap(void)) (error{ CircularDependency, RuleNotFound, OutOfMemory })!void {
        if (in_progress.contains(rule_name)) {
            return error.CircularDependency;
        }

        if (visited.contains(rule_name)) {
            return; // Already processed
        }

        try in_progress.put(rule_name, {});

        // Visit dependencies
        const extended_rule = self.rules.get(rule_name) orelse return error.RuleNotFound;
        try self.visitRuleDependencies(extended_rule, visited, in_progress);

        _ = in_progress.remove(rule_name);
        try visited.put(rule_name, {});
    }

    fn visitRuleDependencies(self: Validator, extended_rule: ExtendedRule, visited: *std.StringHashMap(void), in_progress: *std.StringHashMap(void)) !void {
        switch (extended_rule) {
            .rule_ref => |ref| {
                try self.visitRule(ref.name, visited, in_progress);
            },
            .sequence => |seq| {
                for (seq.rules) |r| {
                    try self.visitRuleDependencies(r, visited, in_progress);
                }
            },
            .choice => |choice| {
                for (choice.choices) |c| {
                    try self.visitRuleDependencies(c, visited, in_progress);
                }
            },
            .optional => |opt| {
                try self.visitRuleDependencies(opt.rule.*, visited, in_progress);
            },
            .repeat => |rep| {
                try self.visitRuleDependencies(rep.rule.*, visited, in_progress);
            },
            .repeat1 => |rep| {
                try self.visitRuleDependencies(rep.rule.*, visited, in_progress);
            },
            .terminal => {}, // No dependencies
        }
    }
};
