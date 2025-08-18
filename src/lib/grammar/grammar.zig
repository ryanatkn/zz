const std = @import("std");
const rule = @import("rule.zig");
const test_framework = @import("test_framework.zig");

const TestContext = test_framework.TestContext;

/// Complete grammar definition with named rules
/// This is the "compiled" grammar that can parse input
pub const Grammar = struct {
    allocator: std.mem.Allocator,
    rules: std.StringHashMap(rule.Rule),
    start_rule: []const u8,

    pub fn init(allocator: std.mem.Allocator, start_rule: []const u8) Grammar {
        return .{
            .allocator = allocator,
            .rules = std.StringHashMap(rule.Rule).init(allocator),
            .start_rule = start_rule,
        };
    }

    pub fn deinit(self: *Grammar) void {
        // Clean up all rules that need cleanup
        var iterator = self.rules.iterator();
        while (iterator.next()) |entry| {
            self.deinitRule(entry.value_ptr.*);
        }
        self.rules.deinit();
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

    /// Create a simple default grammar for testing
    pub fn default() Grammar {
        var grammar = Grammar{
            .allocator = std.heap.page_allocator, // Use page allocator for default
            .rules = std.StringHashMap(rule.Rule).init(std.heap.page_allocator),
            .start_rule = "document",
        };

        // Add a simple terminal rule for basic parsing
        const terminal_rule = rule.Rule{ .terminal = .{ .literal = "" } };
        grammar.rules.put("document", terminal_rule) catch {};

        return grammar;
    }

    /// Get a rule by name
    pub fn getRule(self: Grammar, name: []const u8) ?rule.Rule {
        return self.rules.get(name);
    }

    /// Get the start rule
    pub fn getStartRule(self: Grammar) ?rule.Rule {
        return self.getRule(self.start_rule);
    }

    /// Parse input using the start rule
    pub fn parse(self: Grammar, input: []const u8) !bool {
        const start = self.getStartRule() orelse return error.NoStartRule;
        var ctx = TestContext.init(self.allocator, input);
        const result = start.match(&ctx);
        return result.success and ctx.position == input.len;
    }

    /// Create a new builder for this grammar
    pub fn builder(allocator: std.mem.Allocator) @import("builder.zig").Builder {
        return @import("builder.zig").Builder.init(allocator);
    }
};
