// Test barrel for transform and serialization infrastructure
const std = @import("std");
const testing = std.testing;
const Context = @import("transform.zig").Context;
const json_transform = @import("../languages/json/transform.zig");
const zon_transform = @import("../languages/zon/transform.zig");
const TokenIterator = @import("streaming/token_iterator.zig").TokenIterator;
const pipeline_simple = @import("pipeline_simple.zig");
const transform = @import("transform.zig");

test {
    // Core transform infrastructure
    _ = @import("transform.zig");
    _ = @import("types.zig");

    // Pipeline implementations
    _ = @import("pipeline.zig");
    _ = @import("pipeline_simple.zig");

    // Specialized pipelines
    _ = @import("pipelines/lex_parse.zig");
    _ = @import("pipelines/format.zig");

    // Streaming infrastructure
    _ = @import("streaming/token_iterator.zig");
    _ = @import("streaming/stateful_lexer.zig");
    _ = @import("streaming/incremental_parser.zig");

    // Stage implementations
    _ = @import("stages/lexical.zig");
    _ = @import("stages/syntactic.zig");

    // Language-specific transform pipelines
    _ = @import("../languages/json/transform.zig");
    _ = @import("../languages/zon/transform.zig");
}

// Integration tests for transform pipeline architecture

test "transform pipeline - JSON roundtrip" {
    const allocator = testing.allocator;

    const input =
        \\{
        \\  "name": "test",
        \\  "version": 1,
        \\  "enabled": true
        \\}
    ;

    // Test roundtrip with default options
    var pipeline = try json_transform.JsonTransformPipeline.init(allocator);
    defer pipeline.deinit();

    var ctx = Context.init(allocator);
    defer ctx.deinit();

    const output = try pipeline.roundTrip(&ctx, input);
    defer allocator.free(output);

    // Should parse and regenerate valid JSON
    try testing.expect(output.len > 0);
    try testing.expect(std.mem.indexOf(u8, output, "\"name\"") != null);
}

test "transform pipeline - ZON roundtrip" {
    const allocator = testing.allocator;

    const input =
        \\.{
        \\    .name = "test",
        \\    .version = 1,
        \\    .enabled = true,
        \\}
    ;

    // Test roundtrip with default options
    var pipeline = try zon_transform.ZonTransformPipeline.init(allocator);
    defer pipeline.deinit();

    var ctx = Context.init(allocator);
    defer ctx.deinit();
    const output = try pipeline.roundTrip(&ctx, input);
    defer allocator.free(output);

    // Should parse and regenerate valid ZON
    try testing.expect(output.len > 0);
    try testing.expect(std.mem.indexOf(u8, output, ".name") != null);
}

// test "transform pipeline - format options" {
//     const json_transform = @import("../languages/json/transform.zig");
//     const FormatOptions = @import("../languages/interface.zig").FormatOptions;
//     const allocator = testing.allocator;
//     const input = "{\"a\":1,\"b\":2}";
//     // Test with custom format options
//     const options = FormatOptions{
//         .indent_size = 4,
//         .indent_style = .space,
//         .line_width = 80,
//         .trailing_comma = false,
//         .sort_keys = true,
//     };
//     var pipeline = try json_transform.JsonTransformPipeline.initWithOptions(allocator, options);
//     defer pipeline.deinit();
//     const output = try pipeline.roundTrip(allocator, input);
//     defer allocator.free(output);
//     // Should be formatted with sorting
//     try testing.expect(std.mem.indexOf(u8, output, "\"a\"") != null);
//     try testing.expect(std.mem.indexOf(u8, output, "\"b\"") != null);
//     // Keys should be sorted (a before b)
//     const a_pos = std.mem.indexOf(u8, output, "\"a\"") orelse return error.NotFound;
//     const b_pos = std.mem.indexOf(u8, output, "\"b\"") orelse return error.NotFound;
//     try testing.expect(a_pos < b_pos);
// }

test "streaming - large file handling" {
    const allocator = testing.allocator;

    // Create a moderately sized JSON string
    var json_parts = std.ArrayList(u8).init(allocator);
    defer json_parts.deinit();

    try json_parts.appendSlice("[");
    for (0..100) |i| {
        if (i > 0) try json_parts.appendSlice(",");
        try json_parts.writer().print("{}", .{i});
    }
    try json_parts.appendSlice("]");

    // Test streaming tokenization
    var ctx = Context.init(allocator);
    defer ctx.deinit();
    var iterator = TokenIterator.init(allocator, json_parts.items, &ctx, null);
    defer iterator.deinit();

    var token_count: usize = 0;
    while (try iterator.next()) |_| {
        token_count += 1;
        if (token_count > 1000) break; // Safety limit
    }

    // Should have tokenized the content
    try testing.expect(token_count > 0);
    try testing.expect(token_count < 1000);
}

test "pipeline composition" {
    const allocator = testing.allocator;

    // Create a simple uppercase transform
    const upper_transform = transform.createTransform([]const u8, []const u8, struct {
        fn forward(ctx: *transform.Context, input: []const u8) ![]const u8 {
            const result = try ctx.allocator.alloc(u8, input.len);
            for (input, 0..) |char, i| {
                result[i] = std.ascii.toUpper(char);
            }
            return result;
        }
    }.forward, null, .{
        .name = "uppercase",
        .description = "Convert to uppercase",
        .reversible = false,
        .streaming_capable = false,
        .performance_class = .fast,
    });

    // Create pipeline with single transform
    var pipeline = pipeline_simple.SimplePipeline([]const u8).init(allocator);
    defer pipeline.deinit();

    try pipeline.addTransform(upper_transform);

    // Test forward transform
    var ctx = transform.Context.init(allocator);
    defer ctx.deinit();

    const input = "hello world";
    const output = try pipeline.forward(&ctx, input);
    defer allocator.free(output);

    try testing.expectEqualStrings("HELLO WORLD", output);
}
