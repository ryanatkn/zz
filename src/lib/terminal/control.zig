const std = @import("std");

/// Terminal control sequences
pub const Control = struct {
    pub const clear_screen = "\x1b[2J\x1b[H";
    pub const clear_line = "\x1b[2K";
    pub const save_cursor = "\x1b[s";
    pub const restore_cursor = "\x1b[u";
    pub const hide_cursor = "\x1b[?25l";
    pub const show_cursor = "\x1b[?25h";
    pub const home = "\x1b[H";

    pub fn move_cursor(row: u32, col: u32) [32]u8 {
        var buf: [32]u8 = undefined;
        const slice = std.fmt.bufPrint(&buf, "\x1b[{};{}H", .{ row, col }) catch "";
        var result: [32]u8 = undefined;
        @memcpy(result[0..slice.len], slice);
        return result;
    }

    pub fn move_up(n: u32) [16]u8 {
        var buf: [16]u8 = undefined;
        const slice = std.fmt.bufPrint(&buf, "\x1b[{}A", .{n}) catch "";
        var result: [16]u8 = undefined;
        @memcpy(result[0..slice.len], slice);
        return result;
    }

    pub fn move_down(n: u32) [16]u8 {
        var buf: [16]u8 = undefined;
        const slice = std.fmt.bufPrint(&buf, "\x1b[{}B", .{n}) catch "";
        var result: [16]u8 = undefined;
        @memcpy(result[0..slice.len], slice);
        return result;
    }
};
