const std = @import("std");
const testing = std.testing;
const rule = @import("../rule.zig");
const test_framework = @import("../test_framework.zig");
const TestContext = test_framework.TestContext;
const TestHelpers = test_framework.TestHelpers;

/// Example arithmetic grammar for testing the grammar system
/// Supports basic expressions like "1 + 2" or "3 * 4 + 5"
pub const ArithmeticGrammar = struct {
    allocator: std.mem.Allocator,

    // Rule storage
    number_rule: rule.Rule,
    operator_rule: rule.Rule,
    expression_rule: rule.Rule,

    pub fn init(allocator: std.mem.Allocator) !ArithmeticGrammar {
        // Define digit and number patterns
        const digit = rule.choice(allocator, &.{
            rule.terminal("0"),
            rule.terminal("1"),
            rule.terminal("2"),
            rule.terminal("3"),
            rule.terminal("4"),
            rule.terminal("5"),
            rule.terminal("6"),
            rule.terminal("7"),
            rule.terminal("8"),
            rule.terminal("9"),
        }) catch unreachable;

        // Number is one or more digits
        const digit_ptr = try allocator.create(rule.Rule);
        digit_ptr.* = digit;
        const number = rule.repeat1(digit_ptr);

        // Operators
        const operator = try rule.choice(allocator, &.{
            rule.terminal("+"),
            rule.terminal("-"),
            rule.terminal("*"),
            rule.terminal("/"),
        });

        // For now, simple expression: number operator number
        // TODO: Add recursive expressions and precedence
        const expr = try rule.sequence(allocator, &.{
            number,
            rule.terminal(" "),
            operator,
            rule.terminal(" "),
            number,
        });

        return .{
            .allocator = allocator,
            .number_rule = number,
            .operator_rule = operator,
            .expression_rule = expr,
        };
    }

    pub fn deinit(self: *ArithmeticGrammar) void {
        // Clean up allocated rules
        switch (self.operator_rule) {
            .choice => |*c| c.deinit(),
            else => {},
        }
        switch (self.expression_rule) {
            .sequence => |*s| s.deinit(),
            else => {},
        }
        // Clean up the digit rule allocation
        switch (self.number_rule) {
            .repeat1 => |r| {
                // The repeat1 rule contains a pointer to a digit rule that needs cleanup
                switch (r.rule.*) {
                    .choice => |*c| @constCast(c).deinit(),
                    else => {},
                }
                self.allocator.destroy(r.rule);
            },
            else => {},
        }
    }

    pub fn parseExpression(self: ArithmeticGrammar, input: []const u8) !bool {
        var ctx = TestContext.init(self.allocator, input);
        const result = self.expression_rule.match(&ctx);
        return result.success and ctx.position == input.len;
    }

    pub fn parseNumber(self: ArithmeticGrammar, input: []const u8) !bool {
        var ctx = TestContext.init(self.allocator, input);
        const result = self.number_rule.match(&ctx);
        return result.success and ctx.position == input.len;
    }
};

// Tests
test "ArithmeticGrammar parses simple addition" {
    const allocator = testing.allocator;
    var grammar = try ArithmeticGrammar.init(allocator);
    defer grammar.deinit();

    try testing.expect(try grammar.parseExpression("1 + 2"));
    try testing.expect(try grammar.parseExpression("123 + 456"));
}

test "ArithmeticGrammar parses other operators" {
    const allocator = testing.allocator;
    var grammar = try ArithmeticGrammar.init(allocator);
    defer grammar.deinit();

    try testing.expect(try grammar.parseExpression("5 - 3"));
    try testing.expect(try grammar.parseExpression("4 * 2"));
    try testing.expect(try grammar.parseExpression("8 / 2"));
}

test "ArithmeticGrammar rejects invalid expressions" {
    const allocator = testing.allocator;
    var grammar = try ArithmeticGrammar.init(allocator);
    defer grammar.deinit();

    try testing.expect(!try grammar.parseExpression("1 +"));
    try testing.expect(!try grammar.parseExpression("+ 2"));
    try testing.expect(!try grammar.parseExpression("1+2")); // No spaces
    try testing.expect(!try grammar.parseExpression("abc + def"));
}

test "ArithmeticGrammar parses numbers" {
    const allocator = testing.allocator;
    var grammar = try ArithmeticGrammar.init(allocator);
    defer grammar.deinit();

    try testing.expect(try grammar.parseNumber("0"));
    try testing.expect(try grammar.parseNumber("42"));
    try testing.expect(try grammar.parseNumber("12345"));
    try testing.expect(!try grammar.parseNumber(""));
    try testing.expect(!try grammar.parseNumber("abc"));
}
