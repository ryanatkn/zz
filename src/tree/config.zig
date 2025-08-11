const std = @import("std");
const Format = @import("format.zig").Format;
const SharedConfig = @import("../config.zig").SharedConfig;
const ZonLoader = @import("../config.zig").ZonLoader;

pub const ArgError = error{
    InvalidFlag,
    MissingValue,
    InvalidFormat,
    OutOfMemory,
    ParseError,
};

pub const Config = struct {
    max_depth: ?u32 = null,
    show_hidden: bool = false,
    format: Format = .tree,
    shared_config: SharedConfig,
    directory_path: []const u8 = ".",

    const Self = @This();

    pub fn fromArgs(allocator: std.mem.Allocator, args: [][:0]const u8) !Self {
        return fromArgsWithQuiet(allocator, args, false);
    }

    pub fn fromArgsQuiet(allocator: std.mem.Allocator, args: [][:0]const u8) !Self {
        return fromArgsWithQuiet(allocator, args, true);
    }

    fn fromArgsWithQuiet(allocator: std.mem.Allocator, args: [][:0]const u8, quiet: bool) !Self {
        const parsed_args = parseArgs(allocator, args) catch |err| {
            if (!quiet) {
                std.debug.print("Error: {s}\n", .{formatArgError(err)});
                printUsage("zz", "tree");
            }
            return err;
        };

        const config = Self{
            .shared_config = try loadSharedConfig(allocator, parsed_args.no_gitignore),
            .max_depth = parsed_args.max_depth,
            .show_hidden = parsed_args.show_hidden,
            .format = parsed_args.format,
            .directory_path = parsed_args.directory orelse ".",
        };

        return config;
    }

    const ParsedArgs = struct {
        directory: ?[]const u8 = null,
        max_depth: ?u32 = null,
        format: Format = .tree,
        show_hidden: bool = false,
        no_gitignore: bool = false,
    };

    fn parseArgs(allocator: std.mem.Allocator, args: [][:0]const u8) ArgError!ParsedArgs {
        _ = allocator; // May need later for string duplication
        var result = ParsedArgs{};

        var i: usize = 0; // Start from first argument

        // Skip until we find "tree" command
        while (i < args.len and !std.mem.eql(u8, args[i], "tree")) {
            i += 1;
        }
        i += 1; // Skip the "tree" command itself
        var positional_count: usize = 0;

        while (i < args.len) {
            const arg = args[i];

            if (std.mem.startsWith(u8, arg, "--format=")) {
                const format_str = arg["--format=".len..];
                result.format = Format.fromString(format_str) orelse return ArgError.InvalidFormat;
            } else if (std.mem.eql(u8, arg, "--show-hidden")) {
                result.show_hidden = true;
            } else if (std.mem.eql(u8, arg, "--no-gitignore")) {
                result.no_gitignore = true;
            } else if (std.mem.startsWith(u8, arg, "-")) {
                return ArgError.InvalidFlag;
            } else {
                // Positional argument
                if (positional_count == 0) {
                    result.directory = arg;
                } else if (positional_count == 1) {
                    // Try to parse as max_depth, but don't error if it fails
                    result.max_depth = std.fmt.parseInt(u32, arg, 10) catch null;
                }
                positional_count += 1;
            }

            i += 1;
        }

        return result;
    }

    fn printUsage(program_name: []const u8, command: []const u8) void {
        std.debug.print("Usage: {s} {s} [directory] [max_depth] [options]\n\n", .{ program_name, command });
        std.debug.print("Options:\n", .{});
        std.debug.print("  --format=FORMAT               Output format: tree (default) or list\n", .{});
        std.debug.print("  --show-hidden                 Show hidden files\n", .{});
        std.debug.print("  --no-gitignore                Disable .gitignore parsing (respects .gitignore by default)\n", .{});
        std.debug.print("\n", .{});
        std.debug.print("Examples:\n", .{});
        std.debug.print("  {s} {s}                       # Tree of current directory (respects .gitignore)\n", .{ program_name, command });
        std.debug.print("  {s} {s} src 2                 # Tree of src/ with max depth 2\n", .{ program_name, command });
        std.debug.print("  {s} {s} --format=list         # List format of current directory\n", .{ program_name, command });
        std.debug.print("  {s} {s} --no-gitignore        # Tree ignoring .gitignore files\n", .{ program_name, command });
    }

    fn formatArgError(err: ArgError) []const u8 {
        return switch (err) {
            ArgError.InvalidFlag => "Invalid flag",
            ArgError.MissingValue => "Missing value for flag",
            ArgError.InvalidFormat => "Invalid format. Use 'tree' or 'list'",
            ArgError.OutOfMemory => "Out of memory",
            ArgError.ParseError => "Failed to parse configuration",
        };
    }

    fn loadSharedConfig(allocator: std.mem.Allocator, no_gitignore: bool) !SharedConfig {
        var zon_loader = ZonLoader.init(allocator);
        defer zon_loader.deinit();

        var config = try zon_loader.getSharedConfig();

        // Override gitignore behavior if --no-gitignore flag is used
        if (no_gitignore) {
            config.respect_gitignore = false;
            // Clear any existing gitignore patterns to save memory
            if (config.patterns_allocated) {
                for (config.gitignore_patterns) |pattern| {
                    allocator.free(pattern);
                }
                allocator.free(config.gitignore_patterns);
            }
            config.gitignore_patterns = &[_][]const u8{};
        }

        return config;
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        self.shared_config.deinit(allocator);
    }
};
