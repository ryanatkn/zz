const std = @import("std");

// Re-export filesystem interfaces and implementations
const fs_interface = @import("interface.zig");
pub const FilesystemInterface = fs_interface.FilesystemInterface;
pub const DirHandle = fs_interface.DirHandle;
pub const FileHandle = fs_interface.FileHandle;
pub const DirIterator = fs_interface.DirIterator;

pub const RealFilesystem = @import("real.zig").RealFilesystem;
pub const MockFilesystem = @import("mock.zig").MockFilesystem;
