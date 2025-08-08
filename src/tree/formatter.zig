const std = @import("std");
const Entry = @import("entry.zig").Entry;

pub const Formatter = struct {
    const Self = @This();

    pub fn formatEntry(self: Self, entry: Entry, prefix: []const u8, is_last: bool) void {
        _ = self;
        const connector = if (is_last) "└── " else "├── ";

        if ((entry.is_ignored or entry.is_depth_limited) and entry.kind == .directory) {
            std.debug.print("{s}{s}{s} \x1b[90m[...]\x1b[0m\n", .{ prefix, connector, entry.name });
        } else {
            std.debug.print("{s}{s}{s}\n", .{ prefix, connector, entry.name });
        }
    }
};
