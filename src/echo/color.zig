const std = @import("std");

const ColorCode = struct {
    foreground: u8,
};

const COLORS = std.StaticStringMap(ColorCode).initComptime(.{
    .{ "black", ColorCode{ .foreground = 30 } },
    .{ "red", ColorCode{ .foreground = 31 } },
    .{ "green", ColorCode{ .foreground = 32 } },
    .{ "yellow", ColorCode{ .foreground = 33 } },
    .{ "blue", ColorCode{ .foreground = 34 } },
    .{ "magenta", ColorCode{ .foreground = 35 } },
    .{ "cyan", ColorCode{ .foreground = 36 } },
    .{ "white", ColorCode{ .foreground = 37 } },
});

/// Check if a color name is valid
pub fn isValidColor(name: []const u8) bool {
    return COLORS.has(name);
}

/// Determine if color output should be used
/// Checks for TTY and NO_COLOR environment variable
pub fn shouldUseColor() bool {
    // Check NO_COLOR environment variable
    if (std.posix.getenv("NO_COLOR")) |_| {
        return false;
    }

    // Check if stdout is a TTY
    const stdout_file = std.io.getStdOut();
    return std.posix.isatty(stdout_file.handle);
}

/// Write ANSI color code to writer
pub fn writeColor(writer: anytype, color_name: []const u8, bold: bool) !void {
    if (COLORS.get(color_name)) |color_code| {
        if (bold) {
            try writer.print("\x1b[1;{}m", .{color_code.foreground});
        } else {
            try writer.print("\x1b[{}m", .{color_code.foreground});
        }
    }
}

/// Write bold formatting code
pub fn writeBold(writer: anytype) !void {
    try writer.writeAll("\x1b[1m");
}

/// Write reset code to clear all formatting
pub fn writeReset(writer: anytype) !void {
    try writer.writeAll("\x1b[0m");
}
