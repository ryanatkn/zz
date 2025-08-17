const std = @import("std");
const testing = std.testing;
const grammar = @import("mod.zig");

// Example demonstrating the clean Grammar API
test "Grammar API demonstration" {
    const allocator = testing.allocator;
    
    // Step 1: Build a grammar using the fluent Builder API
    var builder = grammar.Grammar.builder(allocator);
    defer builder.deinit();
    
    // Define rules with references
    _ = try builder.define("digit", try grammar.extended.choice(allocator, &.{
        grammar.extended.terminal("0"),
        grammar.extended.terminal("1"),
        grammar.extended.terminal("2"),
        grammar.extended.terminal("3"),
    }));
    
    _ = try builder.define("number", grammar.extended.repeat1(&grammar.ref("digit")));
    
    _ = try builder.define("operator", try grammar.extended.choice(allocator, &.{
        grammar.extended.terminal("+"),
        grammar.extended.terminal("-"),
    }));
    
    _ = try builder.define("expression", try grammar.extended.sequence(allocator, &.{
        grammar.ref("number"),
        grammar.extended.terminal(" "),
        grammar.ref("operator"),
        grammar.extended.terminal(" "),
        grammar.ref("number"),
    }));
    
    _ = builder.start("expression");
    
    // Step 2: Build the final grammar
    var my_grammar = try builder.build();
    defer my_grammar.deinit();
    
    // Step 3: Use the grammar to parse input
    try testing.expect(try my_grammar.parse("1 + 2"));
    try testing.expect(try my_grammar.parse("321 - 123"));
    try testing.expect(!try my_grammar.parse("1 * 2")); // * not defined
    try testing.expect(!try my_grammar.parse("4 + 5")); // 4,5 not defined as digits
}

// Example showing simpler syntax for basic grammars
test "Simple grammar without references" {
    const allocator = testing.allocator;
    
    // For simple grammars, you can use basic rules directly
    var builder = grammar.Grammar.builder(allocator);
    defer builder.deinit();
    
    _ = try builder.define("hello", grammar.extended.terminal("hello"));
    _ = try builder.define("greeting", try grammar.extended.sequence(allocator, &.{
        grammar.extended.terminal("Hello, "),
        grammar.extended.terminal("World!"),
    }));
    
    _ = builder.start("greeting");
    
    var simple_grammar = try builder.build();
    defer simple_grammar.deinit();
    
    try testing.expect(try simple_grammar.parse("Hello, World!"));
    try testing.expect(!try simple_grammar.parse("Hello, Universe!"));
}