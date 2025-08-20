const std = @import("std");

// Local config modules
const shared = @import("shared.zig");
const resolver_mod = @import("resolver.zig");

// Library modules
const patterns = @import("../lib/patterns/gitignore.zig");
const filesystem_mod = @import("../lib/filesystem/interface.zig");
const filesystem_utils = @import("../lib/core/filesystem.zig");
const zon_language = @import("../lib/languages/zon/mod.zig");
const zon_memory = @import("../lib/memory/zon.zig");

// Type aliases
const SharedConfig = shared.SharedConfig;
const BasePatterns = shared.BasePatterns;
const SymlinkBehavior = shared.SymlinkBehavior;
const PatternResolver = resolver_mod.PatternResolver;
const GitignorePatterns = patterns.GitignorePatterns;
const FilesystemInterface = filesystem_mod.FilesystemInterface;
const DirHandle = filesystem_mod.DirHandle;
const ZonParser = zon_language.ZonParser;
const ManagedZonConfig = zon_memory.ManagedZonConfig;

pub const IndentStyle = enum {
    space,
    tab,
};

pub const QuoteStyle = enum {
    single,
    double,
    preserve,
};

pub const FormatConfigOptions = struct {
    indent_size: u8 = 4,
    indent_style: IndentStyle = .space,
    line_width: u32 = 100,
    preserve_newlines: bool = true,
    trailing_comma: bool = false,
    sort_keys: bool = false,
    quote_style: QuoteStyle = .preserve,
    use_ast: bool = true,
};

pub const ZonConfig = struct {
    base_patterns: ?[]const u8 = null, // Changed from BasePatterns to string for ZON compatibility
    ignored_patterns: ?[]const []const u8 = null,
    hidden_files: ?[]const []const u8 = null,
    symlink_behavior: ?[]const u8 = null, // Changed from enum to string for ZON compatibility
    respect_gitignore: ?bool = null,
    tree: ?TreeSection = null,
    prompt: ?PromptSection = null,
    format: ?FormatSection = null,

    const TreeSection = struct {
        // Tree-specific overrides if needed in future
    };

    const PromptSection = struct {
        // Prompt-specific overrides if needed in future
    };

    const FormatSection = struct {
        indent_size: ?u8 = null,
        indent_style: ?[]const u8 = null, // "space" or "tab"
        line_width: ?u32 = null,
        preserve_newlines: ?bool = null,
        trailing_comma: ?bool = null,
        sort_keys: ?bool = null,
        quote_style: ?[]const u8 = null, // "single", "double", "preserve"
        use_ast: ?bool = null,
    };
};

pub const ZonLoader = struct {
    allocator: std.mem.Allocator,
    config: ?ManagedZonConfig(ZonConfig),
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

        const file_content = try filesystem_utils.Operations.readConfigFile(cwd, self.allocator, config_path, 1024 * 1024);
        if (file_content) |content| {
            defer self.allocator.free(content);
            try self.loadFromContent(content);
        } else {
            self.config = ManagedZonConfig(ZonConfig).initDefault(self.allocator, ZonConfig{}); // Empty config - file not found
        }
    }

    pub fn loadFromDir(self: *Self, dir: std.fs.Dir, config_filename: []const u8) !void {
        if (self.config != null) return; // Already loaded

        const file_content = try filesystem_utils.Operations.readConfigFileFromStdDir(dir, self.allocator, config_filename, 1024 * 1024);
        if (file_content) |content| {
            defer self.allocator.free(content);
            try self.loadFromContent(content);
        } else {
            self.config = ManagedZonConfig(ZonConfig).initDefault(self.allocator, ZonConfig{}); // Empty config - file not found
        }
    }

    pub fn loadFromDirHandle(self: *Self, dir: DirHandle, config_filename: []const u8) !void {
        if (self.config != null) return; // Already loaded

        const file_content = try filesystem_utils.Operations.readConfigFile(dir, self.allocator, config_filename, 1024 * 1024);
        if (file_content) |content| {
            defer self.allocator.free(content);
            try self.loadFromContent(content);
        } else {
            self.config = ManagedZonConfig(ZonConfig).initDefault(self.allocator, ZonConfig{}); // Empty config - file not found
        }
    }

    pub fn loadFromContent(self: *Self, content: []const u8) !void {
        if (self.config != null) return; // Already loaded

        // Use safe ZON parsing with proper memory management
        self.config = zon_memory.parseZonSafely(ZonConfig, self.allocator, content, ZonConfig{});
    }

    pub fn getConfig(self: *Self) !ZonConfig {
        try self.loadFromFile(DEFAULT_CONFIG_FILENAME);
        if (self.config) |*managed| {
            return managed.get();
        } else {
            return ZonConfig{};
        }
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
        const config = if (self.config) |*managed| managed.get() else ZonConfig{};

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
            const gitignore = GitignorePatterns.loadFromDirHandle(self.allocator, dir, ".gitignore") catch GitignorePatterns.init(self.allocator, &[_][]const u8{});
            gitignore_patterns = gitignore.patterns; // Extract patterns from struct
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
        const config = if (self.config) |*managed| managed.get() else ZonConfig{};

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
            const gitignore = GitignorePatterns.loadFromDirHandle(self.allocator, dir, ".gitignore") catch GitignorePatterns.init(self.allocator, &[_][]const u8{});
            gitignore_patterns = gitignore.patterns; // Extract patterns from struct
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

    pub fn getFormatConfig(self: *Self) !FormatConfigOptions {
        try self.loadFromFile(DEFAULT_CONFIG_FILENAME);
        const config = if (self.config) |*managed| managed.get() else ZonConfig{};

        var options = FormatConfigOptions{};

        if (config.format) |format_section| {
            if (format_section.indent_size) |size| {
                options.indent_size = size;
            }

            if (format_section.indent_style) |style_str| {
                if (std.mem.eql(u8, style_str, "tab")) {
                    options.indent_style = .tab;
                } else if (std.mem.eql(u8, style_str, "space")) {
                    options.indent_style = .space;
                }
            }

            if (format_section.line_width) |width| {
                options.line_width = width;
            }

            if (format_section.preserve_newlines) |preserve| {
                options.preserve_newlines = preserve;
            }

            if (format_section.trailing_comma) |trailing| {
                options.trailing_comma = trailing;
            }

            if (format_section.sort_keys) |sort| {
                options.sort_keys = sort;
            }

            if (format_section.quote_style) |quote_str| {
                if (std.mem.eql(u8, quote_str, "single")) {
                    options.quote_style = .single;
                } else if (std.mem.eql(u8, quote_str, "double")) {
                    options.quote_style = .double;
                } else if (std.mem.eql(u8, quote_str, "preserve")) {
                    options.quote_style = .preserve;
                }
            }

            if (format_section.use_ast) |use_ast| {
                options.use_ast = use_ast;
            }
        }

        return options;
    }

    pub fn deinit(self: *Self) void {
        if (self.config) |*managed| {
            managed.deinit();
        }
    }
};
