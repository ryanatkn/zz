const std = @import("std");

const Command = enum {
    tree,
    help,

    const Self = @This();

    pub fn fromString(cmd: []const u8) ?Self {
        if (std.mem.eql(u8, cmd, "tree")) return .tree;
        if (std.mem.eql(u8, cmd, "help")) return .help;
        return null;
    }
};

fn showHelp(program_name: []const u8) void {
    std.debug.print("zz - CLI utility toolkit\n\n", .{});
    std.debug.print("Usage: {s} <command> [args...]\n\n", .{program_name});
    std.debug.print("Commands:\n", .{});
    std.debug.print("  tree [directory] [max_depth]  Show directory tree (defaults to current dir)\n", .{});
    std.debug.print("  help                          Show this help\n", .{});
}

const TreeConfig = struct {
    max_depth: ?u32 = null,
    show_hidden: bool = false,

    const Self = @This();

    pub fn fromArgs(allocator: std.mem.Allocator, args: [][:0]u8) !Self {
        _ = allocator;
        var config = Self{};

        // args[0] is "tree", args[1] is directory, args[2] is optional max_depth
        if (args.len >= 3) {
            config.max_depth = std.fmt.parseInt(u32, args[2], 10) catch null;
        }

        return config;
    }
};

const TreeEntry = struct {
    name: []const u8,
    kind: std.fs.File.Kind,
    is_ignored: bool = false,
    is_depth_limited: bool = false,
};

const TreeFormatter = struct {
    const Self = @This();

    pub fn formatEntry(self: Self, entry: TreeEntry, prefix: []const u8, is_last: bool) void {
        _ = self;
        const connector = if (is_last) "└── " else "├── ";

        if (entry.is_ignored or entry.is_depth_limited) {
            std.debug.print("{s}{s}{s} \x1b[90m[...]\x1b[0m\n", .{ prefix, connector, entry.name });
        } else {
            std.debug.print("{s}{s}{s}\n", .{ prefix, connector, entry.name });
        }
    }
};

const DirectoryFilter = struct {
    const Self = @This();

    pub fn shouldIgnore(self: Self, name: []const u8) bool {
        _ = self;
        const ignored_dirs = [_][]const u8{
            "node_modules",
            "dist",
            "build",
            "target",
            "__pycache__",
            "venv",
            "env",
            "Thumbs.db",
            "tmp",
            "temp",
        };

        // Ignore all dot-prefixed directories and files
        if (name.len > 0 and name[0] == '.') {
            return true;
        }

        for (ignored_dirs) |ignored| {
            if (std.mem.eql(u8, name, ignored)) {
                return true;
            }
        }
        return false;
    }
};

fn shouldIgnore(name: []const u8) bool {
    const filter = DirectoryFilter{};
    return filter.shouldIgnore(name);
}

const TreeWalker = struct {
    allocator: std.mem.Allocator,
    config: TreeConfig,
    filter: DirectoryFilter,
    formatter: TreeFormatter,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: TreeConfig) Self {
        return Self{
            .allocator = allocator,
            .config = config,
            .filter = DirectoryFilter{},
            .formatter = TreeFormatter{},
        };
    }

    pub fn walk(self: Self, path: []const u8) !void {
        try self.walkRecursive(path, "", true, 0);
    }

    fn walkRecursive(self: Self, path: []const u8, prefix: []const u8, is_last: bool, current_depth: u32) !void {
        const basename = std.fs.path.basename(path);
        const entry = TreeEntry{
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

            const tree_entry = TreeEntry{
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

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        showHelp(args[0]);
        std.process.exit(1);
    }

    const command = Command.fromString(args[1]) orelse {
        std.debug.print("Unknown command: {s}\n\n", .{args[1]});
        showHelp(args[0]);
        std.process.exit(1);
    };

    switch (command) {
        .help => {
            showHelp(args[0]);
        },
        .tree => {
            // Default to current directory if no path provided
            const dir_path = if (args.len >= 3) args[2] else ".";

            // Shift args for tree command (remove program name and "tree" command)
            const tree_args = args[1..];
            const config = try TreeConfig.fromArgs(allocator, tree_args);
            const walker = TreeWalker.init(allocator, config);

            try walker.walk(dir_path);
        },
    }
}
