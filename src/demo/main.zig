const std = @import("std");
const core = @import("core.zig");
const json_demo = @import("json.zig");
const zon_demo = @import("zon.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const runner = core.DemoRunner.init(allocator);

    core.printHeader("Language Tooling Demos");

    std.debug.print("Available demos:\n", .{});
    std.debug.print("  • JSON - Formatter, Linter, Validator\n", .{});
    std.debug.print("  • ZON  - Formatter, Linter, Validator (with enum/char features)\n", .{});

    try json_demo.runDemo(runner);
    try zon_demo.runDemo(runner);

    std.debug.print("\n🎉 All demos complete!\n", .{});
    std.debug.print("\n📋 Summary:\n", .{});
    std.debug.print("   • Formatters: Transform compact → readable code\n", .{});
    std.debug.print("   • Linters: Detect style/correctness issues\n", .{});
    std.debug.print("   • Validators: Catch syntax errors\n", .{});
    std.debug.print("   • ZON extras: Enum literals + character literals\n", .{});
}
