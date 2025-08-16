const std = @import("std");
const Color = @import("colors.zig").Color;

/// Progress indicator for long-running operations
pub const ProgressIndicator = struct {
    allocator: std.mem.Allocator,
    writer: std.fs.File.Writer,
    message: []const u8,
    spinner_chars: []const []const u8,
    current_frame: usize,
    show_elapsed: bool,
    start_time: i64,

    const Self = @This();

    /// Spinner animations
    pub const DOTS = [_][]const u8{ "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" };
    pub const ARROW = [_][]const u8{ "←", "↖", "↑", "↗", "→", "↘", "↓", "↙" };
    pub const SIMPLE = [_][]const u8{ "|", "/", "-", "\\" };

    pub fn init(allocator: std.mem.Allocator, message: []const u8) Self {
        return Self{
            .allocator = allocator,
            .writer = std.io.getStdOut().writer(),
            .message = message,
            .spinner_chars = &DOTS,
            .current_frame = 0,
            .show_elapsed = true,
            .start_time = std.time.timestamp(),
        };
    }

    /// Create a progress indicator with custom spinner
    pub fn initWithSpinner(allocator: std.mem.Allocator, message: []const u8, spinner: []const []const u8) Self {
        var indicator = init(allocator, message);
        indicator.spinner_chars = spinner;
        return indicator;
    }

    /// Show a single frame of the progress indicator
    pub fn tick(self: *Self) !void {
        // Clear current line
        try self.writer.writeAll("\r\x1b[K");

        // Show spinner and message
        const spinner_char = self.spinner_chars[self.current_frame % self.spinner_chars.len];
        
        if (self.show_elapsed) {
            const elapsed = std.time.timestamp() - self.start_time;
            const seconds = @mod(elapsed, 60);
            const minutes = @divTrunc(elapsed, 60);
            
            if (minutes > 0) {
                try self.writer.print("{s}{s}{s} {s} ({d}m {d}s)", .{
                    Color.cyan, spinner_char, Color.reset, self.message, minutes, seconds
                });
            } else {
                try self.writer.print("{s}{s}{s} {s} ({d}s)", .{
                    Color.cyan, spinner_char, Color.reset, self.message, seconds
                });
            }
        } else {
            try self.writer.print("{s}{s}{s} {s}", .{
                Color.cyan, spinner_char, Color.reset, self.message
            });
        }

        self.current_frame += 1;
    }

    /// Complete the progress indicator with success message
    pub fn complete(self: *Self, success_message: ?[]const u8) !void {
        // Clear current line
        try self.writer.writeAll("\r\x1b[K");
        
        const final_message = success_message orelse self.message;
        
        if (self.show_elapsed) {
            const elapsed = std.time.timestamp() - self.start_time;
            const seconds = @mod(elapsed, 60);
            const minutes = @divTrunc(elapsed, 60);
            
            if (minutes > 0) {
                try self.writer.print("{s}✓{s} {s} ({d}m {d}s)\n", .{
                    Color.green, Color.reset, final_message, minutes, seconds
                });
            } else {
                try self.writer.print("{s}✓{s} {s} ({d}s)\n", .{
                    Color.green, Color.reset, final_message, seconds
                });
            }
        } else {
            try self.writer.print("{s}✓{s} {s}\n", .{
                Color.green, Color.reset, final_message
            });
        }
    }

    /// Complete the progress indicator with error message
    pub fn fail(self: *Self, error_message: ?[]const u8) !void {
        // Clear current line
        try self.writer.writeAll("\r\x1b[K");
        
        const final_message = error_message orelse self.message;
        try self.writer.print("{s}✗{s} {s}\n", .{
            Color.red, Color.reset, final_message
        });
    }

    /// Update the message without changing timing
    pub fn updateMessage(self: *Self, new_message: []const u8) void {
        self.message = new_message;
    }

    /// Set whether to show elapsed time
    pub fn showElapsed(self: *Self, show: bool) void {
        self.show_elapsed = show;
    }
};

