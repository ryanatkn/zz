const std = @import("std");
const Format = @import("format.zig").Format;

pub const ArgError = error{
    InvalidFlag,
    MissingValue,
    InvalidFormat,
    OutOfMemory,
    ParseError,
};

pub const TreeConfig = struct {
    ignored_patterns: []const []const u8, // Show as [...] and don't traverse
    hidden_files: []const []const u8, // Don't show at all
    // Track whether patterns were dynamically allocated and need to be freed
    patterns_allocated: bool = false,
};

pub const Config = struct {
    max_depth: ?u32 = null,
    show_hidden: bool = false,
    format: Format = .tree,
    tree_config: TreeConfig,
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
            .tree_config = try loadTreeConfig(allocator),
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
        std.debug.print("\n", .{});
        std.debug.print("Examples:\n", .{});
        std.debug.print("  {s} {s}                       # Tree of current directory\n", .{ program_name, command });
        std.debug.print("  {s} {s} src 2                 # Tree of src/ with max depth 2\n", .{ program_name, command });
        std.debug.print("  {s} {s} --format=list         # List format of current directory\n", .{ program_name, command });
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

    fn loadTreeConfig(allocator: std.mem.Allocator) !TreeConfig {
        // Try to read zz.zon configuration file
        const config_path = "zz.zon";
        const file_content = std.fs.cwd().readFileAlloc(allocator, config_path, 1024 * 1024) catch |err| switch (err) {
            error.FileNotFound => {
                // Return default configuration if file doesn't exist
                return getDefaultTreeConfig(allocator);
            },
            else => return err,
        };
        defer allocator.free(file_content);

        // Parse the .zon file for tree configuration
        return parseZonTreeConfig(allocator, file_content) catch {
            // Fall back to defaults if parsing fails
            return getDefaultTreeConfig(allocator);
        };
    }

    fn getDefaultTreeConfig(allocator: std.mem.Allocator) !TreeConfig {
        // Default patterns - these are allocated and need to be freed by caller
        const ignored = try allocator.dupe([]const u8, &[_][]const u8{
            ".git",        ".svn", ".hg", "node_modules", "dist", "build",      "target",
            "__pycache__", "venv", "env", "tmp",          "temp", ".zig-cache", "zig-out",
        });

        const hidden_files = try allocator.dupe([]const u8, &[_][]const u8{
            "Thumbs.db", ".DS_Store",
        });

        return TreeConfig{
            .ignored_patterns = ignored,
            .hidden_files = hidden_files,
            .patterns_allocated = false, // String literals, don't free
        };
    }

    fn parseZonTreeConfig(allocator: std.mem.Allocator, content: []const u8) !TreeConfig {
        // Add null terminator for ZON parsing
        const null_terminated = try allocator.dupeZ(u8, content);
        defer allocator.free(null_terminated);

        // Define the expected structure - make fields optional since zz.zon might have other sections
        const ZonConfig = struct {
            tree: ?struct {
                ignored_patterns: ?[]const []const u8 = null,
                hidden_files: ?[]const []const u8 = null,
            } = null,
            // Allow other sections to exist without parsing them
            prompt: ?struct {
                ignored_patterns: ?[]const []const u8 = null,
            } = null,
        };

        // Parse the ZON content
        const parsed = std.zon.parse.fromSlice(ZonConfig, allocator, null_terminated, null, .{}) catch {
            return error.ParseError;
        };
        defer std.zon.parse.free(allocator, parsed);

        // Check if tree section exists
        const tree_config = parsed.tree orelse return error.ParseError;

        // Copy the patterns to owned memory
        const source_ignored = tree_config.ignored_patterns orelse &[_][]const u8{};
        const ignored_patterns = try allocator.alloc([]const u8, source_ignored.len);
        for (source_ignored, 0..) |pattern, i| {
            ignored_patterns[i] = try allocator.dupe(u8, pattern);
        }

        const source_hidden = tree_config.hidden_files orelse &[_][]const u8{};
        const hidden_files = try allocator.alloc([]const u8, source_hidden.len);
        for (source_hidden, 0..) |file, i| {
            hidden_files[i] = try allocator.dupe(u8, file);
        }

        return TreeConfig{
            .ignored_patterns = ignored_patterns,
            .hidden_files = hidden_files,
            .patterns_allocated = true, // Dynamically allocated, need to free
        };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        // Only free if patterns were dynamically allocated
        if (self.tree_config.patterns_allocated) {
            // Free individual pattern strings
            for (self.tree_config.ignored_patterns) |pattern| {
                allocator.free(pattern);
            }
            for (self.tree_config.hidden_files) |file| {
                allocator.free(file);
            }
        }
        // Always free the slices themselves
        allocator.free(self.tree_config.ignored_patterns);
        allocator.free(self.tree_config.hidden_files);
    }
};
