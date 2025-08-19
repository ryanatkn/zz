const std = @import("std");
const testing = std.testing;
const extended_rules = @import("extended_rules.zig");
const validation = @import("validation.zig");
const resolver = @import("resolver.zig");
const Grammar = @import("grammar.zig").Grammar;

const ExtendedRule = extended_rules.ExtendedRule;

/// Builder for creating grammars with fluent API
/// This constructs a Grammar using the fluent API
pub const Builder = struct {
    allocator: std.mem.Allocator,
    rules: std.StringHashMap(ExtendedRule),
    start_rule: ?[]const u8,
    // Dynamic rule ID mapping for test rules
    rule_name_to_id: std.StringHashMap(u16),
    next_test_rule_id: u16,

    pub fn init(allocator: std.mem.Allocator) Builder {
        const TestRules = @import("../ast/rules.zig").TestRules;
        return .{
            .allocator = allocator,
            .rules = std.StringHashMap(ExtendedRule).init(allocator),
            .start_rule = null,
            .rule_name_to_id = std.StringHashMap(u16).init(allocator),
            .next_test_rule_id = TestRules.range_start,
        };
    }

    pub fn deinit(self: *Builder) void {
        // Clean up rules that need cleanup
        var iterator = self.rules.iterator();
        while (iterator.next()) |entry| {
            switch (entry.value_ptr.*) {
                .sequence => |*s| s.deinit(),
                .choice => |*c| c.deinit(),
                else => {},
            }
        }
        self.rules.deinit();

        // Clean up allocated rule names in the mapping
        var name_iterator = self.rule_name_to_id.iterator();
        while (name_iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.rule_name_to_id.deinit();
    }

    /// Define a named rule
    pub fn define(self: *Builder, name: []const u8, extended_rule: ExtendedRule) !*Builder {
        try self.rules.put(name, extended_rule);
        return self;
    }

    /// Set the start rule
    pub fn start(self: *Builder, rule_name: []const u8) *Builder {
        self.start_rule = rule_name;
        return self;
    }

    /// Get or create a rule ID for the given rule name
    fn getOrCreateRuleId(self: *Builder, rule_name: []const u8) !u16 {
        const CommonRules = @import("../ast/rules.zig").CommonRules;
        const TestRules = @import("../ast/rules.zig").TestRules;

        // Use a static string map for efficient common rule lookup
        const CommonRuleLookup = std.StaticStringMap(u16).initComptime(.{
            .{ "root", @intFromEnum(CommonRules.root) },
            .{ "object", @intFromEnum(CommonRules.object) },
            .{ "array", @intFromEnum(CommonRules.array) },
            .{ "string_literal", @intFromEnum(CommonRules.string_literal) },
            .{ "number_literal", @intFromEnum(CommonRules.number_literal) },
            .{ "boolean_literal", @intFromEnum(CommonRules.boolean_literal) },
            .{ "null_literal", @intFromEnum(CommonRules.null_literal) },
            .{ "identifier", @intFromEnum(CommonRules.identifier) },
        });

        // Check if it's a well-known common rule (O(1) lookup)
        if (CommonRuleLookup.get(rule_name)) |rule_id| {
            return rule_id;
        }

        // Check if we already have an ID for this test rule name
        if (self.rule_name_to_id.get(rule_name)) |existing_id| {
            return existing_id;
        }

        // Generate a new test rule ID
        if (self.next_test_rule_id > TestRules.range_end) {
            return error.TooManyTestRules;
        }

        const new_id = self.next_test_rule_id;
        self.next_test_rule_id += 1;

        // Store the mapping (duplicate the string for ownership)
        const owned_name = try self.allocator.dupe(u8, rule_name);
        try self.rule_name_to_id.put(owned_name, new_id);

        return new_id;
    }

    /// Build the final grammar with validation
    pub fn build(self: *Builder) !Grammar {
        const start_rule_name = self.start_rule orelse return error.NoStartRule;

        // Validate that start rule exists
        if (!self.rules.contains(start_rule_name)) {
            return error.StartRuleNotDefined;
        }

        // Use validation and resolver modules
        const validator = validation.Validator.init(self.allocator, &self.rules);

        // Validate all rule references
        try validator.validateReferences();

        // Check for circular dependencies
        try validator.checkCircularDependencies();

        // Get or create rule ID for start rule
        const start_rule_id = try self.getOrCreateRuleId(start_rule_name);

        var grammar = Grammar.init(self.allocator, start_rule_id);
        const res = resolver.Resolver.init(self.allocator, &self.rules);

        var iterator = self.rules.iterator();
        while (iterator.next()) |entry| {
            const resolved = try res.resolveExtendedRule(entry.value_ptr.*);

            // Get or create rule ID for this rule name
            const rule_name = entry.key_ptr.*;
            const rule_id = try self.getOrCreateRuleId(rule_name);

            try grammar.rules.put(rule_id, resolved);
        }

        return grammar;
    }
};

// Re-export helper functions from extended_rules for convenience in tests
const terminal = extended_rules.terminal;
const sequence = extended_rules.sequence;
const choice = extended_rules.choice;
const optional = extended_rules.optional;
const repeat = extended_rules.repeat;
const repeat1 = extended_rules.repeat1;
const ref = extended_rules.ref;

// ============================================================================
// Tests
// ============================================================================

test "Builder basic usage" {
    const allocator = testing.allocator;

    var builder = Builder.init(allocator);
    defer builder.deinit();

    // Define simple rules
    _ = try builder.define("hello", terminal("hello"));
    _ = try builder.define("world", terminal("world"));
    _ = builder.start("hello");

    var grammar = try builder.build();
    defer grammar.deinit();

    // Test that rules exist - since these are test rules, they'll be in the test range
    const TestRules = @import("../ast/rules.zig").TestRules;

    // Test that start rule exists
    try testing.expect(grammar.getStartRule() != null);

    // Test that we have rules in the test range (the builder created IDs for "hello" and "world")
    const start_rule_id = grammar.start_rule_id;
    try testing.expect(TestRules.isTestRule(start_rule_id) or start_rule_id < 256); // Could be common rule
    try testing.expect(grammar.getRule(start_rule_id) != null);
}

test "Builder fluent API" {
    const allocator = testing.allocator;

    var builder = Grammar.builder(allocator);
    defer builder.deinit();

    // Test fluent chaining
    _ = try builder
        .define("digit", terminal("1"));
    _ = try builder
        .define("number", terminal("123"));
    _ = builder.start("number");

    var grammar = try builder.build();
    defer grammar.deinit();

    try testing.expect(try grammar.parse("123"));
    try testing.expect(!try grammar.parse("456"));
}

test "Builder validates undefined references" {
    const allocator = testing.allocator;

    var builder = Builder.init(allocator);
    defer builder.deinit();

    // Reference undefined rule
    _ = try builder.define("expr", ref("undefined"));
    _ = builder.start("expr");

    // Should fail validation
    try testing.expectError(error.UndefinedRuleReference, builder.build());
}

test "Builder detects circular dependencies" {
    const allocator = testing.allocator;

    var builder = Builder.init(allocator);
    defer builder.deinit();

    // Create circular dependency: a -> b -> a
    _ = try builder.define("a", ref("b"));
    _ = try builder.define("b", ref("a"));
    _ = builder.start("a");

    // Should detect circular dependency
    try testing.expectError(error.CircularDependency, builder.build());
}

test "Builder requires start rule" {
    const allocator = testing.allocator;

    var builder = Builder.init(allocator);
    defer builder.deinit();

    _ = try builder.define("hello", terminal("hello"));
    // No start rule set

    try testing.expectError(error.NoStartRule, builder.build());
}

test "Builder validates start rule exists" {
    const allocator = testing.allocator;

    var builder = Builder.init(allocator);
    defer builder.deinit();

    _ = try builder.define("hello", terminal("hello"));
    _ = builder.start("nonexistent");

    try testing.expectError(error.StartRuleNotDefined, builder.build());
}

test "Builder handles rule references correctly" {
    const allocator = testing.allocator;

    var builder = Grammar.builder(allocator);
    defer builder.deinit();

    // Build a simple arithmetic grammar with references
    // digit = "1" | "2" | "3"
    _ = try builder.define("digit", try choice(allocator, &.{
        terminal("1"),
        terminal("2"),
        terminal("3"),
    }));

    // number = digit+
    _ = try builder.define("number", repeat1(&ref("digit")));

    // operator = "+" | "-"
    _ = try builder.define("operator", try choice(allocator, &.{
        terminal("+"),
        terminal("-"),
    }));

    // expression = number " " operator " " number
    _ = try builder.define("expression", try sequence(allocator, &.{
        ref("number"),
        terminal(" "),
        ref("operator"),
        terminal(" "),
        ref("number"),
    }));

    _ = builder.start("expression");

    var grammar = try builder.build();
    defer grammar.deinit();

    // Test valid expressions
    try testing.expect(try grammar.parse("1 + 2"));
    try testing.expect(try grammar.parse("123 - 321"));
    try testing.expect(try grammar.parse("3 + 1"));

    // Test invalid expressions
    try testing.expect(!try grammar.parse("1 +"));
    try testing.expect(!try grammar.parse("+ 2"));
    try testing.expect(!try grammar.parse("1 * 2")); // * not defined
    try testing.expect(!try grammar.parse("4 + 5")); // 4,5 not defined as digits
}
