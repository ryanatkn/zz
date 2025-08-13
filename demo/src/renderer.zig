// Terminal rendering utilities with ANSI colors and formatting
const std = @import("std");

pub const Color = struct {
    pub const reset = "\x1b[0m";
    pub const bold = "\x1b[1m";
    pub const dim = "\x1b[2m";
    pub const italic = "\x1b[3m";
    pub const underline = "\x1b[4m";
    
    // Regular colors
    pub const black = "\x1b[30m";
    pub const red = "\x1b[31m";
    pub const green = "\x1b[32m";
    pub const yellow = "\x1b[33m";
    pub const blue = "\x1b[34m";
    pub const magenta = "\x1b[35m";
    pub const cyan = "\x1b[36m";
    pub const white = "\x1b[37m";
    pub const gray = "\x1b[90m";
    
    // Bright colors
    pub const bright_red = "\x1b[91m";
    pub const bright_green = "\x1b[92m";
    pub const bright_yellow = "\x1b[93m";
    pub const bright_blue = "\x1b[94m";
    pub const bright_magenta = "\x1b[95m";
    pub const bright_cyan = "\x1b[96m";
    pub const bright_white = "\x1b[97m";
    
    // Background colors
    pub const bg_black = "\x1b[40m";
    pub const bg_red = "\x1b[41m";
    pub const bg_green = "\x1b[42m";
    pub const bg_yellow = "\x1b[43m";
    pub const bg_blue = "\x1b[44m";
    pub const bg_magenta = "\x1b[45m";
    pub const bg_cyan = "\x1b[46m";
    pub const bg_white = "\x1b[47m";
};

pub const Box = struct {
    // Box drawing characters
    pub const horizontal = "─";
    pub const vertical = "│";
    pub const top_left = "┌";
    pub const top_right = "┐";
    pub const bottom_left = "└";
    pub const bottom_right = "┘";
    pub const cross = "┼";
    pub const t_down = "┬";
    pub const t_up = "┴";
    pub const t_right = "├";
    pub const t_left = "┤";
    
    // Double lines
    pub const double_horizontal = "═";
    pub const double_vertical = "║";
    pub const double_top_left = "╔";
    pub const double_top_right = "╗";
    pub const double_bottom_left = "╚";
    pub const double_bottom_right = "╝";
};

