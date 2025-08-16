const std = @import("std");

pub const Command = enum {
    tree,
    prompt,
    benchmark,
    format,
    demo,
    deps,
    help,

    const Self = @This();

    pub fn fromString(cmd: []const u8) ?Self {
        if (std.mem.eql(u8, cmd, "tree")) return .tree;
        if (std.mem.eql(u8, cmd, "prompt")) return .prompt;
        if (std.mem.eql(u8, cmd, "benchmark")) return .benchmark;
        if (std.mem.eql(u8, cmd, "format")) return .format;
        if (std.mem.eql(u8, cmd, "demo")) return .demo;
        if (std.mem.eql(u8, cmd, "deps")) return .deps;
        if (std.mem.eql(u8, cmd, "help")) return .help;
        return null;
    }
};
