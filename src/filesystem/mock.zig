const std = @import("std");
const FilesystemInterface = @import("interface.zig").FilesystemInterface;
const DirHandle = @import("interface.zig").DirHandle;
const FileHandle = @import("interface.zig").FileHandle;
const DirIterator = @import("interface.zig").DirIterator;
const path_utils = @import("../lib/path.zig");

/// Mock filesystem for testing
pub const MockFilesystem = struct {
    allocator: std.mem.Allocator,
    files: std.StringHashMap(FileEntry),

    const Self = @This();

    const FileEntry = struct {
        kind: std.fs.File.Kind,
        size: u64 = 0,
        content: []const u8 = "",
    };

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .files = std.StringHashMap(FileEntry).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        var iter = self.files.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            if (entry.value_ptr.content.len > 0) {
                self.allocator.free(entry.value_ptr.content);
            }
        }
        self.files.deinit();
    }

    pub fn addFile(self: *Self, path: []const u8, content: []const u8) !void {
        const owned_path = try self.allocator.dupe(u8, path);
        const owned_content = try self.allocator.dupe(u8, content);
        try self.files.put(owned_path, FileEntry{
            .kind = .file,
            .size = content.len,
            .content = owned_content,
        });
    }

    pub fn addDirectory(self: *Self, path: []const u8) !void {
        const owned_path = try self.allocator.dupe(u8, path);
        try self.files.put(owned_path, FileEntry{
            .kind = .directory,
        });
    }

    pub fn interface(self: *Self) FilesystemInterface {
        return FilesystemInterface{
            .ptr = self,
            .vtable = &.{
                .openDir = openDir,
                .statFile = statFile,
                .cwd = cwd,
                .pathJoin = pathJoin,
                .pathBasename = pathBasename,
                .pathExtension = pathExtension,
            },
        };
    }

    fn openDir(ptr: *anyopaque, allocator: std.mem.Allocator, path: []const u8, options: std.fs.Dir.OpenDirOptions) !DirHandle {
        _ = options;
        const self: *Self = @ptrCast(@alignCast(ptr));

        // Check if directory exists
        if (!self.files.contains(path)) {
            return error.FileNotFound;
        }

        const entry = self.files.get(path).?;
        if (entry.kind != .directory) {
            return error.NotDir;
        }

        return MockDirHandle.init(allocator, self, path);
    }

    fn statFile(ptr: *anyopaque, allocator: std.mem.Allocator, path: []const u8) !std.fs.File.Stat {
        _ = allocator;
        const self: *Self = @ptrCast(@alignCast(ptr));

        const entry = self.files.get(path) orelse return error.FileNotFound;

        return std.fs.File.Stat{
            .kind = entry.kind,
            .size = entry.size,
            .inode = 0,
            .mode = 0o644,
            .atime = 0,
            .mtime = 0,
            .ctime = 0,
        };
    }

    fn cwd(ptr: *anyopaque) DirHandle {
        const self: *Self = @ptrCast(@alignCast(ptr));
        // The "." directory should already exist - MockTestContext creates it
        return MockDirHandle.init(self.allocator, self, ".") catch |err| {
            std.debug.panic("MockFilesystem cwd() failed - '.' directory should exist: {}", .{err});
        };
    }

    fn pathJoin(ptr: *anyopaque, allocator: std.mem.Allocator, paths: []const []const u8) ![]u8 {
        _ = ptr;
        return path_utils.joinPaths(allocator, paths);
    }

    fn pathBasename(ptr: *anyopaque, path: []const u8) []const u8 {
        _ = ptr;
        return path_utils.basename(path);
    }

    fn pathExtension(ptr: *anyopaque, path: []const u8) []const u8 {
        _ = ptr;
        return path_utils.extension(path);
    }
};

/// Mock directory handle
const MockDirHandle = struct {
    allocator: std.mem.Allocator,
    filesystem: *MockFilesystem,
    path: []const u8,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, filesystem: *MockFilesystem, path: []const u8) !DirHandle {
        const self = try allocator.create(Self);
        self.* = Self{
            .allocator = allocator,
            .filesystem = filesystem,
            .path = try allocator.dupe(u8, path),
        };

        return DirHandle{
            .ptr = self,
            .vtable = &.{
                .iterate = iterate,
                .openDir = openDir,
                .close = close,
                .statFile = statFile,
                .readFileAlloc = readFileAlloc,
                .openFile = openFile,
            },
        };
    }

    fn iterate(ptr: *anyopaque, allocator: std.mem.Allocator) !DirIterator {
        const self: *Self = @ptrCast(@alignCast(ptr));
        return MockDirIterator.init(allocator, self.filesystem, self.path);
    }

    fn openDir(ptr: *anyopaque, allocator: std.mem.Allocator, sub_path: []const u8, options: std.fs.Dir.OpenDirOptions) !DirHandle {
        _ = options;
        const self: *Self = @ptrCast(@alignCast(ptr));

        const full_path = if (std.mem.eql(u8, self.path, "."))
            try allocator.dupe(u8, sub_path)
        else
            try path_utils.joinPaths(allocator, &.{ self.path, sub_path });
        defer allocator.free(full_path);

        return MockDirHandle.init(allocator, self.filesystem, full_path);
    }

    fn close(ptr: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        self.allocator.free(self.path);
        self.allocator.destroy(self);
    }

    fn statFile(ptr: *anyopaque, allocator: std.mem.Allocator, path: []const u8) !std.fs.File.Stat {
        const self: *Self = @ptrCast(@alignCast(ptr));

        const full_path = if (std.mem.eql(u8, self.path, "."))
            try allocator.dupe(u8, path)
        else
            try path_utils.joinPaths(allocator, &.{ self.path, path });
        defer allocator.free(full_path);

        const fs_interface = self.filesystem.interface();
        return fs_interface.statFile(allocator, full_path);
    }

    fn readFileAlloc(ptr: *anyopaque, allocator: std.mem.Allocator, path: []const u8, max_bytes: usize) ![]u8 {
        const self: *Self = @ptrCast(@alignCast(ptr));

        const full_path = if (std.mem.eql(u8, self.path, "."))
            try allocator.dupe(u8, path)
        else
            try path_utils.joinPaths(allocator, &.{ self.path, path });
        defer allocator.free(full_path);

        const entry = self.filesystem.files.get(full_path) orelse return error.FileNotFound;
        if (entry.kind != .file) return error.IsDir;

        const size = @min(entry.content.len, max_bytes);
        const content = try allocator.alloc(u8, size);
        @memcpy(content, entry.content[0..size]);
        return content;
    }

    fn openFile(ptr: *anyopaque, allocator: std.mem.Allocator, path: []const u8, flags: std.fs.File.OpenFlags) !FileHandle {
        _ = flags;
        const self: *Self = @ptrCast(@alignCast(ptr));

        const full_path = if (std.mem.eql(u8, self.path, "."))
            try allocator.dupe(u8, path)
        else
            try path_utils.joinPaths(allocator, &.{ self.path, path });
        defer allocator.free(full_path);

        const entry = self.filesystem.files.get(full_path) orelse return error.FileNotFound;
        if (entry.kind != .file) return error.IsDir;

        return MockFileHandle.init(allocator, entry.content);
    }
};