/// Progress bar for operations with known total
pub const ProgressBar = struct {
    allocator: std.mem.Allocator,
    writer: std.fs.File.Writer,
    message: []const u8,
    total: usize,
    current: usize,
    width: usize,
    start_time: i64,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, message: []const u8, total: usize) Self {
        return Self{
            .allocator = allocator,
            .writer = std.io.getStdOut().writer(),
            .message = message,
            .total = total,
            .current = 0,
            .width = 40,
            .start_time = std.time.timestamp(),
        };
    }

    /// Update progress and display bar
    pub fn update(self: *Self, current: usize) !void {
        self.current = current;
        
        // Clear current line
        try self.writer.writeAll("\r\x1b[K");
        
        // Calculate progress
        const percentage = if (self.total > 0) (self.current * 100) / self.total else 0;
        const filled = if (self.total > 0) (self.current * self.width) / self.total else 0;
        
        // Show progress bar
        try self.writer.print("{s} [", .{self.message});
        
        var i: usize = 0;
        while (i < self.width) : (i += 1) {
            if (i < filled) {
                try self.writer.writeAll("█");
            } else {
                try self.writer.writeAll("░");
            }
        }
        
        try self.writer.print("] {d}% ({d}/{d})", .{ percentage, self.current, self.total });
    }

    /// Complete the progress bar
    pub fn complete(self: *Self, success_message: ?[]const u8) !void {
        try self.update(self.total);
        
        const final_message = success_message orelse self.message;
        const elapsed = std.time.timestamp() - self.start_time;
        
        try self.writer.print(" - {s}{s}{s} ({d}s)\n", .{
            Color.green, final_message, Color.reset, elapsed
        });
    }
};

/// Simple progress tracking for operations
pub const SimpleProgress = struct {
    /// Show a simple progress message
    pub fn show(message: []const u8) !void {
        const stdout = std.io.getStdOut().writer();
        try stdout.print("  → {s}...\n", .{message});
    }

    /// Show success message
    pub fn success(message: []const u8) !void {
        const stdout = std.io.getStdOut().writer();
        try stdout.print("  {s}✓{s} {s}\n", .{ Color.green, Color.reset, message });
    }

    /// Show error message
    pub fn fail(message: []const u8) !void {
        const stderr = std.io.getStdErr().writer();
        try stderr.print("  {s}✗{s} {s}\n", .{ Color.red, Color.reset, message });
    }

    /// Show warning message
    pub fn warn(message: []const u8) !void {
        const stdout = std.io.getStdOut().writer();
        try stdout.print("  {s}⚠{s} {s}\n", .{ Color.yellow, Color.reset, message });
    }
};

/// Thread-safe progress updater for background operations
pub const BackgroundProgress = struct {
    indicator: *ProgressIndicator,
    running: std.atomic.Value(bool),
    thread: ?std.Thread,

    const Self = @This();

    pub fn init(indicator: *ProgressIndicator) Self {
        return Self{
            .indicator = indicator,
            .running = std.atomic.Value(bool).init(true),
            .thread = null,
        };
    }

    /// Start background animation thread
    pub fn start(self: *Self) !void {
        self.thread = try std.Thread.spawn(.{}, animateLoop, .{self});
    }

    /// Stop background animation
    pub fn stop(self: *Self) void {
        self.running.store(false, .release);
        if (self.thread) |thread| {
            thread.join();
            self.thread = null;
        }
    }

    /// Complete with success
    pub fn complete(self: *Self, message: ?[]const u8) !void {
        self.stop();
        try self.indicator.complete(message);
    }

    /// Complete with failure
    pub fn fail(self: *Self, message: ?[]const u8) !void {
        self.stop();
        try self.indicator.fail(message);
    }

    fn animateLoop(self: *Self) void {
        while (self.running.load(.acquire)) {
            self.indicator.tick() catch break;
            std.time.sleep(100 * std.time.ns_per_ms); // 100ms between frames
        }
    }
};