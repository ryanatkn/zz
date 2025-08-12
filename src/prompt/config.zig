const std = @import("std");
const SharedConfig = @import("../config.zig").SharedConfig;
const ZonLoader = @import("../config.zig").ZonLoader;
const shouldIgnorePath = @import("../config.zig").shouldIgnorePath;

pub const Config = struct {
    allocator: std.mem.Allocator,
    shared_config: SharedConfig,
    prepend_text: ?[]const u8,
    append_text: ?[]const u8,
    allow_empty_glob: bool,
    allow_missing: bool,

    const Self = @This();

    const PREPEND_PREFIX = "--prepend=";
    const APPEND_PREFIX = "--append=";
    const SKIP_ARGS = 2; // Skip "zz prompt"

    /// Create a minimal config for testing (no filesystem operations)
    pub fn forTesting(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .shared_config = SharedConfig{
                .ignored_patterns = &[_][]const u8{}, // Empty patterns
                .hidden_files = &[_][]const u8{},
                .gitignore_patterns = &[_][]const u8{},
                .symlink_behavior = .skip,
                .respect_gitignore = false, // Don't use gitignore in tests
                .patterns_allocated = false, // Static arrays, no cleanup needed
            },
            .prepend_text = null,
            .append_text = null,
            .allow_empty_glob = false,
            .allow_missing = false,
        };
    }

    fn setTextOption(allocator: std.mem.Allocator, current_value: ?[]const u8, new_text: []const u8) !?[]const u8 {
        if (current_value) |old| {
            allocator.free(old);
        }
        return try allocator.dupe(u8, new_text);
    }

    fn parseFlag(config: *Self, allocator: std.mem.Allocator, arg: []const u8) !void {
        if (std.mem.startsWith(u8, arg, PREPEND_PREFIX)) {
            const text = arg[PREPEND_PREFIX.len..];
            config.prepend_text = try setTextOption(allocator, config.prepend_text, text);
        } else if (std.mem.startsWith(u8, arg, APPEND_PREFIX)) {
            const text = arg[APPEND_PREFIX.len..];
            config.append_text = try setTextOption(allocator, config.append_text, text);
        } else if (std.mem.eql(u8, arg, "--allow-empty-glob")) {
            config.allow_empty_glob = true;
        } else if (std.mem.eql(u8, arg, "--allow-missing")) {
            config.allow_missing = true;
        } else if (std.mem.eql(u8, arg, "--no-gitignore")) {
            // Handle gitignore override
            config.shared_config.respect_gitignore = false;
            // Clear existing gitignore patterns to save memory
            if (config.shared_config.patterns_allocated) {
                for (config.shared_config.gitignore_patterns) |pattern| {
                    allocator.free(pattern);
                }
                allocator.free(config.shared_config.gitignore_patterns);
            }
            config.shared_config.gitignore_patterns = &[_][]const u8{};
        }
    }

    pub fn fromArgs(allocator: std.mem.Allocator, args: [][:0]const u8) !Self {
        // Load shared config from ZON
        var zon_loader = ZonLoader.init(allocator);
        defer zon_loader.deinit();
        const shared_config = try zon_loader.getSharedConfig();

        var config = Self{
            .allocator = allocator,
            .shared_config = shared_config,
            .prepend_text = null,
            .append_text = null,
            .allow_empty_glob = false,
            .allow_missing = false,
        };

        // Parse flags
        for (args) |arg| {
            try parseFlag(&config, allocator, arg);
        }

        return config;
    }

    pub fn deinit(self: *Self) void {
        self.shared_config.deinit(self.allocator);
        if (self.prepend_text) |text| {
            self.allocator.free(text);
        }
        if (self.append_text) |text| {
            self.allocator.free(text);
        }
    }

    fn hasGlobChars(pattern: []const u8) bool {
        return std.mem.indexOf(u8, pattern, "*") != null or
            std.mem.indexOf(u8, pattern, "?") != null;
    }

    pub fn shouldIgnore(self: Self, path: []const u8) bool {
        // Use shared DRY helper function
        return shouldIgnorePath(self.shared_config, path);
    }

    pub fn getFilePatterns(self: Self, args: [][:0]const u8) !std.ArrayList([]const u8) {
        var patterns = std.ArrayList([]const u8).init(self.allocator);

        // Skip program name, command name, and flag args
        var i: usize = SKIP_ARGS;
        while (i < args.len) : (i += 1) {
            const arg = args[i];

            // Skip all flags
            if (std.mem.startsWith(u8, arg, "--")) {
                continue;
            }

            try patterns.append(arg);
        }

        // If no patterns provided and no text flags, this is an error
        if (patterns.items.len == 0) {
            if (self.prepend_text == null and self.append_text == null) {
                return error.NoInputFiles;
            }
            // If we have text flags but no files, that's valid
        }

        return patterns;
    }
};

