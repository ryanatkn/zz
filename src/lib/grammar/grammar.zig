const std = @import("std");
const rule = @import("rule.zig");
const test_framework = @import("test_framework.zig");
const ast_rules = @import("../ast/rules.zig");
const Builder = @import("builder.zig").Builder;

const CommonRules = ast_rules.CommonRules;

const TestContext = test_framework.TestContext;

/// Complete grammar definition with rule IDs
/// This is the "compiled" grammar that can parse input
pub const Grammar = struct {
    allocator: std.mem.Allocator,
    rules: std.HashMap(u16, rule.Rule, std.hash_map.AutoContext(u16), std.hash_map.default_max_load_percentage),
    start_rule_id: u16,
    // Optional string names for debugging (can be removed in production)
    rule_names: ?std.HashMap(u16, []const u8, std.hash_map.AutoContext(u16), std.hash_map.default_max_load_percentage) = null,

    pub fn init(allocator: std.mem.Allocator, start_rule_id: u16) Grammar {
        return .{
            .allocator = allocator,
            .rules = std.HashMap(u16, rule.Rule, std.hash_map.AutoContext(u16), std.hash_map.default_max_load_percentage).init(allocator),
            .start_rule_id = start_rule_id,
        };
    }

    pub fn deinit(self: *Grammar) void {
        // Clean up all rules that need cleanup
        var iterator = self.rules.iterator();
        while (iterator.next()) |entry| {
            self.deinitRule(entry.value_ptr.*);
        }
        self.rules.deinit();

        // Clean up optional rule names
        if (self.rule_names) |*names| {
            names.deinit();
        }
    }

    /// Recursively deinit a rule and all its nested rules
    fn deinitRule(self: *Grammar, rule_val: rule.Rule) void {
        switch (rule_val) {
            .sequence => |s| {
                // First recursively deinit nested rules
                for (s.rules) |nested_rule| {
                    self.deinitRule(nested_rule);
                }
                // Then free the sequence array - need mutable access
                var mutable_s = s;
                mutable_s.deinit();
            },
            .choice => |c| {
                // First recursively deinit nested rules
                for (c.choices) |nested_rule| {
                    self.deinitRule(nested_rule);
                }
                // Then free the choices array - need mutable access
                var mutable_c = c;
                mutable_c.deinit();
            },
            .optional => |*o| {
                // First recursively deinit the nested rule
                self.deinitRule(o.rule.*);
                // Then free the allocated Rule pointer
                self.allocator.destroy(o.rule);
            },
            .repeat => |*r| {
                // First recursively deinit the nested rule
                self.deinitRule(r.rule.*);
                // Then free the allocated Rule pointer
                self.allocator.destroy(r.rule);
            },
            .repeat1 => |*r| {
                // First recursively deinit the nested rule
                self.deinitRule(r.rule.*);
                // Then free the allocated Rule pointer
                self.allocator.destroy(r.rule);
            },
            else => {}, // Terminal rules don't need cleanup
        }
    }

    /// Add a rule by ID
    pub fn addRule(self: *Grammar, rule_id: u16, rule_def: rule.Rule) !void {
        try self.rules.put(rule_id, rule_def);
    }

    /// Add a rule by ID with optional debug name
    pub fn addRuleWithName(self: *Grammar, rule_id: u16, rule_def: rule.Rule, name: []const u8) !void {
        try self.rules.put(rule_id, rule_def);

        if (self.rule_names == null) {
            self.rule_names = std.HashMap(u16, []const u8, std.hash_map.AutoContext(u16), std.hash_map.default_max_load_percentage).init(self.allocator);
        }

        if (self.rule_names) |*names| {
            try names.put(rule_id, name);
        }
    }

    /// Get rule name for debugging (returns null if no debug names)
    pub fn getRuleName(self: Grammar, rule_id: u16) ?[]const u8 {
        if (self.rule_names) |names| {
            return names.get(rule_id);
        }
        return null;
    }

    /// Create a simple default grammar for testing
    pub fn default() Grammar {
        var grammar = Grammar{
            .allocator = std.heap.page_allocator, // Use page allocator for default
            .rules = std.HashMap(u16, rule.Rule, std.hash_map.AutoContext(u16), std.hash_map.default_max_load_percentage).init(std.heap.page_allocator),
            .start_rule_id = @intFromEnum(CommonRules.root),
        };

        // Add a simple terminal rule for basic parsing
        const terminal_rule = rule.Rule{ .terminal = .{ .literal = "" } };
        grammar.rules.put(@intFromEnum(CommonRules.root), terminal_rule) catch {};

        return grammar;
    }

    /// Get a rule by ID
    pub fn getRule(self: Grammar, rule_id: u16) ?rule.Rule {
        return self.rules.get(rule_id);
    }

    /// Get the start rule
    pub fn getStartRule(self: Grammar) ?rule.Rule {
        return self.getRule(self.start_rule_id);
    }

    /// Parse input using the start rule
    pub fn parse(self: Grammar, input: []const u8) !bool {
        const start = self.getStartRule() orelse return error.NoStartRule;
        var ctx = TestContext.init(self.allocator, input);
        const result = start.match(&ctx);
        return result.success and ctx.position == input.len;
    }

    /// Create a new builder for this grammar
    pub fn builder(allocator: std.mem.Allocator) Builder {
        return Builder.init(allocator);
    }
};
