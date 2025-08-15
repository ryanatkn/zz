const std = @import("std");
const Entry = @import("entry.zig").Entry;
const Format = @import("format.zig").Format;

pub const Formatter = struct {
    quiet: bool = false,
    format: Format = .tree,

    const Self = @This();

    pub fn formatEntry(self: Self, entry: Entry, context: []const u8, is_last: bool) void {
        if (self.quiet) return; // Skip output when in quiet mode

        switch (self.format) {
            .tree => self.formatTree(entry, context, is_last),
            .list => self.formatList(entry, context),
        }
    }

    fn formatTree(self: Self, entry: Entry, prefix: []const u8, is_last: bool) void {
        _ = self; // Suppress unused parameter warning
        const connector = if (is_last) "└── " else "├── ";

        if ((entry.is_ignored or entry.is_depth_limited) and entry.kind == .directory) {
            std.debug.print("{s}{s}{s} \x1b[90m[...]\x1b[0m\n", .{ prefix, connector, entry.name });
        } else {
            std.debug.print("{s}{s}{s}\n", .{ prefix, connector, entry.name });
        }
    }

    fn formatList(self: Self, entry: Entry, path_from_root: []const u8) void {
        _ = self; // Suppress unused parameter warning
        _ = entry; // Entry details not needed for list format

        // For list format, context contains the full relative path
        std.debug.print("./{s}\n", .{path_from_root});
    }
};
