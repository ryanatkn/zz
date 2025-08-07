const std = @import("std");
const Config = @import("config.zig").Config;
const Entry = @import("entry.zig").Entry;
const Filter = @import("filter.zig").Filter;
const Formatter = @import("formatter.zig").Formatter;

pub const Walker = struct {
    allocator: std.mem.Allocator,
    config: Config,
    filter: Filter,
    formatter: Formatter,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: Config) Self {
        return Self{
            .allocator = allocator,
            .config = config,
            .filter = Filter{},
            .formatter = Formatter{},
        };
    }

    pub fn walk(self: Self, path: []const u8) !void {
        try self.walkRecursive(path, "", true, 0);
    }

    fn walkRecursive(self: Self, path: []const u8, prefix: []const u8, is_last: bool, current_depth: u32) !void {
        const basename = std.fs.path.basename(path);
        const entry = Entry{
            .name = basename,
            .kind = .directory, // We'll assume directory for now, could be enhanced
        };

        self.formatter.formatEntry(entry, prefix, is_last);

        // Check if we've reached max depth
        if (self.config.max_depth) |depth| {
            if (current_depth >= depth) {
                return;
            }
        }

        const dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch |err| switch (err) {
            error.NotDir => return,
            error.InvalidUtf8 => return,
            error.BadPathName => return,
            error.FileNotFound => return,
            error.AccessDenied => return,
            error.SymLinkLoop => return,
            else => return err,
        };
        var iter_dir = dir;
        defer iter_dir.close();

        var entries = std.ArrayList(std.fs.Dir.Entry).init(self.allocator);
        defer entries.deinit();

        var iterator = iter_dir.iterate();
        while (try iterator.next()) |dir_entry| {
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
            const new_prefix_char = if (is_last) "    " else "│   ";

            const new_prefix = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ prefix, new_prefix_char });
            defer self.allocator.free(new_prefix);

            // Skip entries with null bytes or invalid characters
            if (std.mem.indexOfScalar(u8, dir_entry.name, 0) != null) {
                continue;
            }

            const tree_entry = Entry{
                .name = dir_entry.name,
                .kind = dir_entry.kind,
                .is_ignored = self.filter.shouldIgnore(dir_entry.name),
                .is_depth_limited = if (self.config.max_depth) |depth|
                    (current_depth + 1 >= depth and dir_entry.kind == .directory)
                else
                    false,
            };

            // Check if this entry should be ignored or depth limited
            if (tree_entry.is_ignored or tree_entry.is_depth_limited) {
                self.formatter.formatEntry(tree_entry, new_prefix, is_last_entry);
                continue;
            }

            const full_path = std.fs.path.join(self.allocator, &.{ path, dir_entry.name }) catch {
                continue;
            };
            defer self.allocator.free(full_path);

            try self.walkRecursive(full_path, new_prefix, is_last_entry, current_depth + 1);
        }
    }
};
