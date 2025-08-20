const std = @import("std");

// TODO: In future migration, move this to filesystem/mod.zig for consistency with other modules

// Re-export filesystem interfaces and implementations
const fs_interface = @import("lib/filesystem/interface.zig");
pub const FilesystemInterface = fs_interface.FilesystemInterface;
pub const DirHandle = fs_interface.DirHandle;
pub const FileHandle = fs_interface.FileHandle;
pub const DirIterator = fs_interface.DirIterator;

pub const RealFilesystem = @import("lib/filesystem/real.zig").RealFilesystem;
pub const MockFilesystem = @import("lib/filesystem/mock.zig").MockFilesystem;
