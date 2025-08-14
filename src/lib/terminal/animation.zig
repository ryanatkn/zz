const std = @import("std");
const colors = @import("colors.zig");
const control = @import("control.zig");

/// Animation utilities for terminal output
pub const Animation = struct {
    /// Braille spinner frames
    pub const spinners = [_][]const u8{ "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" };

    /// Dot animation frames
    pub const dots = [_][]const u8{ "   ", ".  ", ".. ", "..." };

    /// Intensity levels for pulse animation
    pub const pulse_intensity = [_][]const u8{
        colors.Color.dim,
        colors.Color.reset,
        colors.Color.bold,
        colors.Color.reset,
    };

    /// Show animated spinner
    pub fn showSpinner(
        writer: std.fs.File.Writer,
        frame: usize,
        message: []const u8,
        use_color: bool,
    ) !void {
        const spinner = spinners[frame % spinners.len];

        try writer.writeAll("\r");
        if (use_color) {
            try writer.print("{s}{s} {s}{s}", .{ colors.Color.cyan, spinner, message, colors.Color.reset });
        } else {
            try writer.print("{s} {s}", .{ spinner, message });
        }
    }

    /// Show animated dots
    pub fn showDots(
        writer: std.fs.File.Writer,
        frame: usize,
        message: []const u8,
        use_color: bool,
    ) !void {
        const dot_pattern = dots[frame % dots.len];

        try writer.writeAll("\r");
        if (use_color) {
            try writer.print("{s}{s}{s}{s}", .{ colors.Color.bright_blue, message, dot_pattern, colors.Color.reset });
        } else {
            try writer.print("{s}{s}", .{ message, dot_pattern });
        }
    }

    /// Show animated pulse effect
    pub fn showPulse(
        writer: std.fs.File.Writer,
        frame: usize,
        symbol: []const u8,
        message: []const u8,
        use_color: bool,
    ) !void {
        const color = pulse_intensity[frame % pulse_intensity.len];

        try writer.writeAll("\r");
        if (use_color) {
            try writer.print("{s}{s} {s}{s}", .{ color, symbol, message, colors.Color.reset });
        } else {
            try writer.print("{s} {s}", .{ symbol, message });
        }
    }

    /// Clear current line
    pub fn clearLine(writer: std.fs.File.Writer) !void {
        try writer.writeAll("\r");
        try writer.writeAll(control.Control.clear_line);
    }
};
