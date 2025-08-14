const std = @import("std");

// Re-export filesystem interfaces and implementations
pub const FilesystemInterface = @import("lib/filesystem/interface.zig").FilesystemInterface;
pub const DirHandle = @import("lib/filesystem/interface.zig").DirHandle;
pub const FileHandle = @import("lib/filesystem/interface.zig").FileHandle;
pub const DirIterator = @import("lib/filesystem/interface.zig").DirIterator;

pub const RealFilesystem = @import("lib/filesystem/real.zig").RealFilesystem;
pub const MockFilesystem = @import("lib/filesystem/mock.zig").MockFilesystem;
