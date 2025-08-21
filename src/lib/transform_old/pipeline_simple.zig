const std = @import("std");
const types = @import("types.zig");
const transform_mod = @import("transform.zig");
const Transform = transform_mod.Transform;
const Context = transform_mod.Context;

/// Simple pipeline implementation without complex type erasure
/// Works only for specific type combinations but is much simpler
pub fn SimplePipeline(comptime T: type) type {
    return struct {
        const Self = @This();

        transforms: std.ArrayList(Transform(T, T)),
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .transforms = std.ArrayList(Transform(T, T)).init(allocator),
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.transforms.deinit();
        }

        pub fn addTransform(self: *Self, t: Transform(T, T)) !void {
            try self.transforms.append(t);
        }

        pub fn forward(self: Self, ctx: *Context, input: T) !T {
            var result = input;
            for (self.transforms.items) |t| {
                result = try t.runForward(ctx, result);
            }
            return result;
        }

        pub fn reverse(self: Self, ctx: *Context, output: T) !T {
            var result = output;
            var i = self.transforms.items.len;
            while (i > 0) : (i -= 1) {
                const t = self.transforms.items[i - 1];
                if (!t.isReversible()) {
                    return error.NotReversible;
                }
                result = try t.runReverse(ctx, result);
            }
            return result;
        }
    };
}

// Tests
const testing = std.testing;

test "Simple pipeline" {
    const allocator = testing.allocator;

    const add_one = transform_mod.createTransform(
        i32,
        i32,
        struct {
            fn forward(ctx: *Context, input: i32) !i32 {
                _ = ctx;
                return input + 1;
            }
        }.forward,
        struct {
            fn reverse(ctx: *Context, output: i32) !i32 {
                _ = ctx;
                return output - 1;
            }
        }.reverse,
        .{
            .name = "add_one",
            .description = "Add 1",
            .reversible = true,
        },
    );

    const multiply_two = transform_mod.createTransform(
        i32,
        i32,
        struct {
            fn forward(ctx: *Context, input: i32) !i32 {
                _ = ctx;
                return input * 2;
            }
        }.forward,
        struct {
            fn reverse(ctx: *Context, output: i32) !i32 {
                _ = ctx;
                return @divExact(output, 2);
            }
        }.reverse,
        .{
            .name = "multiply_two",
            .description = "Multiply by 2",
            .reversible = true,
        },
    );

    var pipeline = SimplePipeline(i32).init(allocator);
    defer pipeline.deinit();

    try pipeline.addTransform(add_one);
    try pipeline.addTransform(multiply_two);

    var ctx = Context.init(allocator);
    defer ctx.deinit();

    // Test forward: (5 + 1) * 2 = 12
    const result = try pipeline.forward(&ctx, 5);
    try testing.expectEqual(@as(i32, 12), result);

    // Test reverse: 12 / 2 - 1 = 5
    const original = try pipeline.reverse(&ctx, 12);
    try testing.expectEqual(@as(i32, 5), original);
}
