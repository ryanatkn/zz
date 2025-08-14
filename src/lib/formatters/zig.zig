const std = @import("std");
const FormatterOptions = @import("../formatter.zig").FormatterOptions;

pub fn format(allocator: std.mem.Allocator, source: []const u8, options: FormatterOptions) ![]const u8 {
    _ = options;
    
    // Create a temp file for zig fmt
    var tmp_dir = std.testing.tmpDir(.{});
    var dir = try tmp_dir.dir.makeOpenPath("zig_fmt_tmp", .{});
    defer dir.close();
    defer tmp_dir.cleanup();
    
    // Write source to temp file
    const tmp_file = try dir.createFile("temp.zig", .{});
    defer tmp_file.close();
    try tmp_file.writeAll(source);
    
    // Get the absolute path
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try dir.realpath("temp.zig", &path_buf);
    
    // Run zig fmt on the file
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "zig", "fmt", tmp_path },
    }) catch {
        // If zig fmt is not available, return source as-is
        return allocator.dupe(u8, source);
    };

    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term.Exited != 0) {
        // If formatting failed, return original source
        return allocator.dupe(u8, source);
    }

    // Read the formatted file
    const formatted_file = try dir.openFile("temp.zig", .{});
    defer formatted_file.close();
    
    const formatted = try formatted_file.readToEndAlloc(allocator, std.math.maxInt(usize));
    return formatted;
}