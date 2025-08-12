const std = @import("std");
const fence = @import("fence.zig");
const FilesystemInterface = @import("../filesystem.zig").FilesystemInterface;

pub const PromptBuilder = struct {
    allocator: std.mem.Allocator,
    lines: std.ArrayList([]const u8),
    arena: std.heap.ArenaAllocator,
    quiet: bool,
    filesystem: FilesystemInterface,

    const Self = @This();
    const max_file_size = 10 * 1024 * 1024; // 10MB

    pub fn init(allocator: std.mem.Allocator, filesystem: FilesystemInterface) Self {
        return Self{
            .allocator = allocator,
            .lines = std.ArrayList([]const u8).init(allocator),
            .arena = std.heap.ArenaAllocator.init(allocator),
            .quiet = false,
            .filesystem = filesystem,
        };
    }

    pub fn initQuiet(allocator: std.mem.Allocator, filesystem: FilesystemInterface) Self {
        return Self{
            .allocator = allocator,
            .lines = std.ArrayList([]const u8).init(allocator),
            .arena = std.heap.ArenaAllocator.init(allocator),
            .quiet = true,
            .filesystem = filesystem,
        };
    }

    pub fn deinit(self: *Self) void {
        self.lines.deinit();
        self.arena.deinit();
    }

    pub fn addText(self: *Self, text: []const u8) !void {
        const text_copy = try self.arena.allocator().dupe(u8, text);
        try self.lines.append(text_copy);
        try self.lines.append("");
    }

    pub fn addFile(self: *Self, file_path: []const u8) !void {
        const cwd = self.filesystem.cwd();
        defer cwd.close();
        
        const file = try cwd.openFile(self.allocator, file_path, .{});
        defer file.close();

        const stat = try cwd.statFile(self.allocator, file_path);
        if (stat.size > max_file_size) {
            if (!self.quiet) {
                const stderr = std.io.getStdErr().writer();
                try stderr.print("Warning: Skipping large file (>{d}MB): {s}\n", .{ max_file_size / (1024 * 1024), file_path });
            }
            return;
        }

        const content = try file.readAll(self.arena.allocator(), stat.size);

        // Detect file extension for syntax highlighting
        const ext = std.fs.path.extension(file_path);
        const lang = if (ext.len > 0) ext[1..] else "";

        // Detect appropriate fence
        const fence_str = try fence.detectFence(content, self.arena.allocator());

        // Add file with XML-style tags and markdown code fence
        const header = try std.fmt.allocPrint(self.arena.allocator(), "<File path=\"{s}\">", .{file_path});
        try self.lines.append("");
        try self.lines.append(header);
        try self.lines.append("");

        const fence_start = try std.fmt.allocPrint(self.arena.allocator(), "{s}{s}", .{ fence_str, lang });
        try self.lines.append(fence_start);

        // Add content line by line
        var iter = std.mem.splitScalar(u8, content, '\n');
        while (iter.next()) |line| {
            // Only add non-empty lines or preserve empty lines in code blocks
            try self.lines.append(line);
        }

        try self.lines.append(fence_str);
        try self.lines.append("");
        try self.lines.append("</File>");
        try self.lines.append("");
    }

    pub fn addFiles(self: *Self, file_paths: [][]u8) !void {
        for (file_paths) |file_path| {
            try self.addFile(file_path);
        }
    }

    pub fn write(self: *Self, writer: anytype) !void {
        for (self.lines.items) |line| {
            try writer.print("{s}\n", .{line});
        }
    }
};
