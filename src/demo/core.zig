const std = @import("std");

pub fn printHeader(title: []const u8) void {
    std.debug.print("\n┌", .{});
    for (0..title.len + 4) |_| std.debug.print("═", .{});
    std.debug.print("┐\n", .{});
    std.debug.print("│  {s}  │\n", .{title});
    std.debug.print("└", .{});
    for (0..title.len + 4) |_| std.debug.print("═", .{});
    std.debug.print("┘\n\n", .{});
}

pub fn printSection(title: []const u8) void {
    std.debug.print("🔸 {s}\n", .{title});
    for (0..title.len) |_| std.debug.print("─", .{});
    std.debug.print("\n", .{});
}

pub fn printExample(label: []const u8, code: []const u8, description: ?[]const u8) void {
    std.debug.print("\n{s}:\n", .{label});
    std.debug.print("{s}\n", .{code});
    if (description) |desc| {
        std.debug.print("→ {s}\n", .{desc});
    }
}

pub const DemoRunner = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) DemoRunner {
        return .{ .allocator = allocator };
    }

    pub fn printResult(self: DemoRunner, success: bool, message: []const u8) void {
        _ = self;
        const icon = if (success) "✅" else "❌";
        std.debug.print("{s} {s}\n", .{ icon, message });
    }

    pub fn printSeparator(self: DemoRunner) void {
        _ = self;
        std.debug.print("\n", .{});
        for (0..50) |_| std.debug.print("─", .{});
        std.debug.print("\n\n", .{});
    }
};