test "config parsing" {
    const allocator = std.testing.allocator;

    // Test with --prepend flag
    var args1 = [_][:0]const u8{ "zz", "prompt", "--prepend=Instructions here", "file.zig" };
    var config1 = try Config.fromArgs(allocator, &args1);
    defer config1.deinit();

    try std.testing.expect(config1.prepend_text != null);
    try std.testing.expectEqualStrings("Instructions here", config1.prepend_text.?);

    var patterns1 = try config1.getFilePatterns(&args1);
    defer patterns1.deinit();
    try std.testing.expect(patterns1.items.len == 1);
    try std.testing.expectEqualStrings("file.zig", patterns1.items[0]);

    // Test with --append flag
    var args2 = [_][:0]const u8{ "zz", "prompt", "--append=Follow-up text", "file.zig" };
    var config2 = try Config.fromArgs(allocator, &args2);
    defer config2.deinit();

    try std.testing.expect(config2.append_text != null);
    try std.testing.expectEqualStrings("Follow-up text", config2.append_text.?);

    // Test without text flags
    var args3 = [_][:0]const u8{ "zz", "prompt", "file1.zig", "file2.zig" };
    var config3 = try Config.fromArgs(allocator, &args3);
    defer config3.deinit();

    try std.testing.expect(config3.prepend_text == null);
    try std.testing.expect(config3.append_text == null);

    var patterns3 = try config3.getFilePatterns(&args3);
    defer patterns3.deinit();
    try std.testing.expect(patterns3.items.len == 2);
    try std.testing.expectEqualStrings("file1.zig", patterns3.items[0]);
    try std.testing.expectEqualStrings("file2.zig", patterns3.items[1]);

    // Test error when no files provided and no text flags
    var args4 = [_][:0]const u8{ "zz", "prompt" };
    var config4 = try Config.fromArgs(allocator, &args4);
    defer config4.deinit();

    const result = config4.getFilePatterns(&args4);
    try std.testing.expectError(error.NoInputFiles, result);
}

test "ignore patterns" {
    const allocator = std.testing.allocator;

    var args = [_][:0]const u8{ "zz", "prompt" };
    var config = try Config.fromArgs(allocator, &args);
    defer config.deinit();

    // Test default ignore patterns
    try std.testing.expect(config.shouldIgnore(".git/config"));
    try std.testing.expect(config.shouldIgnore("path/to/.zig-cache/file"));
    try std.testing.expect(config.shouldIgnore("zig-out/bin/test"));
    try std.testing.expect(config.shouldIgnore("node_modules/package/index.js"));

    // Test non-ignored paths
    try std.testing.expect(!config.shouldIgnore("README.md"));
    try std.testing.expect(!config.shouldIgnore("docs/example.md"));
    try std.testing.expect(!config.shouldIgnore("build.zig"));
}

test "config flag parsing" {
    const allocator = std.testing.allocator;

    // Test allow-empty-glob flag
    var args1 = [_][:0]const u8{ "zz", "prompt", "--allow-empty-glob", "file.zig" };
    var config1 = try Config.fromArgs(allocator, &args1);
    defer config1.deinit();

    try std.testing.expect(config1.allow_empty_glob == true);
    try std.testing.expect(config1.allow_missing == false);
    try std.testing.expect(config1.prepend_text == null);
    try std.testing.expect(config1.append_text == null);

    // Test allow-missing flag
    var args2 = [_][:0]const u8{ "zz", "prompt", "--allow-missing", "file.zig" };
    var config2 = try Config.fromArgs(allocator, &args2);
    defer config2.deinit();

    try std.testing.expect(config2.allow_empty_glob == false);
    try std.testing.expect(config2.allow_missing == true);

    // Test both flags
    var args3 = [_][:0]const u8{ "zz", "prompt", "--allow-empty-glob", "--allow-missing", "file.zig" };
    var config3 = try Config.fromArgs(allocator, &args3);
    defer config3.deinit();

    try std.testing.expect(config3.allow_empty_glob == true);
    try std.testing.expect(config3.allow_missing == true);

    // Test default (no flags)
    var args4 = [_][:0]const u8{ "zz", "prompt", "file.zig" };
    var config4 = try Config.fromArgs(allocator, &args4);
    defer config4.deinit();

    try std.testing.expect(config4.allow_empty_glob == false);
    try std.testing.expect(config4.allow_missing == false);
}
