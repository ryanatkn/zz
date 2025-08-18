const std = @import("std");
const char = @import("../char/mod.zig");
const colors = @import("colors.zig");
const control = @import("control.zig");
const animation = @import("animation.zig");

// Re-export for convenience
pub const Color = colors.Color;
pub const Control = control.Control;
pub const Animation = animation.Animation;

/// High-level terminal interface for interactive operations
/// Consolidates terminal functionality from across the project
pub const Terminal = struct {
    writer: std.fs.File.Writer,
    reader: std.fs.File.Reader,
    is_interactive: bool,
    use_color: bool,

    pub fn init(interactive: bool) Terminal {
        return .{
            .writer = std.io.getStdOut().writer(),
            .reader = std.io.getStdIn().reader(),
            .is_interactive = interactive,
            .use_color = interactive and isTerminal(),
        };
    }

    fn isTerminal() bool {
        return std.io.getStdOut().isTty();
    }

    pub fn clearScreen(self: *Terminal) !void {
        if (self.is_interactive) {
            try self.writer.writeAll(Control.clear_screen);
        }
    }

    pub fn print(self: *Terminal, comptime fmt: []const u8, args: anytype) !void {
        try self.writer.print(fmt, args);
    }

    pub fn printColored(self: *Terminal, color: []const u8, text: []const u8) !void {
        if (self.use_color) {
            try self.writer.print("{s}{s}{s}", .{ color, text, Color.reset });
        } else {
            try self.writer.writeAll(text);
        }
    }

    pub fn printBold(self: *Terminal, text: []const u8) !void {
        try self.printColored(Color.bold, text);
    }

    pub fn printSuccess(self: *Terminal, text: []const u8) !void {
        try self.printColored(Color.bright_green, text);
    }

    pub fn printError(self: *Terminal, text: []const u8) !void {
        try self.printColored(Color.bright_red, text);
    }

    pub fn printWarning(self: *Terminal, text: []const u8) !void {
        try self.printColored(Color.bright_yellow, text);
    }

    pub fn printInfo(self: *Terminal, text: []const u8) !void {
        try self.printColored(Color.bright_cyan, text);
    }

    pub fn printDim(self: *Terminal, text: []const u8) !void {
        try self.printColored(Color.dim, text);
    }

    pub fn newline(self: *Terminal) !void {
        try self.writer.writeAll("\n");
    }

    pub fn waitForEnter(self: *Terminal) !void {
        if (!self.is_interactive) return;

        try self.printDim("\nPress Enter to continue...");

        var buf: [256]u8 = undefined;
        _ = try self.reader.readUntilDelimiterOrEof(&buf, '\n');
        try self.newline();
    }

    pub fn waitForKey(self: *Terminal, prompt: []const u8) !void {
        if (!self.is_interactive) return;

        try self.printDim(prompt);

        var buf: [256]u8 = undefined;
        _ = try self.reader.readUntilDelimiterOrEof(&buf, '\n');
    }

    pub fn drawBox(self: *Terminal, title: []const u8, width: usize) !void {
        const box_width = @max(width, title.len + 4);
        const padding = (box_width -| title.len -| 2) / 2;

        // Top border
        if (self.use_color) {
            try self.writer.print("{s}{s}", .{ Color.bold, Color.cyan });
        }
        try self.writer.writeAll("╔");
        for (0..box_width) |_| {
            try self.writer.writeAll("═");
        }
        try self.writer.writeAll("╗");
        if (self.use_color) {
            try self.writer.writeAll(Color.reset);
        }
        try self.newline();

        // Title line
        if (self.use_color) {
            try self.writer.print("{s}{s}", .{ Color.bold, Color.cyan });
        }
        try self.writer.writeAll("║");
        for (0..padding) |_| {
            try self.writer.writeAll(" ");
        }
        try self.writer.writeAll(title);
        for (0..(box_width -| title.len -| padding)) |_| {
            try self.writer.writeAll(" ");
        }
        try self.writer.writeAll("║");
        if (self.use_color) {
            try self.writer.writeAll(Color.reset);
        }
        try self.newline();

        // Bottom border
        if (self.use_color) {
            try self.writer.print("{s}{s}", .{ Color.bold, Color.cyan });
        }
        try self.writer.writeAll("╚");
        for (0..box_width) |_| {
            try self.writer.writeAll("═");
        }
        try self.writer.writeAll("╝");
        if (self.use_color) {
            try self.writer.writeAll(Color.reset);
        }
        try self.newline();
    }

    pub fn showProgress(self: *Terminal, current: usize, total: usize, label: []const u8) !void {
        if (!self.is_interactive) return;

        const percentage = if (total > 0) (current * 100) / total else 0;
        const bar_width = 40;
        const filled = (percentage * bar_width) / 100;

        try self.writer.writeAll("\r");
        try self.writer.print("{s}: [", .{label});

        if (self.use_color) {
            try self.writer.writeAll(Color.bright_green);
        }
        for (0..filled) |_| {
            try self.writer.writeAll("█");
        }
        if (self.use_color) {
            try self.writer.writeAll(Color.dim);
        }
        for (filled..bar_width) |_| {
            try self.writer.writeAll("░");
        }
        if (self.use_color) {
            try self.writer.writeAll(Color.reset);
        }

        try self.writer.print("] {}%", .{percentage});

        if (current >= total) {
            try self.newline();
        }
    }

    /// Show animated spinner during long operations
    pub fn showSpinner(self: *Terminal, frame: usize, message: []const u8) !void {
        if (!self.is_interactive) return;
        try Animation.showSpinner(self.writer, frame, message, self.use_color);
    }

    /// Show animated dots during operations
    pub fn showDots(self: *Terminal, frame: usize, message: []const u8) !void {
        if (!self.is_interactive) return;
        try Animation.showDots(self.writer, frame, message, self.use_color);
    }

    /// Show animated pulse effect
    pub fn showPulse(self: *Terminal, frame: usize, symbol: []const u8, message: []const u8) !void {
        if (!self.is_interactive) return;
        try Animation.showPulse(self.writer, frame, symbol, message, self.use_color);
    }

    /// Clear current line (for cleaning up animations)
    pub fn clearLine(self: *Terminal) !void {
        if (!self.is_interactive) return;
        try Animation.clearLine(self.writer);
    }

    pub fn printStep(self: *Terminal, step_num: usize, title: []const u8) !void {
        if (self.use_color) {
            try self.writer.print("{s}{s}═══ {}. {s} ═══{s}\n", .{
                Color.bold,
                Color.blue,
                step_num,
                title,
                Color.reset,
            });
        } else {
            try self.writer.print("=== {}. {s} ===\n", .{ step_num, title });
        }
    }

    pub fn printCommand(self: *Terminal, command: []const u8) !void {
        if (self.use_color) {
            try self.writer.print("{s}$ {s}{s}\n", .{
                Color.magenta,
                command,
                Color.reset,
            });
        } else {
            try self.writer.print("$ {s}\n", .{command});
        }
    }

    pub fn printOutput(self: *Terminal, output: []const u8) !void {
        try self.writer.writeAll(output);
        if (!std.mem.endsWith(u8, output, "\n")) {
            try self.newline();
        }
    }
};

/// Create a formatted header for demo sections
pub fn formatHeader(allocator: std.mem.Allocator, title: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator,
        \\╔══════════════════════════════════════════════════════════════╗
        \\║{s: ^62}║
        \\╚══════════════════════════════════════════════════════════════╝
    , .{title});
}

/// Strip ANSI color codes from text (for non-interactive output)
pub fn stripColors(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    var i: usize = 0;
    while (i < text.len) {
        if (i + 1 < text.len and text[i] == '\x1b' and text[i + 1] == '[') {
            // Skip ANSI escape sequence
            i += 2;
            while (i < text.len and !char.isAlpha(text[i])) {
                i += 1;
            }
            if (i < text.len) i += 1; // Skip the letter
        } else {
            try result.append(text[i]);
            i += 1;
        }
    }

    return result.toOwnedSlice();
}