/// Mock file handle
const MockFileHandle = struct {
    allocator: std.mem.Allocator,
    content: []const u8,
    position: usize,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, content: []const u8) !FileHandle {
        const self = try allocator.create(Self);
        self.* = Self{
            .allocator = allocator,
            .content = content,
            .position = 0,
        };

        return FileHandle{
            .ptr = self,
            .vtable = &.{
                .close = close,
                .reader = reader,
                .readAll = readAll,
            },
        };
    }

    fn close(ptr: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        self.allocator.destroy(self);
    }

    fn reader(ptr: *anyopaque) std.io.AnyReader {
        const self: *Self = @ptrCast(@alignCast(ptr));
        var fixed_buffer_stream = std.io.fixedBufferStream(self.content[self.position..]);
        return fixed_buffer_stream.reader().any();
    }

    fn readAll(ptr: *anyopaque, allocator: std.mem.Allocator, max_bytes: usize) ![]u8 {
        const self: *Self = @ptrCast(@alignCast(ptr));
        const remaining = self.content.len - self.position;
        const size = @min(remaining, max_bytes);
        const result = try allocator.alloc(u8, size);
        @memcpy(result, self.content[self.position .. self.position + size]);
        self.position += size;
        return result;
    }
};

/// Mock directory iterator
const MockDirIterator = struct {
    allocator: std.mem.Allocator,
    filesystem: *MockFilesystem,
    parent_path: []const u8,
    entries: std.ArrayList([]const u8),
    index: usize,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, filesystem: *MockFilesystem, parent_path: []const u8) !DirIterator {
        const self = try allocator.create(Self);
        self.* = Self{
            .allocator = allocator,
            .filesystem = filesystem,
            .parent_path = try allocator.dupe(u8, parent_path),
            .entries = std.ArrayList([]const u8).init(allocator),
            .index = 0,
        };

        // Collect entries that are direct children of parent_path
        var iter = filesystem.files.iterator();
        while (iter.next()) |entry| {
            const entry_path = entry.key_ptr.*;

            // Skip the parent path itself
            if (std.mem.eql(u8, entry_path, parent_path)) continue;

            // Check if this entry is a direct child
            const relative_path = if (std.mem.eql(u8, parent_path, "."))
                entry_path
            else if (std.mem.startsWith(u8, entry_path, parent_path) and entry_path.len > parent_path.len and entry_path[parent_path.len] == '/')
                entry_path[parent_path.len + 1 ..]
            else
                continue;

            // Only include direct children (no nested paths)
            if (std.mem.indexOf(u8, relative_path, "/") == null) {
                try self.entries.append(try allocator.dupe(u8, relative_path));
            }
        }

        return DirIterator{
            .ptr = self,
            .vtable = &.{
                .next = next,
            },
        };
    }

    fn next(ptr: *anyopaque, allocator: std.mem.Allocator) !?std.fs.Dir.Entry {
        _ = allocator;
        const self: *Self = @ptrCast(@alignCast(ptr));

        if (self.index >= self.entries.items.len) {
            // Clean up when done
            for (self.entries.items) |entry| {
                self.allocator.free(entry);
            }
            self.entries.deinit();
            self.allocator.free(self.parent_path);
            self.allocator.destroy(self);
            return null;
        }

        const entry_name = self.entries.items[self.index];
        self.index += 1;

        // Get the full path to determine the kind
        const full_path = if (std.mem.eql(u8, self.parent_path, "."))
            entry_name
        else
            try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ self.parent_path, entry_name });
        defer if (!std.mem.eql(u8, self.parent_path, ".")) self.allocator.free(full_path);

        const file_entry = self.filesystem.files.get(full_path) orelse return error.FileNotFound;

        return std.fs.Dir.Entry{
            .name = entry_name,
            .kind = file_entry.kind,
        };
    }
};
