const std = @import("std");
const rule = @import("rule.zig");
const extended_rules = @import("extended_rules.zig");
const ExtendedRule = extended_rules.ExtendedRule;

/// Rule resolution utilities for converting ExtendedRules to basic Rules
pub const Resolver = struct {
    allocator: std.mem.Allocator,
    rules: *const std.StringHashMap(ExtendedRule),
    
    pub fn init(allocator: std.mem.Allocator, rules: *const std.StringHashMap(ExtendedRule)) Resolver {
        return .{
            .allocator = allocator,
            .rules = rules,
        };
    }
    
    /// Resolve an extended rule to a basic rule
    pub fn resolveExtendedRule(self: Resolver, extended_rule: ExtendedRule) !rule.Rule {
        return switch (extended_rule) {
            .terminal => |t| t.toRule(),
            .sequence => |s| {
                // Create new sequence with resolved rules
                var resolved_rules = std.ArrayList(rule.Rule).init(self.allocator);
                defer resolved_rules.deinit();
                
                for (s.rules) |r| {
                    const resolved = try self.resolveExtendedRule(r);
                    try resolved_rules.append(resolved);
                }
                
                const seq = try rule.Sequence.init(self.allocator, resolved_rules.items);
                return seq.toRule();
            },
            .choice => |c| {
                // Create new choice with resolved rules
                var resolved_choices = std.ArrayList(rule.Rule).init(self.allocator);
                defer resolved_choices.deinit();
                
                for (c.choices) |choice| {
                    const resolved = try self.resolveExtendedRule(choice);
                    try resolved_choices.append(resolved);
                }
                
                const ch = try rule.Choice.init(self.allocator, resolved_choices.items);
                return ch.toRule();
            },
            .optional => |o| {
                const resolved_rule = try self.allocator.create(rule.Rule);
                resolved_rule.* = try self.resolveExtendedRule(o.rule.*);
                return rule.Optional.init(resolved_rule).toRule();
            },
            .repeat => |r| {
                const resolved_rule = try self.allocator.create(rule.Rule);
                resolved_rule.* = try self.resolveExtendedRule(r.rule.*);
                return rule.Repeat.init(resolved_rule).toRule();
            },
            .repeat1 => |r| {
                const resolved_rule = try self.allocator.create(rule.Rule);
                resolved_rule.* = try self.resolveExtendedRule(r.rule.*);
                return rule.Repeat1.init(resolved_rule).toRule();
            },
            .rule_ref => |ref| {
                // Resolve by looking up the referenced rule
                const referenced_rule = self.rules.get(ref.name) orelse return error.UndefinedRuleReference;
                return self.resolveExtendedRule(referenced_rule);
            },
        };
    }
};