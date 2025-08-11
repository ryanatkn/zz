const std = @import("std");

pub const Config = struct {
    allocator: std.mem.Allocator,
    ignored_patterns: []const []const u8,
    prepend_text: ?[]const u8,
    append_text: ?[]const u8,
    allow_empty_glob: bool,
    allow_missing: bool,
    
    const Self = @This();
    
    // Default patterns to ignore
    const default_ignored = [_][]const u8{
        ".git",
        ".zig-cache", 
        "zig-out",
        "node_modules",
    };
    
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
            if (std.mem.startsWith(u8, arg, "--prepend=")) {
                const text = arg[10..];
                // Free old value if present
                if (config.prepend_text) |old| {
                    allocator.free(old);
                }
                config.prepend_text = try allocator.dupe(u8, text);
            } else if (std.mem.startsWith(u8, arg, "--append=")) {
                const text = arg[9..];
                // Free old value if present
                if (config.append_text) |old| {
                    allocator.free(old);
                }
                config.append_text = try allocator.dupe(u8, text);
            } else if (std.mem.eql(u8, arg, "--allow-empty-glob")) {
                config.allow_empty_glob = true;
            } else if (std.mem.eql(u8, arg, "--allow-missing")) {
                config.allow_missing = true;
            }
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
    
    pub fn shouldIgnore(self: Self, path: []const u8) bool {
        const glob = @import("glob.zig");
        
        for (self.ignored_patterns) |pattern| {
            // Check if pattern contains glob characters
            if (std.mem.indexOf(u8, pattern, "*") != null or 
                std.mem.indexOf(u8, pattern, "?") != null) {
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
        var i: usize = 2; // Start after "zz prompt"
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