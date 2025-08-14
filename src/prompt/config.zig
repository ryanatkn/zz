const std = @import("std");
const FilesystemInterface = @import("../filesystem/interface.zig").FilesystemInterface;
const SharedConfig = @import("../config.zig").SharedConfig;
const ZonLoader = @import("../config.zig").ZonLoader;
const shouldIgnorePath = @import("../config.zig").shouldIgnorePath;
const ExtractionFlags = @import("../lib/extraction_flags.zig").ExtractionFlags;

pub const Config = struct {
    allocator: std.mem.Allocator,
    shared_config: SharedConfig,
    prepend_text: ?[]const u8,
    append_text: ?[]const u8,
    allow_empty_glob: bool,
    allow_missing: bool,
    extraction_flags: ExtractionFlags,

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
            .extraction_flags = ExtractionFlags{},
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
        } else if (std.mem.eql(u8, arg, "--signatures")) {
            config.extraction_flags.signatures = true;
        } else if (std.mem.eql(u8, arg, "--types")) {
            config.extraction_flags.types = true;
        } else if (std.mem.eql(u8, arg, "--docs")) {
            config.extraction_flags.docs = true;
        } else if (std.mem.eql(u8, arg, "--structure")) {
            config.extraction_flags.structure = true;
        } else if (std.mem.eql(u8, arg, "--imports")) {
            config.extraction_flags.imports = true;
        } else if (std.mem.eql(u8, arg, "--errors")) {
            config.extraction_flags.errors = true;
        } else if (std.mem.eql(u8, arg, "--tests")) {
            config.extraction_flags.tests = true;
        } else if (std.mem.eql(u8, arg, "--full")) {
            config.extraction_flags.full = true;
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

    pub fn fromArgs(allocator: std.mem.Allocator, filesystem: FilesystemInterface, args: [][:0]const u8) !Self {
        // Load shared config from ZON
        var zon_loader = ZonLoader.init(allocator, filesystem);
        defer zon_loader.deinit();
        const shared_config = try zon_loader.getSharedConfig();

        var config = Self{
            .allocator = allocator,
            .shared_config = shared_config,
            .prepend_text = null,
            .append_text = null,
            .allow_empty_glob = false,
            .allow_missing = false,
            .extraction_flags = ExtractionFlags{},
        };

        // Parse flags
        for (args) |arg| {
            try parseFlag(&config, allocator, arg);
        }

        // Set default extraction mode if none specified
        config.extraction_flags.setDefault();

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
