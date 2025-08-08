const std = @import("std");

pub const Command = enum {
    tree,
    hex,
    help,

    const Self = @This();

    pub fn fromString(cmd: []const u8) ?Self {
        if (std.mem.eql(u8, cmd, "tree")) return .tree;
        if (std.mem.eql(u8, cmd, "hex")) return .hex;
        if (std.mem.eql(u8, cmd, "help")) return .help;
        return null;
    }
};
