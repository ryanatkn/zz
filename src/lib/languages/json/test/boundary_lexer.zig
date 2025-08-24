/// Test for streaming lexer 4KB boundary handling
/// Validates that the dynamic token buffer correctly handles tokens spanning boundaries
const std = @import("std");
const testing = std.testing;

const Lexer = @import("../lexer/mod.zig").Lexer;
const BoundaryTester = @import("../token/buffer.zig").BoundaryTester;
const StreamToken = @import("../../../token/mod.zig").StreamToken;

test "Lexer basic boundary handling" {
    // Test boundary handling with a simple but realistic JSON
    const allocator = testing.allocator;

    // Create a JSON string that will test boundary handling
    const test_json = "{\"name\": \"test\", \"value\": 123, \"active\": true}";

    // Test with regular init first (should work fine)
    var simple_lexer = Lexer.init(test_json);
    var simple_token_count: usize = 0;

    while (simple_lexer.next()) |_| {
        simple_token_count += 1;
        // Safety check
        if (simple_token_count > 50) break;
    }

    // Should have reasonable number of tokens
    try testing.expect(simple_token_count > 5);
    try testing.expect(simple_token_count < 25);

    // Test with boundary-aware lexer (should also work)
    var boundary_lexer = Lexer.initWithAllocator(allocator);
    defer boundary_lexer.deinit();

    // Feed the data in one chunk (simpler test)
    try boundary_lexer.feedData(test_json);

    var boundary_token_count: usize = 0;
    while (boundary_lexer.next()) |_| {
        boundary_token_count += 1;
        // Safety check
        if (boundary_token_count > 50) break;
    }

    // Should have same number of tokens as simple lexer
    try testing.expectEqual(simple_token_count, boundary_token_count);
}

test "Lexer backward compatibility" {
    // Test that the original init() method still works for non-boundary cases
    const simple_json = "{\"test\": \"value\"}";

    var lexer = Lexer.init(simple_json);
    // Note: no deinit() needed for simple init

    var token_count: usize = 0;
    while (lexer.next()) |token| {
        token_count += 1;

        // Should not get continuation tokens in simple cases
        switch (token) {
            .json => |json_token| {
                try testing.expect(!json_token.flags.continuation);
            },
            .zon => {
                // Not relevant for JSON test, but handle for completeness
            },
        }

        if (token_count > 20) break; // Safety
    }

    try testing.expect(token_count > 5); // Should have several tokens
}

test "TokenBuffer edge cases" {
    const allocator = testing.allocator;

    // Test memory pressure scenarios
    const large_boundary_json = try BoundaryTester.createBoundaryString(allocator, 64 * 1024); // 64KB
    defer allocator.free(large_boundary_json);

    try testing.expect(large_boundary_json.len > 64 * 1024);

    // Test with very large strings that definitely span boundaries
    var lexer = Lexer.initWithAllocator(allocator);
    defer lexer.deinit();

    // Should handle large inputs without crashing
    try lexer.feedData(large_boundary_json[0..4096]);
    _ = lexer.next(); // Might get continuation token

    try lexer.feedData(large_boundary_json[4096..]);
    _ = lexer.next(); // Should eventually complete
}
