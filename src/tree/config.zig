const std = @import("std");
const FilesystemInterface = @import("../lib/core/filesystem.zig").FilesystemInterface;
const Format = @import("format.zig").Format;
const SharedConfig = @import("../config.zig").SharedConfig;
const ZonLoader = @import("../config.zig").ZonLoader;
const Args = @import("../lib/args.zig").Args;
const CommonFlags = @import("../lib/args.zig").CommonFlags;

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

    /// Create a minimal config for testing (no filesystem operations)
    pub fn forTesting(allocator: std.mem.Allocator) Self {
        _ = allocator; // May be needed for future functionality
        return Self{
            .max_depth = null,
            .show_hidden = false,
            .format = .tree,
            .shared_config = SharedConfig{
                .ignored_patterns = &[_][]const u8{}, // Empty patterns
                .hidden_files = &[_][]const u8{},
                .gitignore_patterns = &[_][]const u8{},
                .symlink_behavior = .skip,
                .respect_gitignore = false, // Don't use gitignore in tests
                .patterns_allocated = false, // Static arrays, no cleanup needed
            },
            .directory_path = ".",
        };
    }

    pub fn fromArgs(allocator: std.mem.Allocator, filesystem: FilesystemInterface, args: [][:0]const u8) !Self {
        return fromArgsWithQuiet(allocator, filesystem, args, false);
    }

    pub fn fromArgsQuiet(allocator: std.mem.Allocator, filesystem: FilesystemInterface, args: [][:0]const u8) !Self {
        return fromArgsWithQuiet(allocator, filesystem, args, true);
    }

    fn fromArgsWithQuiet(allocator: std.mem.Allocator, filesystem: FilesystemInterface, args: [][:0]const u8, quiet: bool) !Self {
        const parsed_args = parseArgs(allocator, args) catch |err| {
            if (!quiet) {
                std.debug.print("Error: {s}\n", .{formatArgError(err)});
                printUsage("zz", "tree");
            }
            return err;
        };

        const config = Self{
            .shared_config = try loadSharedConfig(allocator, filesystem, parsed_args.no_gitignore),
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

        const start_index = Args.skipToCommand(args, "tree");
        var positional_count: usize = 0;

        var i = start_index;
        while (i < args.len) {
            const arg = args[i];

            // Parse using centralized flag functions
            if (CommonFlags.parseFormatFlag(arg)) |format_str| {
                result.format = Format.fromString(format_str) orelse return ArgError.InvalidFormat;
            } else if (std.mem.eql(u8, arg, "-f")) {
                // Handle -f flag that expects next argument as format
                if (i + 1 >= args.len) return ArgError.MissingValue;
                i += 1;
                const format_str = args[i];
                result.format = Format.fromString(format_str) orelse return ArgError.InvalidFormat;
            } else if (CommonFlags.isShowHiddenFlag(arg)) {
                result.show_hidden = true;
            } else if (CommonFlags.isNoGitignoreFlag(arg)) {
                result.no_gitignore = true;
            } else if (Args.isHelpFlag(arg)) {
                printUsage("zz", "tree");
                std.process.exit(0);
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
        _ = program_name; // Use centralized usage function instead
        const stderr = std.io.getStdErr().writer();
        const options = [_][]const u8{
            "--format=FORMAT, -f FORMAT   Output format: tree (default) or list",
            "--show-hidden                 Show hidden files",
            "--no-gitignore                Disable .gitignore parsing",
            "--help, -h                    Show this help message",
        };

        Args.printUsage(stderr, command, "Show directory tree with configurable filtering", &options) catch {};
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

    fn loadSharedConfig(allocator: std.mem.Allocator, filesystem: FilesystemInterface, no_gitignore: bool) !SharedConfig {
        var zon_loader = ZonLoader.init(allocator, filesystem);
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