pub const Terminal = struct {
    stdout: std.fs.File.Writer,
    
    pub fn init() Terminal {
        return .{
            .stdout = std.io.getStdOut().writer(),
        };
    }
    
    pub fn clearScreen(self: Terminal) !void {
        try self.stdout.print("\x1b[2J\x1b[H", .{});
    }
    
    pub fn moveCursor(self: Terminal, row: u32, col: u32) !void {
        try self.stdout.print("\x1b[{};{}H", .{ row, col });
    }
    
    pub fn hideCursor(self: Terminal) !void {
        try self.stdout.print("\x1b[?25l", .{});
    }
    
    pub fn showCursor(self: Terminal) !void {
        try self.stdout.print("\x1b[?25h", .{});
    }
    
    pub fn drawBox(self: Terminal, x: u32, y: u32, width: u32, height: u32, title: ?[]const u8) !void {
        // Top border
        try self.moveCursor(y, x);
        try self.stdout.print("{s}{s}{s}", .{ Color.cyan, Box.double_top_left, Color.reset });
        
        if (title) |t| {
            const padding = (width - t.len - 4) / 2;
            var i: u32 = 0;
            while (i < padding) : (i += 1) {
                try self.stdout.print("{s}", .{Box.double_horizontal});
            }
            try self.stdout.print(" {s}{s}{s} ", .{ Color.bright_white, t, Color.cyan });
            i = @as(u32, @intCast(padding + t.len + 4));
            while (i < width - 2) : (i += 1) {
                try self.stdout.print("{s}", .{Box.double_horizontal});
            }
        } else {
            var i: u32 = 0;
            while (i < width - 2) : (i += 1) {
                try self.stdout.print("{s}", .{Box.double_horizontal});
            }
        }
        try self.stdout.print("{s}{s}\n", .{ Box.double_top_right, Color.reset });
        
        // Sides
        var row: u32 = 1;
        while (row < height - 1) : (row += 1) {
            try self.moveCursor(y + row, x);
            try self.stdout.print("{s}{s}{s}", .{ Color.cyan, Box.double_vertical, Color.reset });
            try self.moveCursor(y + row, x + width - 1);
            try self.stdout.print("{s}{s}{s}\n", .{ Color.cyan, Box.double_vertical, Color.reset });
        }
        
        // Bottom border
        try self.moveCursor(y + height - 1, x);
        try self.stdout.print("{s}{s}", .{ Color.cyan, Box.double_bottom_left });
        var i: u32 = 0;
        while (i < width - 2) : (i += 1) {
            try self.stdout.print("{s}", .{Box.double_horizontal});
        }
        try self.stdout.print("{s}{s}\n", .{ Box.double_bottom_right, Color.reset });
    }
    
    pub fn printColored(self: Terminal, text: []const u8, color: []const u8) !void {
        try self.stdout.print("{s}{s}{s}", .{ color, text, Color.reset });
    }
    
    pub fn printLine(self: Terminal, text: []const u8) !void {
        try self.stdout.print("{s}\n", .{text});
    }
    
    pub fn drawProgressBar(self: Terminal, progress: f32, width: u32, label: []const u8) !void {
        const filled = @as(u32, @intFromFloat(@floor(@as(f32, @floatFromInt(width)) * progress)));
        const empty = width - filled;
        
        try self.stdout.print("{s}: [", .{label});
        
        // Filled portion
        try self.stdout.print("{s}", .{Color.bright_green});
        var i: u32 = 0;
        while (i < filled) : (i += 1) {
            try self.stdout.print("█", .{});
        }
        
        // Empty portion
        try self.stdout.print("{s}", .{Color.gray});
        i = 0;
        while (i < empty) : (i += 1) {
            try self.stdout.print("░", .{});
        }
        
        try self.stdout.print("{s}] {d:.1}%\n", .{ Color.reset, progress * 100 });
    }
    
    pub fn highlightCode(self: Terminal, code: []const u8, language: []const u8) !void {
        // Simple syntax highlighting based on language
        const lines = std.mem.tokenizeScalar(u8, code, '\n');
        var iter = lines;
        
        while (iter.next()) |line| {
            if (std.mem.eql(u8, language, "typescript") or std.mem.eql(u8, language, "javascript")) {
                try self.highlightTypeScript(line);
            } else if (std.mem.eql(u8, language, "css")) {
                try self.highlightCss(line);
            } else if (std.mem.eql(u8, language, "html")) {
                try self.highlightHtml(line);
            } else {
                try self.stdout.print("{s}\n", .{line});
            }
        }
    }
    
    fn highlightTypeScript(self: Terminal, line: []const u8) !void {
        const trimmed = std.mem.trim(u8, line, " \t");
        
        if (std.mem.startsWith(u8, trimmed, "//")) {
            try self.stdout.print("{s}{s}{s}\n", .{ Color.gray, line, Color.reset });
        } else if (std.mem.startsWith(u8, trimmed, "import") or 
                   std.mem.startsWith(u8, trimmed, "export") or
                   std.mem.startsWith(u8, trimmed, "const") or
                   std.mem.startsWith(u8, trimmed, "let") or
                   std.mem.startsWith(u8, trimmed, "var")) {
            try self.stdout.print("{s}{s}{s}\n", .{ Color.magenta, line, Color.reset });
        } else if (std.mem.startsWith(u8, trimmed, "interface") or
                   std.mem.startsWith(u8, trimmed, "type") or
                   std.mem.startsWith(u8, trimmed, "class")) {
            try self.stdout.print("{s}{s}{s}\n", .{ Color.blue, line, Color.reset });
        } else if (std.mem.startsWith(u8, trimmed, "function") or
                   std.mem.startsWith(u8, trimmed, "async")) {
            try self.stdout.print("{s}{s}{s}\n", .{ Color.yellow, line, Color.reset });
        } else {
            try self.stdout.print("{s}\n", .{line});
        }
    }
    
    fn highlightCss(self: Terminal, line: []const u8) !void {
        const trimmed = std.mem.trim(u8, line, " \t");
        
        if (std.mem.startsWith(u8, trimmed, "/*") or std.mem.startsWith(u8, trimmed, "*")) {
            try self.stdout.print("{s}{s}{s}\n", .{ Color.gray, line, Color.reset });
        } else if (std.mem.startsWith(u8, trimmed, "@")) {
            try self.stdout.print("{s}{s}{s}\n", .{ Color.magenta, line, Color.reset });
        } else if (std.mem.startsWith(u8, trimmed, ".") or std.mem.startsWith(u8, trimmed, "#")) {
            try self.stdout.print("{s}{s}{s}\n", .{ Color.cyan, line, Color.reset });
        } else if (std.mem.indexOf(u8, trimmed, ":") != null) {
            try self.stdout.print("{s}{s}{s}\n", .{ Color.green, line, Color.reset });
        } else {
            try self.stdout.print("{s}\n", .{line});
        }
    }
    
    fn highlightHtml(self: Terminal, line: []const u8) !void {
        const trimmed = std.mem.trim(u8, line, " \t");
        
        if (std.mem.startsWith(u8, trimmed, "<!--")) {
            try self.stdout.print("{s}{s}{s}\n", .{ Color.gray, line, Color.reset });
        } else if (std.mem.startsWith(u8, trimmed, "<!") or std.mem.startsWith(u8, trimmed, "<")) {
            try self.stdout.print("{s}{s}{s}\n", .{ Color.blue, line, Color.reset });
        } else {
            try self.stdout.print("{s}\n", .{line});
        }
    }
};