const std = @import("std");
const testing = std.testing;
const rule = @import("rule.zig");
const test_framework = @import("test_framework.zig");
const TestContext = test_framework.TestContext;

// Integration test showing complete grammar usage
test "Complete arithmetic grammar example" {
    const allocator = testing.allocator;
    
    // Build a simple arithmetic grammar
    // digit = "0" | "1" | ... | "9"
    const digit = try rule.choice(allocator, &.{
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
    });
    defer {
        var d = digit.choice;
        d.deinit();
    }
    
    // number = digit+
    const digit_rule = digit;
    const number = rule.repeat1(&digit_rule);
    
    // operator = "+" | "-" | "*" | "/"
    const operator = try rule.choice(allocator, &.{
        rule.terminal("+"),
        rule.terminal("-"),
        rule.terminal("*"),
        rule.terminal("/"),
    });
    defer {
        var op = operator.choice;
        op.deinit();
    }
    
    // ws = " "*
    const space = rule.terminal(" ");
    const ws = rule.repeat(&space);
    
    // expression = number ws operator ws number
    const expr = try rule.sequence(allocator, &.{
        number,
        ws,
        operator,
        ws,
        number,
    });
    defer {
        var e = expr.sequence;
        e.deinit();
    }
    
    // Test valid expressions
    {
        var ctx = TestContext.init(allocator, "123 + 456");
        const result = expr.match(&ctx);
        try testing.expect(result.success);
        try testing.expectEqual(@as(usize, 9), result.consumed);
    }
    
    {
        var ctx = TestContext.init(allocator, "5*3");
        const result = expr.match(&ctx);
        try testing.expect(result.success);
        try testing.expectEqual(@as(usize, 3), result.consumed);
    }
    
    // Test invalid expressions
    {
        var ctx = TestContext.init(allocator, "abc + 123");
        const result = expr.match(&ctx);
        try testing.expect(!result.success);
    }
}

// Test building a simple JSON-like grammar
test "JSON object grammar example" {
    const allocator = testing.allocator;
    
    // Build grammar for simple JSON objects like: {"key": "value"}
    
    // string = '"' [^"]* '"'
    // For simplicity, we'll just match specific strings for now
    const string_hello = try rule.sequence(allocator, &.{
        rule.terminal("\""),
        rule.terminal("hello"),
        rule.terminal("\""),
    });
    defer {
        var s = string_hello.sequence;
        s.deinit();
    }
    
    const string_world = try rule.sequence(allocator, &.{
        rule.terminal("\""),
        rule.terminal("world"),
        rule.terminal("\""),
    });
    defer {
        var s = string_world.sequence;
        s.deinit();
    }
    
    // key_value = string ":" string
    const key_value = try rule.sequence(allocator, &.{
        string_hello,
        rule.terminal(":"),
        rule.terminal(" "),
        string_world,
    });
    defer {
        var kv = key_value.sequence;
        kv.deinit();
    }
    
    // object = "{" key_value "}"
    const object = try rule.sequence(allocator, &.{
        rule.terminal("{"),
        key_value,
        rule.terminal("}"),
    });
    defer {
        var o = object.sequence;
        o.deinit();
    }
    
    // Test valid JSON object
    {
        var ctx = TestContext.init(allocator, "{\"hello\": \"world\"}");
        const result = object.match(&ctx);
        try testing.expect(result.success);
        try testing.expectEqual(@as(usize, 18), result.consumed);
    }
    
    // Test invalid JSON
    {
        var ctx = TestContext.init(allocator, "{hello: world}");
        const result = object.match(&ctx);
        try testing.expect(!result.success);
    }
}

// Test nested rules and complex patterns
test "Nested parentheses grammar" {
    const allocator = testing.allocator;
    
    // Grammar for balanced parentheses
    // We'll build it iteratively since we can't do true recursion yet
    
    // Level 0: empty or simple content
    const content = rule.terminal("x");
    
    // Level 1: (x)
    const level1 = try rule.sequence(allocator, &.{
        rule.terminal("("),
        content,
        rule.terminal(")"),
    });
    defer {
        var l1 = level1.sequence;
        l1.deinit();
    }
    
    // Level 2: ((x))
    const level2 = try rule.sequence(allocator, &.{
        rule.terminal("("),
        level1,
        rule.terminal(")"),
    });
    defer {
        var l2 = level2.sequence;
        l2.deinit();
    }
    
    // Test different nesting levels
    {
        var ctx = TestContext.init(allocator, "(x)");
        const result = level1.match(&ctx);
        try testing.expect(result.success);
        try testing.expectEqual(@as(usize, 3), result.consumed);
    }
    
    {
        var ctx = TestContext.init(allocator, "((x))");
        const result = level2.match(&ctx);
        try testing.expect(result.success);
        try testing.expectEqual(@as(usize, 5), result.consumed);
    }
    
    // Test unbalanced
    {
        var ctx = TestContext.init(allocator, "(x");
        const result = level1.match(&ctx);
        try testing.expect(!result.success);
    }
}