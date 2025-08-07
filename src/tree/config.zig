const std = @import("std");

pub const Config = struct {
    max_depth: ?u32 = null,
    show_hidden: bool = false,

    const Self = @This();

    pub fn fromArgs(allocator: std.mem.Allocator, args: [][:0]u8) !Self {
        _ = allocator;
        var config = Self{};

        // args[0] is "tree", args[1] is directory, args[2] is optional max_depth
        if (args.len >= 3) {
            config.max_depth = std.fmt.parseInt(u32, args[2], 10) catch null;
        }

        return config;
    }
};
