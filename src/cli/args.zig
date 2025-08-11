const std = @import("std");
const Format = @import("../tree/format.zig").Format;

pub const ArgError = error{
    InvalidFlag,
    MissingValue,
    InvalidFormat,
    OutOfMemory,
};

pub const ParsedArgs = struct {
    directory: ?[]const u8 = null,
    max_depth: ?u32 = null,
    format: Format = .tree,
    show_hidden: bool = false,

    pub fn deinit(self: *ParsedArgs) void {
        _ = self;
        // No cleanup needed for string slices as they reference original args
    }
};

pub const ArgParser = struct {
    const Self = @This();

    pub fn parse(allocator: std.mem.Allocator, args: [][:0]const u8) ArgError!ParsedArgs {
        _ = allocator; // May need later for string duplication
        var result = ParsedArgs{};
        
        var i: usize = 1; // Skip command name (args[0] is "tree")
        var positional_count: usize = 0;
        
        while (i < args.len) {
            const arg = args[i];
            
            if (std.mem.startsWith(u8, arg, "--format=")) {
                const format_str = arg["--format=".len..];
                result.format = Format.fromString(format_str) orelse return ArgError.InvalidFormat;
            } else if (std.mem.eql(u8, arg, "-f") and i + 1 < args.len) {
                i += 1;
                const format_str = args[i];
                result.format = Format.fromString(format_str) orelse return ArgError.InvalidFormat;
            } else if (std.mem.eql(u8, arg, "--show-hidden")) {
                result.show_hidden = true;
            } else if (std.mem.startsWith(u8, arg, "-")) {
                return ArgError.InvalidFlag;
            } else {
                // Positional argument
                if (positional_count == 0) {
                    result.directory = arg;
                } else if (positional_count == 1) {
                    result.max_depth = std.fmt.parseInt(u32, arg, 10) catch return ArgError.InvalidFormat;
                }
                positional_count += 1;
            }
            
            i += 1;
        }
        
        return result;
    }

    pub fn printUsage(program_name: []const u8, command: []const u8) void {
        std.debug.print("Usage: {s} {s} [directory] [max_depth] [options]\n\n", .{ program_name, command });
        std.debug.print("Options:\n", .{});
        std.debug.print("  --format=FORMAT, -f FORMAT    Output format: tree (default) or list\n", .{});
        std.debug.print("  --show-hidden                  Show hidden files\n", .{});
        std.debug.print("\n", .{});
        std.debug.print("Examples:\n", .{});
        std.debug.print("  {s} {s}                       # Tree of current directory\n", .{ program_name, command });
        std.debug.print("  {s} {s} src 2                 # Tree of src/ with max depth 2\n", .{ program_name, command });
        std.debug.print("  {s} {s} --format=list         # List format of current directory\n", .{ program_name, command });
        std.debug.print("  {s} {s} src -f list           # List format of src/\n", .{ program_name, command });
    }

    pub fn formatError(err: ArgError) []const u8 {
        return switch (err) {
            ArgError.InvalidFlag => "Invalid flag",
            ArgError.MissingValue => "Missing value for flag",
            ArgError.InvalidFormat => "Invalid format. Use 'tree' or 'list'",
            ArgError.OutOfMemory => "Out of memory",
        };
    }
};