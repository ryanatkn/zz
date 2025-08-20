const std = @import("std");
const path_utils = @import("../core/path.zig");

// Consolidate filesystem interface imports
const interface_types = @import("interface.zig");
const FilesystemInterface = interface_types.FilesystemInterface;
const DirHandle = interface_types.DirHandle;
const FileHandle = interface_types.FileHandle;
const DirIterator = interface_types.DirIterator;

/// Real filesystem implementation for production use
pub const RealFilesystem = struct {
    const Self = @This();

    pub fn init() FilesystemInterface {
        const self = std.heap.page_allocator.create(Self) catch unreachable;
        self.* = Self{};

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
        _ = allocator;
        _ = ptr;
        const dir = try std.fs.cwd().openDir(path, options);
        return RealDirHandle.init(dir);
    }

    fn statFile(ptr: *anyopaque, allocator: std.mem.Allocator, path: []const u8) !std.fs.File.Stat {
        _ = allocator;
        _ = ptr;
        return std.fs.cwd().statFile(path);
    }

    fn cwd(ptr: *anyopaque) DirHandle {
        _ = ptr;
        return RealDirHandle.initFromCwd();
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

/// Real directory handle wrapper
const RealDirHandle = struct {
    dir: std.fs.Dir,
    owns_dir: bool,

    const Self = @This();

    pub fn init(dir: std.fs.Dir) DirHandle {
        const self = std.heap.page_allocator.create(Self) catch unreachable;
        self.* = Self{
            .dir = dir,
            .owns_dir = true,
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

    pub fn initFromCwd() DirHandle {
        const self = std.heap.page_allocator.create(Self) catch unreachable;
        self.* = Self{
            .dir = std.fs.cwd(),
            .owns_dir = false,
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
        _ = allocator;
        const self: *Self = @ptrCast(@alignCast(ptr));
        const iter = self.dir.iterate();
        return RealDirIterator.init(iter);
    }

    fn openDir(ptr: *anyopaque, allocator: std.mem.Allocator, sub_path: []const u8, options: std.fs.Dir.OpenDirOptions) !DirHandle {
        _ = allocator;
        const self: *Self = @ptrCast(@alignCast(ptr));
        const dir = try self.dir.openDir(sub_path, options);
        return RealDirHandle.init(dir);
    }

    fn close(ptr: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        if (self.owns_dir) {
            self.dir.close();
        }
        std.heap.page_allocator.destroy(self);
    }

    fn statFile(ptr: *anyopaque, allocator: std.mem.Allocator, path: []const u8) !std.fs.File.Stat {
        _ = allocator;
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.dir.statFile(path);
    }

    fn readFileAlloc(ptr: *anyopaque, allocator: std.mem.Allocator, path: []const u8, max_bytes: usize) ![]u8 {
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.dir.readFileAlloc(allocator, path, max_bytes);
    }

    fn openFile(ptr: *anyopaque, allocator: std.mem.Allocator, path: []const u8, flags: std.fs.File.OpenFlags) !FileHandle {
        _ = allocator;
        const self: *Self = @ptrCast(@alignCast(ptr));
        const file = try self.dir.openFile(path, flags);
        return RealFileHandle.init(file);
    }
};

/// Real file handle wrapper
const RealFileHandle = struct {
    file: std.fs.File,

    const Self = @This();

    pub fn init(file: std.fs.File) FileHandle {
        const self = std.heap.page_allocator.create(Self) catch unreachable;
        self.* = Self{
            .file = file,
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
        self.file.close();
        std.heap.page_allocator.destroy(self);
    }

    fn reader(ptr: *anyopaque) std.io.AnyReader {
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.file.reader().any();
    }

    fn readAll(ptr: *anyopaque, allocator: std.mem.Allocator, max_bytes: usize) ![]u8 {
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.file.readToEndAlloc(allocator, max_bytes);
    }
};

/// Real directory iterator wrapper
const RealDirIterator = struct {
    iter: std.fs.Dir.Iterator,

    const Self = @This();

    pub fn init(iter: std.fs.Dir.Iterator) DirIterator {
        const self = std.heap.page_allocator.create(Self) catch unreachable;
        self.* = Self{
            .iter = iter,
        };

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
        return self.iter.next();
    }
};
