const std = @import("std");
const filesystem = @import("../lib/filesystem/interface.zig");
const memory = @import("../lib/memory/pools.zig");

const config_mod = @import("config.zig");
const entry_mod = @import("entry.zig");
const formatter_mod = @import("formatter.zig");
const filter_mod = @import("filter.zig");
const walker_mod = @import("walker.zig");

const FilesystemInterface = filesystem.FilesystemInterface;
const PathCache = memory.PathCache;

pub const Config = config_mod.Config;
pub const Entry = entry_mod.Entry;
pub const Formatter = formatter_mod.Formatter;
pub const Filter = filter_mod.Filter;
pub const Walker = walker_mod.Walker;
pub const WalkerOptions = walker_mod.WalkerOptions;

pub fn run(allocator: std.mem.Allocator, fs: FilesystemInterface, args: [][:0]const u8) !void {
    return runInternal(allocator, fs, args, false);
}

pub fn runQuiet(allocator: std.mem.Allocator, fs: FilesystemInterface, args: [][:0]const u8) !void {
    return runInternal(allocator, fs, args, true);
}

pub fn runWithConfig(config: *Config, allocator: std.mem.Allocator, fs: FilesystemInterface, args: [][:0]const u8) !void {
    return runWithConfigInternal(config, allocator, fs, args, false);
}

pub fn runWithConfigQuiet(config: *Config, allocator: std.mem.Allocator, fs: FilesystemInterface, args: [][:0]const u8) !void {
    return runWithConfigInternal(config, allocator, fs, args, true);
}

fn runInternal(allocator: std.mem.Allocator, fs: FilesystemInterface, args: [][:0]const u8, quiet: bool) !void {
    // Create config from args (skip the "tree" command itself)
    var tree_config = try Config.fromArgs(allocator, fs, args);
    defer tree_config.deinit(allocator);

    return runWithConfigInternal(&tree_config, allocator, fs, args, quiet);
}

fn runWithConfigInternal(config: *Config, allocator: std.mem.Allocator, fs: FilesystemInterface, args: [][:0]const u8, quiet: bool) !void {
    _ = args; // May be needed for future functionality

    // Directory path is now stored in config
    const dir_path = config.directory_path;

    // Create path cache for performance optimization
    var path_cache = try PathCache.init(allocator);
    defer path_cache.deinit();

    const walker_options = WalkerOptions{
        .filesystem = fs,
        .quiet = quiet,
        .path_cache = &path_cache,
    };
    const walker = Walker.initWithOptions(allocator, config.*, walker_options);

    try walker.walk(dir_path);
}
