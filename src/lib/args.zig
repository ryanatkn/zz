const std = @import("std");

/// Common argument parsing utilities for CLI commands
pub const Args = struct {
    allocator: std.mem.Allocator,

    /// Initialize argument parser
    pub fn init(allocator: std.mem.Allocator) Args {
        return Args{
            .allocator = allocator,
        };
    }

    /// Parse a flag argument that starts with -- or -
    pub fn parseFlag(arg: []const u8, flag_name: []const u8, short_flag: ?[]const u8) ?[]const u8 {
        // Check long form: --flag=value
        if (std.mem.startsWith(u8, arg, "--")) {
            // Build expected prefix manually to avoid allocation
            var prefix_buf: [64]u8 = undefined;
            const expected_prefix = std.fmt.bufPrint(prefix_buf[0..], "--{s}=", .{flag_name}) catch return null;

            if (std.mem.startsWith(u8, arg, expected_prefix)) {
                return arg[expected_prefix.len..];
            }
        }

        // Check short form: -f=value
        if (short_flag) |short| {
            if (std.mem.startsWith(u8, arg, "-")) {
                var prefix_buf: [16]u8 = undefined;
                const expected_prefix = std.fmt.bufPrint(prefix_buf[0..], "-{s}=", .{short}) catch return null;

                if (std.mem.startsWith(u8, arg, expected_prefix)) {
                    return arg[expected_prefix.len..];
                }
            }
        }

        return null;
    }

    /// Check if argument is a boolean flag
    pub fn isBoolFlag(arg: []const u8, flag_name: []const u8, short_flag: ?[]const u8) bool {
        // Check long form: --flag
        var long_buf: [64]u8 = undefined;
        const expected_long = std.fmt.bufPrint(long_buf[0..], "--{s}", .{flag_name}) catch return false;

        if (std.mem.eql(u8, arg, expected_long)) {
            return true;
        }

        // Check short form: -f
        if (short_flag) |short| {
            var short_buf: [16]u8 = undefined;
            const expected_short = std.fmt.bufPrint(short_buf[0..], "-{s}", .{short}) catch return false;

            if (std.mem.eql(u8, arg, expected_short)) {
                return true;
            }
        }

        return false;
    }

    /// Parse integer value from flag
    pub fn parseIntFlag(arg: []const u8, flag_name: []const u8, short_flag: ?[]const u8, comptime T: type) ?T {
        if (parseFlag(arg, flag_name, short_flag)) |value| {
            return std.fmt.parseInt(T, value, 10) catch null;
        }
        return null;
    }

    /// Skip to a specific command in args array
    pub fn skipToCommand(args: [][:0]const u8, command: []const u8) usize {
        for (args, 0..) |arg, i| {
            if (std.mem.eql(u8, arg, command)) {
                return i + 1; // Return index after the command
            }
        }
        return args.len; // Command not found, return end
    }

    /// Collect remaining positional arguments starting from index
    pub fn collectPositionalArgs(self: Args, args: [][:0]const u8, start_index: usize) !std.ArrayList([]const u8) {
        var result = std.ArrayList([]const u8).init(self.allocator);

        var i = start_index;
        while (i < args.len) {
            const arg = args[i];

            // Skip flags (arguments starting with -)
            if (std.mem.startsWith(u8, arg, "-")) {
                i += 1;
                continue;
            }

            try result.append(arg);
            i += 1;
        }

        return result;
    }

    /// Parse common help flags
    pub fn isHelpFlag(arg: []const u8) bool {
        return std.mem.eql(u8, arg, "--help") or
            std.mem.eql(u8, arg, "-h") or
            std.mem.eql(u8, arg, "help");
    }

    /// Common error for argument parsing
    pub const ArgError = error{
        InvalidFlag,
        MissingValue,
        InvalidFormat,
        OutOfMemory,
        ParseError,
    };

    /// Standard usage message formatter
    pub fn printUsage(writer: anytype, command: []const u8, description: []const u8, options: []const []const u8) !void {
        try writer.print("Usage: zz {s} [files...] [options]\n", .{command});
        try writer.print("{s}\n\n", .{description});
        try writer.print("Options:\n", .{});
        for (options) |option| {
            try writer.print("  {s}\n", .{option});
        }
    }
};

/// Common flag parsing patterns
pub const CommonFlags = struct {
    /// Parse format flag (for tree command)
    pub fn parseFormatFlag(arg: []const u8) ?[]const u8 {
        return Args.parseFlag(arg, "format", "f");
    }

    /// Parse write flag (for format command)
    pub fn isWriteFlag(arg: []const u8) bool {
        return Args.isBoolFlag(arg, "write", "w");
    }

    /// Parse check flag (for format command)
    pub fn isCheckFlag(arg: []const u8) bool {
        return Args.isBoolFlag(arg, "check", null);
    }

    /// Parse stdin flag (for format command)
    pub fn isStdinFlag(arg: []const u8) bool {
        return Args.isBoolFlag(arg, "stdin", null);
    }

    /// Parse show-hidden flag (for tree command)
    pub fn isShowHiddenFlag(arg: []const u8) bool {
        return Args.isBoolFlag(arg, "show-hidden", null);
    }

    /// Parse no-gitignore flag
    pub fn isNoGitignoreFlag(arg: []const u8) bool {
        return Args.isBoolFlag(arg, "no-gitignore", null);
    }

    /// Parse indent-size flag (for format command)
    pub fn parseIndentSizeFlag(arg: []const u8) ?u8 {
        return Args.parseIntFlag(arg, "indent-size", null, u8);
    }

    /// Parse line-width flag (for format command)
    pub fn parseLineWidthFlag(arg: []const u8) ?u32 {
        return Args.parseIntFlag(arg, "line-width", null, u32);
    }

    /// Parse indent-style flag (for format command)
    pub fn parseIndentStyleFlag(arg: []const u8) ?[]const u8 {
        return Args.parseFlag(arg, "indent-style", null);
    }
};

// Tests
test "parseFlag with long form" {
    const result = Args.parseFlag("--format=tree", "format", "f");
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("tree", result.?);
}

test "parseFlag with short form" {
    const result = Args.parseFlag("-f=list", "format", "f");
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("list", result.?);
}

test "isBoolFlag with long form" {
    try std.testing.expect(Args.isBoolFlag("--write", "write", "w"));
}

test "isBoolFlag with short form" {
    try std.testing.expect(Args.isBoolFlag("-w", "write", "w"));
}

test "parseIntFlag" {
    const result = Args.parseIntFlag("--indent-size=4", "indent-size", null, u8);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(u8, 4), result.?);
}

test "skipToCommand" {
    var args = [_][:0]const u8{ "zz", "format", "file.txt" };
    const index = Args.skipToCommand(args[0..], "format");
    try std.testing.expectEqual(@as(usize, 2), index);
}

test "isHelpFlag" {
    try std.testing.expect(Args.isHelpFlag("--help"));
    try std.testing.expect(Args.isHelpFlag("-h"));
    try std.testing.expect(Args.isHelpFlag("help"));
    try std.testing.expect(!Args.isHelpFlag("--version"));
}
