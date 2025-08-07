const std = @import("std");

pub const Entry = struct {
    name: []const u8,
    kind: std.fs.File.Kind,
    is_ignored: bool = false,
    is_depth_limited: bool = false,
};
