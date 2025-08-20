const std = @import("std");
const collections = @import("../lib/core/collections.zig");
const errors = @import("../lib/core/errors.zig");
const filesystem = @import("../lib/filesystem/interface.zig");
const memory = @import("../lib/memory/pools.zig");

const config_mod = @import("config.zig");
const entry_mod = @import("entry.zig");
const filter_mod = @import("filter.zig");
const formatter_mod = @import("formatter.zig");
const path_builder_mod = @import("path_builder.zig");

const Config = config_mod.Config;
const Entry = entry_mod.Entry;
const Filter = filter_mod.Filter;
const Formatter = formatter_mod.Formatter;
const PathBuilder = path_builder_mod.PathBuilder;
const FilesystemInterface = filesystem.FilesystemInterface;
const PathCache = memory.PathCache;

pub const WalkerOptions = struct {
    filesystem: FilesystemInterface,
    quiet: bool = false,
    path_cache: ?*PathCache = null,
};

pub const Walker = struct {
    allocator: std.mem.Allocator,
    config: Config,
    filter: Filter,
    formatter: Formatter,
    path_builder: PathBuilder,
    filesystem: FilesystemInterface,
    path_cache: ?*PathCache,

    const Self = @This();

    pub fn initWithOptions(allocator: std.mem.Allocator, config: Config, options: WalkerOptions) Self {
        return Self{
            .allocator = allocator,
            .config = config,
            .filter = Filter.init(config.shared_config),
            .formatter = Formatter{ .quiet = options.quiet, .format = config.format },
            .path_builder = PathBuilder.initWithCache(allocator, options.filesystem, options.path_cache),
            .filesystem = options.filesystem,
            .path_cache = options.path_cache,
        };
    }

    pub fn walk(self: Self, path: []const u8) !void {
        // For list format, start with "." for current directory, otherwise use basename
        const initial_relative = if (self.config.format == .list and std.mem.eql(u8, path, "."))
            "."
        else
            self.path_builder.basename(path);

        try self.walkRecursive(path, "", initial_relative, true, 0);
    }

    fn walkRecursive(self: Self, path: []const u8, prefix: []const u8, relative_path: []const u8, is_last: bool, current_depth: u32) !void {
        const basename = self.path_builder.basename(path);
        const entry = Entry{
            .name = basename,
            .kind = .directory, // We'll assume directory for now, could be enhanced
        };

        self.formatter.formatEntry(entry, if (self.config.format == .list) relative_path else prefix, is_last);

        // Check if we've reached max depth
        if (self.config.max_depth) |depth| {
            if (current_depth >= depth) {
                return;
            }
        }

        const dir = self.filesystem.openDir(self.allocator, path, .{ .iterate = true }) catch |err| switch (err) {
            error.NotDir => return,
            error.InvalidUtf8 => return,
            error.BadPathName => return,
            error.FileNotFound => return,
            error.AccessDenied => {
                if (!self.formatter.quiet) {
                    std.debug.print("Warning: {s} - Open directory: {s}\n", .{ path, errors.getMessage(err) });
                }
                return;
            },
            error.SymLinkLoop => {
                if (!self.formatter.quiet) {
                    std.debug.print("Warning: {s} - Open directory: {s}\n", .{ path, errors.getMessage(err) });
                }
                return;
            },
            else => {
                if (!self.formatter.quiet) {
                    std.debug.print("Warning: {s} - Open directory: {s}\n", .{ path, errors.getMessage(err) });
                }
                return err;
            },
        };
        var iter_dir = dir;
        defer iter_dir.close();

        var entries = collections.List(std.fs.Dir.Entry).init(self.allocator);
        defer entries.deinit();

        var iterator = try iter_dir.iterate(self.allocator);
        while (try iterator.next(self.allocator)) |dir_entry| {
            try entries.append(dir_entry);
        }

        std.sort.insertion(std.fs.Dir.Entry, entries.items, {}, struct {
            fn lessThan(context: void, lhs: std.fs.Dir.Entry, rhs: std.fs.Dir.Entry) bool {
                _ = context;
                if (lhs.kind == .directory and rhs.kind != .directory) return true;
                if (lhs.kind != .directory and rhs.kind == .directory) return false;
                return std.mem.lessThan(u8, lhs.name, rhs.name);
            }
        }.lessThan);

        for (entries.items, 0..) |dir_entry, i| {
            const is_last_entry = i == entries.items.len - 1;

            const new_prefix = try self.path_builder.buildTreePrefix(prefix, is_last);
            defer self.allocator.free(new_prefix);

            // Skip entries with null bytes or invalid characters
            if (std.mem.indexOfScalar(u8, dir_entry.name, 0) != null) {
                continue;
            }

            // Skip completely hidden files (not displayed at all)
            if (self.filter.shouldHide(dir_entry.name)) {
                continue;
            }

            // Check both name-based and path-based ignore patterns
            const is_ignored_by_name = self.filter.shouldIgnore(dir_entry.name);
            const full_path = self.filesystem.pathJoin(self.allocator, &.{ path, dir_entry.name }) catch {
                continue;
            };
            defer self.allocator.free(full_path);

            const is_ignored_by_path = self.filter.shouldIgnoreAtPath(full_path);
            const is_ignored = is_ignored_by_name or is_ignored_by_path;

            const is_depth_limited = if (self.config.max_depth) |depth|
                (current_depth + 1 >= depth and dir_entry.kind == .directory)
            else
                false;

            const tree_entry = Entry{
                .name = dir_entry.name,
                .kind = dir_entry.kind,
                .is_ignored = is_ignored,
                .is_depth_limited = is_depth_limited,
            };

            // Compute relative path for this entry (used for list format)
            const relative_entry_path = try self.path_builder.buildPath(relative_path, dir_entry.name);
            defer self.allocator.free(relative_entry_path);

            // Handle ignored entries
            if (tree_entry.is_ignored or tree_entry.is_depth_limited) {
                if (dir_entry.kind == .directory) {
                    // Ignored directories show as [...]
                    self.formatter.formatEntry(tree_entry, if (self.config.format == .list) relative_entry_path else new_prefix, is_last_entry);
                }
                // Ignored files are completely skipped (like git behavior)
                continue; // Don't traverse into ignored directories (performance optimization)
            }

            // If it's a directory and not ignored, recurse into it
            if (dir_entry.kind == .directory) {
                try self.walkRecursive(full_path, new_prefix, relative_entry_path, is_last_entry, current_depth + 1);
            } else {
                // It's a file and not ignored, display it
                self.formatter.formatEntry(tree_entry, if (self.config.format == .list) relative_entry_path else new_prefix, is_last_entry);
            }
        }
    }
};
