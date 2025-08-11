const std = @import("std");

pub const ZonConfig = struct {
    tree: ?TreeSection = null,
    prompt: ?PromptSection = null,
    
    const TreeSection = struct {
        ignored_patterns: ?[]const []const u8 = null,
        hidden_files: ?[]const []const u8 = null,
    };
    
    const PromptSection = struct {
        ignored_patterns: ?[]const []const u8 = null,
    };
};

pub const ZonLoader = struct {
    allocator: std.mem.Allocator,
    config: ?ZonConfig,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .config = null,
        };
    }
    
    pub fn load(self: *Self) !void {
        if (self.config != null) return; // Already loaded
        
        const config_path = "zz.zon";
        const file_content = std.fs.cwd().readFileAlloc(self.allocator, config_path, 1024 * 1024) catch |err| switch (err) {
            error.FileNotFound => {
                self.config = ZonConfig{}; // Empty config
                return;
            },
            else => return err,
        };
        defer self.allocator.free(file_content);
        
        // Add null terminator for ZON parsing
        const null_terminated = try self.allocator.dupeZ(u8, file_content);
        defer self.allocator.free(null_terminated);
        
        // Parse the ZON content
        const parsed = std.zon.parse.fromSlice(ZonConfig, self.allocator, null_terminated, null, .{}) catch {
            self.config = ZonConfig{}; // Empty config on parse error
            return;
        };
        
        self.config = parsed;
    }
    
    pub fn getTreePatterns(self: *Self) !struct {
        ignored_patterns: [][]const u8,
        hidden_files: [][]const u8,
        patterns_allocated: bool,
    } {
        try self.load();
        
        const tree_section = if (self.config) |cfg| cfg.tree else null;
        
        if (tree_section) |tree| {
            // Copy patterns from ZON config
            const source_ignored = tree.ignored_patterns orelse &[_][]const u8{};
            const ignored_patterns = try self.allocator.alloc([]const u8, source_ignored.len);
            for (source_ignored, 0..) |pattern, i| {
                ignored_patterns[i] = try self.allocator.dupe(u8, pattern);
            }
            
            const source_hidden = tree.hidden_files orelse &[_][]const u8{};
            const hidden_files = try self.allocator.alloc([]const u8, source_hidden.len);
            for (source_hidden, 0..) |file, i| {
                hidden_files[i] = try self.allocator.dupe(u8, file);
            }
            
            return .{
                .ignored_patterns = ignored_patterns,
                .hidden_files = hidden_files,
                .patterns_allocated = true,
            };
        }
        
        // Return defaults
        const default_ignored = [_][]const u8{
            ".git", ".svn", ".hg", "node_modules", "dist", "build", "target",
            "__pycache__", "venv", "env", "tmp", "temp", ".zig-cache", "zig-out",
        };
        const default_hidden = [_][]const u8{ "Thumbs.db", ".DS_Store" };
        
        return .{
            .ignored_patterns = try self.allocator.dupe([]const u8, &default_ignored),
            .hidden_files = try self.allocator.dupe([]const u8, &default_hidden),
            .patterns_allocated = false,
        };
    }
    
    pub fn getPromptPatterns(self: *Self) ![][]const u8 {
        try self.load();
        
        const prompt_section = if (self.config) |cfg| cfg.prompt else null;
        
        if (prompt_section) |prompt| {
            if (prompt.ignored_patterns) |patterns| {
                // Copy patterns from ZON config
                const result = try self.allocator.alloc([]const u8, patterns.len);
                for (patterns, 0..) |pattern, i| {
                    result[i] = try self.allocator.dupe(u8, pattern);
                }
                return result;
            }
        }
        
        // Return defaults
        const default_patterns = [_][]const u8{ ".git", ".zig-cache", "zig-out", "node_modules" };
        return try self.allocator.dupe([]const u8, &default_patterns);
    }
    
    pub fn deinit(self: *Self) void {
        if (self.config) |config| {
            std.zon.parse.free(self.allocator, config);
        }
    }
};