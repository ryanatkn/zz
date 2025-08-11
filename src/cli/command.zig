const std = @import("std");

pub const Command = enum {
    tree,
    prompt,
    help,

    const Self = @This();

    pub fn fromString(cmd: []const u8) ?Self {
        if (std.mem.eql(u8, cmd, "tree")) return .tree;
        if (std.mem.eql(u8, cmd, "prompt")) return .prompt;
        if (std.mem.eql(u8, cmd, "help")) return .help;
        return null;
    }
};
