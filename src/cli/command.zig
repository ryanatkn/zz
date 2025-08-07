const std = @import("std");

pub const Command = enum {
    tree,
    yar,
    help,

    const Self = @This();

    pub fn fromString(cmd: []const u8) ?Self {
        if (std.mem.eql(u8, cmd, "tree")) return .tree;
        if (std.mem.eql(u8, cmd, "yar")) return .yar;
        if (std.mem.eql(u8, cmd, "help")) return .help;
        return null;
    }
};
