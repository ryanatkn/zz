const std = @import("std");

/// Abstract filesystem interface for parameterized dependencies and testing
pub const FilesystemInterface = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    const VTable = struct {
        openDir: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator, path: []const u8, options: std.fs.Dir.OpenDirOptions) anyerror!DirHandle,
        statFile: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator, path: []const u8) anyerror!std.fs.File.Stat,
        cwd: *const fn (ptr: *anyopaque) DirHandle,
        pathJoin: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator, paths: []const []const u8) anyerror![]u8,
        pathBasename: *const fn (ptr: *anyopaque, path: []const u8) []const u8,
        pathExtension: *const fn (ptr: *anyopaque, path: []const u8) []const u8,
    };

    pub fn openDir(self: FilesystemInterface, allocator: std.mem.Allocator, path: []const u8, options: std.fs.Dir.OpenDirOptions) !DirHandle {
        return self.vtable.openDir(self.ptr, allocator, path, options);
    }

    pub fn statFile(self: FilesystemInterface, allocator: std.mem.Allocator, path: []const u8) !std.fs.File.Stat {
        return self.vtable.statFile(self.ptr, allocator, path);
    }

    pub fn cwd(self: FilesystemInterface) DirHandle {
        return self.vtable.cwd(self.ptr);
    }

    pub fn pathJoin(self: FilesystemInterface, allocator: std.mem.Allocator, paths: []const []const u8) ![]u8 {
        return self.vtable.pathJoin(self.ptr, allocator, paths);
    }

    pub fn pathBasename(self: FilesystemInterface, path: []const u8) []const u8 {
        return self.vtable.pathBasename(self.ptr, path);
    }

    pub fn pathExtension(self: FilesystemInterface, path: []const u8) []const u8 {
        return self.vtable.pathExtension(self.ptr, path);
    }
};

/// Abstract directory handle interface
pub const DirHandle = struct {
    ptr: *anyopaque,
    vtable: *const DirVTable,

    const DirVTable = struct {
        iterate: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator) anyerror!DirIterator,
        openDir: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator, sub_path: []const u8, options: std.fs.Dir.OpenDirOptions) anyerror!DirHandle,
        close: *const fn (ptr: *anyopaque) void,
        statFile: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator, path: []const u8) anyerror!std.fs.File.Stat,
        readFileAlloc: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator, path: []const u8, max_bytes: usize) anyerror![]u8,
        openFile: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator, path: []const u8, flags: std.fs.File.OpenFlags) anyerror!FileHandle,
    };

    pub fn iterate(self: DirHandle, allocator: std.mem.Allocator) !DirIterator {
        return self.vtable.iterate(self.ptr, allocator);
    }

    pub fn openDir(self: DirHandle, allocator: std.mem.Allocator, sub_path: []const u8, options: std.fs.Dir.OpenDirOptions) !DirHandle {
        return self.vtable.openDir(self.ptr, allocator, sub_path, options);
    }

    pub fn close(self: DirHandle) void {
        return self.vtable.close(self.ptr);
    }

    pub fn statFile(self: DirHandle, allocator: std.mem.Allocator, path: []const u8) !std.fs.File.Stat {
        return self.vtable.statFile(self.ptr, allocator, path);
    }

    pub fn readFileAlloc(self: DirHandle, allocator: std.mem.Allocator, path: []const u8, max_bytes: usize) ![]u8 {
        return self.vtable.readFileAlloc(self.ptr, allocator, path, max_bytes);
    }

    pub fn openFile(self: DirHandle, allocator: std.mem.Allocator, path: []const u8, flags: std.fs.File.OpenFlags) !FileHandle {
        return self.vtable.openFile(self.ptr, allocator, path, flags);
    }
};

/// Abstract file handle interface
pub const FileHandle = struct {
    ptr: *anyopaque,
    vtable: *const FileVTable,

    const FileVTable = struct {
        close: *const fn (ptr: *anyopaque) void,
        reader: *const fn (ptr: *anyopaque) std.io.AnyReader,
        readAll: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator, max_bytes: usize) anyerror![]u8,
    };

    pub fn close(self: FileHandle) void {
        return self.vtable.close(self.ptr);
    }

    pub fn reader(self: FileHandle) std.io.AnyReader {
        return self.vtable.reader(self.ptr);
    }

    pub fn readAll(self: FileHandle, allocator: std.mem.Allocator, max_bytes: usize) ![]u8 {
        return self.vtable.readAll(self.ptr, allocator, max_bytes);
    }
};

/// Abstract directory iterator interface
pub const DirIterator = struct {
    ptr: *anyopaque,
    vtable: *const IteratorVTable,

    const IteratorVTable = struct {
        next: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator) anyerror!?std.fs.Dir.Entry,
    };

    pub fn next(self: DirIterator, allocator: std.mem.Allocator) !?std.fs.Dir.Entry {
        return self.vtable.next(self.ptr, allocator);
    }
};
