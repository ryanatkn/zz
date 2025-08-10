const std = @import("std");

pub const TreeConfig = struct {
    ignored_patterns: []const []const u8, // Show as [...] and don't traverse
    hidden_files: []const []const u8, // Don't show at all
};

pub const Config = struct {
    max_depth: ?u32 = null,
    show_hidden: bool = false,
    tree_config: TreeConfig,

    const Self = @This();

    pub fn fromArgs(allocator: std.mem.Allocator, args: [][:0]const u8) !Self {
        var config = Self{
            .tree_config = try loadTreeConfig(allocator),
        };

        // args[0] is "tree", args[1] is directory, args[2] is optional max_depth
        if (args.len >= 3) {
            config.max_depth = std.fmt.parseInt(u32, args[2], 10) catch null;
        }

        return config;
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

        // For now, just return default config - full .zon parsing is complex
        // TODO: Implement actual .zon parsing if needed
        return getDefaultTreeConfig(allocator);
    }

    fn getDefaultTreeConfig(allocator: std.mem.Allocator) !TreeConfig {
        // Default patterns - these are allocated and need to be freed by caller
        const ignored = try allocator.dupe([]const u8, &[_][]const u8{
            ".git",                     ".svn", ".hg", "node_modules", "dist", "build",      "target",
            "__pycache__",              "venv", "env", "tmp",          "temp", ".zig-cache", "zig-out",
            "src/hex/shaders/compiled",
        });

        const hidden_files = try allocator.dupe([]const u8, &[_][]const u8{
            "Thumbs.db", ".DS_Store",
        });

        return TreeConfig{
            .ignored_patterns = ignored,
            .hidden_files = hidden_files,
        };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.tree_config.ignored_patterns);
        allocator.free(self.tree_config.hidden_files);
    }
};
