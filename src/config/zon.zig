const std = @import("std");
const SharedConfig = @import("shared.zig").SharedConfig;
const BasePatterns = @import("shared.zig").BasePatterns;
const SymlinkBehavior = @import("shared.zig").SymlinkBehavior;
const PatternResolver = @import("resolver.zig").PatternResolver;
const GitignorePatterns = @import("../patterns/gitignore.zig").GitignorePatterns;
const FilesystemInterface = @import("../filesystem.zig").FilesystemInterface;
const DirHandle = @import("../filesystem.zig").DirHandle;

pub const ZonConfig = struct {
    base_patterns: ?[]const u8 = null, // Changed from BasePatterns to string for ZON compatibility
    ignored_patterns: ?[]const []const u8 = null,
    hidden_files: ?[]const []const u8 = null,
    symlink_behavior: ?[]const u8 = null, // Changed from enum to string for ZON compatibility
    respect_gitignore: ?bool = null,
    tree: ?TreeSection = null,
    prompt: ?PromptSection = null,

    const TreeSection = struct {
        // Tree-specific overrides if needed in future
    };

    const PromptSection = struct {
        // Prompt-specific overrides if needed in future
    };
};

pub const ZonLoader = struct {
    allocator: std.mem.Allocator,
    config: ?ZonConfig,
    filesystem: FilesystemInterface,

    const Self = @This();
    const DEFAULT_CONFIG_FILENAME = "zz.zon";

    pub fn init(allocator: std.mem.Allocator, filesystem: FilesystemInterface) Self {
        return Self{
            .allocator = allocator,
            .config = null,
            .filesystem = filesystem,
        };
    }

    pub fn loadFromFile(self: *Self, config_path: []const u8) !void {
        if (self.config != null) return; // Already loaded

        const cwd = self.filesystem.cwd();
        defer cwd.close();
        
        const file_content = cwd.readFileAlloc(self.allocator, config_path, 1024 * 1024) catch |err| switch (err) {
            error.FileNotFound => {
                self.config = ZonConfig{}; // Empty config
                return;
            },
            else => return err,
        };
        defer self.allocator.free(file_content);

        try self.loadFromContent(file_content);
    }

    pub fn loadFromDir(self: *Self, dir: std.fs.Dir, config_filename: []const u8) !void {
        if (self.config != null) return; // Already loaded

        const file_content = dir.readFileAlloc(self.allocator, config_filename, 1024 * 1024) catch |err| switch (err) {
            error.FileNotFound => {
                self.config = ZonConfig{}; // Empty config
                return;
            },
            else => return err,
        };
        defer self.allocator.free(file_content);

        try self.loadFromContent(file_content);
    }

    pub fn loadFromDirHandle(self: *Self, dir: DirHandle, config_filename: []const u8) !void {
        if (self.config != null) return; // Already loaded

        const file_content = dir.readFileAlloc(self.allocator, config_filename, 1024 * 1024) catch |err| switch (err) {
            error.FileNotFound => {
                self.config = ZonConfig{}; // Empty config
                return;
            },
            else => return err,
        };
        defer self.allocator.free(file_content);

        try self.loadFromContent(file_content);
    }

    pub fn loadFromContent(self: *Self, content: []const u8) !void {
        if (self.config != null) return; // Already loaded

        // Add null terminator for ZON parsing
        const null_terminated = try self.allocator.dupeZ(u8, content);
        defer self.allocator.free(null_terminated);

        // Parse the ZON content
        const parsed = std.zon.parse.fromSlice(ZonConfig, self.allocator, null_terminated, null, .{}) catch {
            self.config = ZonConfig{}; // Empty config on parse error
            return;
        };

        self.config = parsed;
    }

    pub fn getConfig(self: *Self) !ZonConfig {
        try self.loadFromFile(DEFAULT_CONFIG_FILENAME);
        return self.config orelse ZonConfig{};
    }

    pub fn getSharedConfig(self: *Self) !SharedConfig {
        try self.loadFromFile(DEFAULT_CONFIG_FILENAME);
        const cwd = self.filesystem.cwd();
        defer cwd.close();
        return self.getSharedConfigFromDirHandleInternal(cwd);
    }

    pub fn getSharedConfigFromDir(self: *Self, dir: std.fs.Dir) !SharedConfig {
        try self.loadFromDir(dir, DEFAULT_CONFIG_FILENAME);
        return self.getSharedConfigFromDirInternal(dir);
    }

    pub fn getSharedConfigFromDirHandle(self: *Self, dir: DirHandle) !SharedConfig {
        try self.loadFromDirHandle(dir, DEFAULT_CONFIG_FILENAME);
        return self.getSharedConfigFromDirHandleInternal(dir);
    }

    fn getSharedConfigFromDirInternal(self: *Self, dir: std.fs.Dir) !SharedConfig {

        const config = self.config orelse ZonConfig{};

        // Resolve base patterns (default to "extend")
        const base_patterns = if (config.base_patterns) |bp_str|
            BasePatterns.fromZon(bp_str)
        else
            BasePatterns.extend;

        // Create pattern resolver
        const resolver = PatternResolver.init(self.allocator);

        // Resolve ignored patterns
        const ignored_patterns = try resolver.resolveIgnoredPatterns(base_patterns, config.ignored_patterns);

        // Resolve hidden files
        const hidden_files = try resolver.resolveHiddenFiles(config.hidden_files);

        // Resolve gitignore patterns (default to respecting gitignore)
        const respect_gitignore = config.respect_gitignore orelse true;
        var gitignore_patterns: []const []const u8 = &[_][]const u8{};

        if (respect_gitignore) {
            gitignore_patterns = GitignorePatterns.loadFromDir(self.allocator, dir, ".gitignore") catch &[_][]const u8{}; // Ignore errors, use empty patterns
        }

        // Resolve symlink behavior (default to skip)
        const symlink_behavior = if (config.symlink_behavior) |sb_str|
            SymlinkBehavior.fromString(sb_str) orelse SymlinkBehavior.skip
        else
            SymlinkBehavior.skip;

        return SharedConfig{
            .ignored_patterns = ignored_patterns,
            .hidden_files = hidden_files,
            .gitignore_patterns = gitignore_patterns,
            .symlink_behavior = symlink_behavior,
            .respect_gitignore = respect_gitignore,
            .patterns_allocated = true,
        };
    }

    fn getSharedConfigFromDirHandleInternal(self: *Self, dir: DirHandle) !SharedConfig {
        const config = self.config orelse ZonConfig{};

        // Resolve base patterns (default to "extend")
        const base_patterns = if (config.base_patterns) |bp_str|
            BasePatterns.fromZon(bp_str)
        else
            BasePatterns.extend;

        // Create pattern resolver
        const resolver = PatternResolver.init(self.allocator);

        // Resolve ignored patterns
        const ignored_patterns = try resolver.resolveIgnoredPatterns(base_patterns, config.ignored_patterns);

        // Resolve hidden files
        const hidden_files = try resolver.resolveHiddenFiles(config.hidden_files);

        // Resolve gitignore patterns (default to respecting gitignore)
        const respect_gitignore = config.respect_gitignore orelse true;
        var gitignore_patterns: []const []const u8 = &[_][]const u8{};

        if (respect_gitignore) {
            gitignore_patterns = GitignorePatterns.loadFromDirHandle(self.allocator, dir, ".gitignore") catch &[_][]const u8{}; // Ignore errors, use empty patterns
        }

        // Resolve symlink behavior (default to skip)
        const symlink_behavior = if (config.symlink_behavior) |sb_str|
            SymlinkBehavior.fromString(sb_str) orelse SymlinkBehavior.skip
        else
            SymlinkBehavior.skip;

        return SharedConfig{
            .ignored_patterns = ignored_patterns,
            .hidden_files = hidden_files,
            .gitignore_patterns = gitignore_patterns,
            .symlink_behavior = symlink_behavior,
            .respect_gitignore = respect_gitignore,
            .patterns_allocated = true,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.config) |config| {
            std.zon.parse.free(self.allocator, config);
        }
    }
};
