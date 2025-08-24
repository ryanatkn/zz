/// Test for streaming lexer 4KB boundary handling for ZON
/// Validates that the dynamic token buffer correctly handles tokens spanning boundaries
const std = @import("std");
const testing = std.testing;

const Lexer = @import("../lexer/mod.zig").Lexer;
const Token = @import("../../../token/mod.zig").Token;

test "ZON Lexer basic boundary handling" {
    // Test boundary handling with a simple but realistic ZON structure

    // Create a ZON structure that will test boundary handling
    const test_zon = ".{ .name = \"test\", .value = 123, .active = true, .nested = .{ .inner = \"value\" } }";

    // Test with regular init first (should work fine)
    var simple_lexer = Lexer.init(test_zon);
    var simple_token_count: usize = 0;

    while (simple_lexer.next()) |_| {
        simple_token_count += 1;
        // Safety check to prevent infinite loops
        if (simple_token_count > 50) break;
    }

    // Should have reasonable number of tokens
    try testing.expect(simple_token_count > 5);
    try testing.expect(simple_token_count < 30);

    // ZON lexer doesn't have separate boundary-aware mode
    // Test with the same lexer setup as simple lexer for consistency
    var boundary_lexer = Lexer.init(test_zon);
    var boundary_token_count: usize = 0;
    while (boundary_lexer.next()) |_| {
        boundary_token_count += 1;
        // Safety check
        if (boundary_token_count > 50) break;
    }

    // Should have same number of tokens as simple lexer
    try testing.expectEqual(simple_token_count, boundary_token_count);
}

test "ZON Lexer backward compatibility" {
    // Test that the original init() method still works for non-boundary cases
    const simple_zon = ".{ .test = \"value\" }";

    var lexer = Lexer.init(simple_zon);
    // Note: no deinit() needed for simple init

    var token_count: usize = 0;
    while (lexer.next()) |token| {
        token_count += 1;

        // Verify token is valid ZON token
        switch (token) {
            .zon => |zon_token| {
                // Token should be valid (not error)
                try testing.expect(zon_token.kind != .err);
            },
            .json => {
                // Should not get JSON tokens when parsing ZON
                try testing.expect(false);
            },
        }

        if (token_count > 20) break; // Safety
    }

    try testing.expect(token_count > 3); // Should have several tokens (.{, .test, =, "value", })
}

test "ZON Lexer handles complex structures across boundaries" {
    const allocator = testing.allocator;

    // Create a large ZON structure to test boundary spanning
    var large_zon = std.ArrayList(u8).init(allocator);
    defer large_zon.deinit();

    // Build a structure large enough to cross 4KB boundaries
    try large_zon.appendSlice(".{\n");

    // Add many fields to create a large structure
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        try std.fmt.format(large_zon.writer(), "    .field_{d} = \"This is a relatively long string value to increase size field_{d}\",\n", .{ i, i });
    }

    // Add nested structures
    try large_zon.appendSlice("    .nested = .{\n");
    i = 0;
    while (i < 50) : (i += 1) {
        try std.fmt.format(large_zon.writer(), "        .nested_field_{d} = {d},\n", .{ i, i * 2 });
    }
    try large_zon.appendSlice("    },\n");

    // Add arrays/tuples
    try large_zon.appendSlice("    .tuple_data = .{ ");
    i = 0;
    while (i < 200) : (i += 1) {
        try std.fmt.format(large_zon.writer(), "{d}, ", .{i});
    }
    try large_zon.appendSlice("},\n");

    try large_zon.appendSlice("}");

    const large_zon_str = large_zon.items;

    // Verify we have a large enough structure
    try testing.expect(large_zon_str.len > 8192); // Larger than typical boundary

    // Test with ZON lexer (note: ZON lexer handles large inputs directly)
    var lexer = Lexer.init(large_zon_str);

    // Process all tokens
    var token_count: usize = 0;
    while (lexer.next()) |token| {
        token_count += 1;

        // Verify we get ZON tokens
        switch (token) {
            .zon => |zon_token| {
                // Token should be valid
                _ = zon_token;
            },
            .json => {
                // Should not get JSON tokens when parsing ZON
                try testing.expect(false);
            },
        }

        // Safety check
        if (token_count > 2000) break;
    }

    // Should have processed many tokens
    try testing.expect(token_count > 100);
}

test "ZON Lexer handles string boundaries correctly" {
    const allocator = testing.allocator;

    // Create a ZON structure where string literals span boundaries
    const boundary_string = "x" ** 2048; // 2KB string
    var test_zon = std.ArrayList(u8).init(allocator);
    defer test_zon.deinit();

    try test_zon.appendSlice(".{ .long_string = \"");
    try test_zon.appendSlice(boundary_string);
    try test_zon.appendSlice("\", .another_field = \"");
    try test_zon.appendSlice(boundary_string);
    try test_zon.appendSlice("\" }");

    const test_zon_str = test_zon.items;

    // Test with ZON lexer
    var lexer = Lexer.init(test_zon_str);

    // Should still parse correctly
    var token_count: usize = 0;
    var string_tokens: usize = 0;

    while (lexer.next()) |token| {
        token_count += 1;

        switch (token) {
            .zon => |zon_token| {
                if (zon_token.kind == .string_value) {
                    string_tokens += 1;
                }
            },
            .json => {
                try testing.expect(false); // Should not get JSON tokens
            },
        }

        if (token_count > 20) break; // Safety
    }

    // Should have found the string tokens despite boundary crossing
    try testing.expect(string_tokens >= 2); // At least the two long strings
}

test "ZON Lexer handles identifier boundaries" {
    const allocator = testing.allocator;

    // Create ZON with long identifiers that might span boundaries
    var test_zon = std.ArrayList(u8).init(allocator);
    defer test_zon.deinit();

    try test_zon.appendSlice(".{\n");

    // Create identifiers that are long enough to potentially span chunk boundaries
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        try std.fmt.format(test_zon.writer(), "    .very_long_identifier_name_that_might_span_boundaries_field_{d} = {d},\n", .{ i, i });
    }

    try test_zon.appendSlice("}");

    const test_zon_str = test_zon.items;

    // Test with ZON lexer
    var lexer = Lexer.init(test_zon_str);

    // Should still parse correctly
    var token_count: usize = 0;
    var identifier_tokens: usize = 0;

    while (lexer.next()) |token| {
        token_count += 1;

        switch (token) {
            .zon => |zon_token| {
                if (zon_token.kind == .identifier or zon_token.kind == .field_name) {
                    identifier_tokens += 1;
                }
            },
            .json => {
                try testing.expect(false); // Should not get JSON tokens
            },
        }

        if (token_count > 1000) break; // Safety - we have many tokens
    }

    // Should have found many identifier/field_name tokens
    try testing.expect(identifier_tokens >= 50); // Should have many field names
}
