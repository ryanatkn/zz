const std = @import("std");

// Re-export filesystem interfaces and implementations
pub const FilesystemInterface = @import("filesystem/interface.zig").FilesystemInterface;
pub const DirHandle = @import("filesystem/interface.zig").DirHandle;
pub const FileHandle = @import("filesystem/interface.zig").FileHandle;
pub const DirIterator = @import("filesystem/interface.zig").DirIterator;

pub const RealFilesystem = @import("filesystem/real.zig").RealFilesystem;
pub const MockFilesystem = @import("filesystem/mock.zig").MockFilesystem;