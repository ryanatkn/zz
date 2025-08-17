const std = @import("std");
const FilesystemInterface = @import("../lib/filesystem/interface.zig").FilesystemInterface;
const PathCache = @import("../lib/memory/pools.zig").PathCache;

pub const Config = @import("config.zig").Config;
pub const Entry = @import("entry.zig").Entry;
pub const Formatter = @import("formatter.zig").Formatter;
pub const Filter = @import("filter.zig").Filter;
pub const Walker = @import("walker.zig").Walker;
pub const WalkerOptions = @import("walker.zig").WalkerOptions;

pub fn run(allocator: std.mem.Allocator, filesystem: FilesystemInterface, args: [][:0]const u8) !void {
    return runInternal(allocator, filesystem, args, false);
}

pub fn runQuiet(allocator: std.mem.Allocator, filesystem: FilesystemInterface, args: [][:0]const u8) !void {
    return runInternal(allocator, filesystem, args, true);
}

pub fn runWithConfig(config: *Config, allocator: std.mem.Allocator, filesystem: FilesystemInterface, args: [][:0]const u8) !void {
    return runWithConfigInternal(config, allocator, filesystem, args, false);
}

pub fn runWithConfigQuiet(config: *Config, allocator: std.mem.Allocator, filesystem: FilesystemInterface, args: [][:0]const u8) !void {
    return runWithConfigInternal(config, allocator, filesystem, args, true);
}

fn runInternal(allocator: std.mem.Allocator, filesystem: FilesystemInterface, args: [][:0]const u8, quiet: bool) !void {
    // Create config from args (skip the "tree" command itself)
    var config = try Config.fromArgs(allocator, filesystem, args);
    defer config.deinit(allocator);

    return runWithConfigInternal(&config, allocator, filesystem, args, quiet);
}

fn runWithConfigInternal(config: *Config, allocator: std.mem.Allocator, filesystem: FilesystemInterface, args: [][:0]const u8, quiet: bool) !void {
    _ = args; // May be needed for future functionality

    // Directory path is now stored in config
    const dir_path = config.directory_path;

    // Create path cache for performance optimization
    var path_cache = try PathCache.init(allocator);
    defer path_cache.deinit();

    const walker_options = WalkerOptions{
        .filesystem = filesystem,
        .quiet = quiet,
        .path_cache = &path_cache,
    };
    const walker = Walker.initWithOptions(allocator, config.*, walker_options);

    try walker.walk(dir_path);
}
