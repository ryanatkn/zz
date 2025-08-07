const std = @import("std");

fn shouldIgnore(name: []const u8) bool {
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

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: {s} <directory> [max_depth]\n", .{args[0]});
        std.process.exit(1);
    }

    const dir_path = args[1];
    const max_depth: ?u32 = if (args.len >= 3) blk: {
        break :blk std.fmt.parseInt(u32, args[2], 10) catch null;
    } else null;

    try printDirTree(allocator, dir_path, "", true, 0, max_depth);
}

fn printDirTree(allocator: std.mem.Allocator, path: []const u8, prefix: []const u8, is_last: bool, current_depth: u32, max_depth: ?u32) !void {
    const connector = if (is_last) "└── " else "├── ";

    const basename = std.fs.path.basename(path);
    std.debug.print("{s}{s}{s}\n", .{ prefix, connector, basename });

    // Check if we've reached max depth
    if (max_depth) |depth| {
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

    var entries = std.ArrayList(std.fs.Dir.Entry).init(allocator);
    defer entries.deinit();

    var iterator = iter_dir.iterate();
    while (try iterator.next()) |entry| {
        try entries.append(entry);
    }

    std.sort.insertion(std.fs.Dir.Entry, entries.items, {}, struct {
        fn lessThan(context: void, lhs: std.fs.Dir.Entry, rhs: std.fs.Dir.Entry) bool {
            _ = context;
            if (lhs.kind == .directory and rhs.kind != .directory) return true;
            if (lhs.kind != .directory and rhs.kind == .directory) return false;
            return std.mem.lessThan(u8, lhs.name, rhs.name);
        }
    }.lessThan);

    for (entries.items, 0..) |entry, i| {
        const is_last_entry = i == entries.items.len - 1;
        const new_prefix_char = if (is_last) "    " else "│   ";

        const new_prefix = try std.fmt.allocPrint(allocator, "{s}{s}", .{ prefix, new_prefix_char });
        defer allocator.free(new_prefix);

        // Skip entries with null bytes or invalid characters
        if (std.mem.indexOfScalar(u8, entry.name, 0) != null) {
            continue;
        }

        // Check if this entry should be ignored
        if (shouldIgnore(entry.name)) {
            // Print the ignored entry but don't crawl it
            const ignore_connector = if (is_last_entry) "└── " else "├── ";
            std.debug.print("{s}{s}{s} \x1b[90m[...]\x1b[0m\n", .{ new_prefix, ignore_connector, entry.name });
            continue;
        }

        const full_path = std.fs.path.join(allocator, &.{ path, entry.name }) catch {
            // If path joining fails, skip this entry
            continue;
        };
        defer allocator.free(full_path);

        // Check if we need to show depth elision
        if (max_depth) |depth| {
            if (current_depth + 1 >= depth and entry.kind == .directory) {
                const ignore_connector = if (is_last_entry) "└── " else "├── ";
                std.debug.print("{s}{s}{s} \x1b[90m[...]\x1b[0m\n", .{ new_prefix, ignore_connector, entry.name });
                continue;
            }
        }

        try printDirTree(allocator, full_path, new_prefix, is_last_entry, current_depth + 1, max_depth);
    }
}
