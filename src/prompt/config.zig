const std = @import("std");

pub const Config = struct {
    allocator: std.mem.Allocator,
    ignored_patterns: []const []const u8,
    prepend_text: ?[]const u8,
    append_text: ?[]const u8,
    allow_empty_glob: bool,
    allow_missing: bool,
    
    const Self = @This();
    
    const PREPEND_PREFIX = "--prepend=";
    const APPEND_PREFIX = "--append=";
    const SKIP_ARGS = 2; // Skip "zz prompt"
    
    // Default patterns to ignore
    const default_ignored = [_][]const u8{
        ".git",
        ".zig-cache", 
        "zig-out",
        "node_modules",
    };
    
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
        }
    }
    
    pub fn fromArgs(allocator: std.mem.Allocator, args: [][:0]const u8) !Self {
        var config = Self{
            .allocator = allocator,
            .ignored_patterns = &default_ignored,
            .prepend_text = null,
            .append_text = null,
            .allow_empty_glob = false,
            .allow_missing = false,
        };
        
        // Parse flags
        for (args) |arg| {
            try parseFlag(&config, allocator, arg);
        }
        
        // TODO: Load from zz.zon if present
        // For now, just use defaults
        
        return config;
    }
    
    pub fn deinit(self: *Self) void {
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
        const glob = @import("glob.zig");
        
        for (self.ignored_patterns) |pattern| {
            if (hasGlobChars(pattern)) {
                // Extract filename for pattern matching
                const filename = std.fs.path.basename(path);
                if (glob.matchSimplePattern(filename, pattern)) {
                    return true;
                }
            } else {
                // Simple substring match for non-glob patterns
                if (std.mem.indexOf(u8, path, pattern) != null) {
                    return true;
                }
            }
        }
        return false;
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