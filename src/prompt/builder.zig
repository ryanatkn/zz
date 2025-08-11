const std = @import("std");
const fence = @import("fence.zig");

pub const PromptBuilder = struct {
    allocator: std.mem.Allocator,
    lines: std.ArrayList([]const u8),
    arena: std.heap.ArenaAllocator,
    quiet: bool,

    const Self = @This();
    const max_file_size = 10 * 1024 * 1024; // 10MB

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .lines = std.ArrayList([]const u8).init(allocator),
            .arena = std.heap.ArenaAllocator.init(allocator),
            .quiet = false,
        };
    }

    pub fn initQuiet(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .lines = std.ArrayList([]const u8).init(allocator),
            .arena = std.heap.ArenaAllocator.init(allocator),
            .quiet = true,
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
        const file = try std.fs.cwd().openFile(file_path, .{});
        defer file.close();

        const stat = try file.stat();
        if (stat.size > max_file_size) {
            if (!self.quiet) {
                const stderr = std.io.getStdErr().writer();
                try stderr.print("Warning: Skipping large file (>{d}MB): {s}\n", .{ max_file_size / (1024 * 1024), file_path });
            }
            return;
        }

        const content = try file.readToEndAlloc(self.arena.allocator(), stat.size);

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

test "PromptBuilder basic" {
    var builder = PromptBuilder.init(std.testing.allocator);
    defer builder.deinit();

    try builder.addText("Test instructions");
    try std.testing.expect(builder.lines.items.len > 0);
}

test "prompt builder output format" {
    const allocator = std.testing.allocator;

    var builder = PromptBuilder.init(allocator);
    defer builder.deinit();

    // Add text
    try builder.addText("Test instructions");

    // Write to buffer
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();

    try builder.write(buf.writer());

    const output = buf.items;
    try std.testing.expect(std.mem.indexOf(u8, output, "Test instructions") != null);
}

test "deduplication of file paths" {
    const allocator = std.testing.allocator;
    const GlobExpander = @import("glob.zig").GlobExpander;

    // Create temp directory structure for testing
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Create test files
    try tmp_dir.dir.writeFile(.{ .sub_path = "test1.zig", .data = "const a = 1;" });
    try tmp_dir.dir.writeFile(.{ .sub_path = "test2.zig", .data = "const b = 2;" });
    try tmp_dir.dir.makeDir("sub");
    try tmp_dir.dir.writeFile(.{ .sub_path = "sub/test3.zig", .data = "const c = 3;" });

    // Get temp path
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp_dir.dir.realpath(".", &path_buf);

    // Test deduplication with multiple patterns that match same files
    var expander = GlobExpander.init(allocator);

    // Create patterns that will match some of the same files
    var patterns = [_][]const u8{
        try std.fmt.allocPrint(allocator, "{s}/test1.zig", .{tmp_path}),
        try std.fmt.allocPrint(allocator, "{s}/*.zig", .{tmp_path}),
        try std.fmt.allocPrint(allocator, "{s}/test1.zig", .{tmp_path}), // Duplicate
    };
    defer for (patterns) |pattern| allocator.free(pattern);

    var file_paths = try expander.expandGlobs(&patterns);
    defer {
        for (file_paths.items) |path| {
            allocator.free(path);
        }
        file_paths.deinit();
    }

    // Deduplicate
    var seen = std.StringHashMap(void).init(allocator);
    defer seen.deinit();

    var unique_paths = std.ArrayList([]u8).init(allocator);
    defer unique_paths.deinit();

    for (file_paths.items) |path| {
        if (!seen.contains(path)) {
            try seen.put(path, {});
            try unique_paths.append(path);
        }
    }

    // Should have only 2 unique files (test1.zig and test2.zig)
    try std.testing.expect(unique_paths.items.len == 2);
}
