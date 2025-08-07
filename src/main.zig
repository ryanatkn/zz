const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: {s} <directory>\n", .{args[0]});
        std.process.exit(1);
    }

    const dir_path = args[1];
    try printDirTree(allocator, dir_path, "", true);
}

fn printDirTree(allocator: std.mem.Allocator, path: []const u8, prefix: []const u8, is_last: bool) !void {
    const connector = if (is_last) "└── " else "├── ";

    const basename = std.fs.path.basename(path);
    std.debug.print("{s}{s}{s}\n", .{ prefix, connector, basename });

    const dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch |err| switch (err) {
        error.NotDir => return,
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

        const full_path = try std.fs.path.join(allocator, &.{ path, entry.name });
        defer allocator.free(full_path);

        try printDirTree(allocator, full_path, new_prefix, is_last_entry);
    }
}
