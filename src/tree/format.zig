const std = @import("std");

pub const Format = enum {
    tree,
    list,

    pub fn fromString(s: []const u8) ?Format {
        if (std.mem.eql(u8, s, "tree")) return .tree;
        if (std.mem.eql(u8, s, "list")) return .list;
        return null;
    }
};