const std = @import("std");

/// String interning pool for reducing repeated allocations
/// Optimized for common path patterns in filesystem operations
pub const StringPool = struct {
    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    pool: std.StringHashMap([]const u8),
    
    // Performance counters
    hits: u64 = 0,
    misses: u64 = 0,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .arena = std.heap.ArenaAllocator.init(allocator),
            .pool = std.StringHashMap([]const u8).init(allocator),
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.pool.deinit();
        self.arena.deinit();
    }
    
    /// Get an interned string - returns existing instance or creates new one
    pub fn intern(self: *Self, str: []const u8) ![]const u8 {
        // Check if we already have this string
        if (self.pool.get(str)) |interned| {
            self.hits += 1;
            return interned;
        }
        
        // Create new interned string in arena
        const owned = try self.arena.allocator().dupe(u8, str);
        try self.pool.put(owned, owned);
        self.misses += 1;
        return owned;
    }
    
    /// Specialized intern for common path patterns
    pub fn internPath(self: *Self, dir: []const u8, name: []const u8) ![]const u8 {
        // Build key for lookup (temporary allocation)
        const key = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ dir, name });
        defer self.allocator.free(key);
        
        return self.intern(key);
    }
    
    /// Get statistics about pool efficiency
    pub fn stats(self: *const Self) struct { hits: u64, misses: u64, efficiency: f64 } {
        const total = self.hits + self.misses;
        const efficiency = if (total == 0) 0.0 else @as(f64, @floatFromInt(self.hits)) / @as(f64, @floatFromInt(total));
        return .{ .hits = self.hits, .misses = self.misses, .efficiency = efficiency };
    }
    
    /// Reset statistics
    pub fn resetStats(self: *Self) void {
        self.hits = 0;
        self.misses = 0;
    }
    
    /// Clear pool but keep arena (for reuse)
    pub fn clear(self: *Self) void {
        self.pool.clearRetainingCapacity();
        // Note: Arena memory is not freed - it will be reused for new strings
        self.resetStats();
    }
    
    /// Get pool size
    pub fn size(self: *const Self) u32 {
        return @intCast(self.pool.count());
    }
};

/// Path string cache for commonly used paths
pub const PathCache = struct {
    pool: StringPool,
    common_paths: std.StringHashMap([]const u8),
    
    const Self = @This();
    
    // Common filesystem paths that appear frequently
    const COMMON_PATTERNS = [_][]const u8{
        ".",
        "..",
        "src",
        "test",
        "tests",
        "node_modules",
        ".git",
        ".zig-cache",
        "zig-out",
        "build.zig",
        "README.md",
        ".gitignore",
        "package.json",
        "main.zig",
        "lib.zig",
    };
    
    pub fn init(allocator: std.mem.Allocator) !Self {
        var self = Self{
            .pool = StringPool.init(allocator),
            .common_paths = std.StringHashMap([]const u8).init(allocator),
        };
        
        // Pre-populate with common patterns
        for (COMMON_PATTERNS) |pattern| {
            const interned = try self.pool.intern(pattern);
            try self.common_paths.put(pattern, interned);
        }
        
        return self;
    }
    
    pub fn deinit(self: *Self) void {
        self.common_paths.deinit();
        self.pool.deinit();
    }
    
    /// Get cached path or intern new one
    pub fn getPath(self: *Self, path: []const u8) ![]const u8 {
        // Check common paths first (fastest)
        if (self.common_paths.get(path)) |cached| {
            return cached;
        }
        
        // Fall back to general pool
        return self.pool.intern(path);
    }
    
    /// Build and cache path from components
    pub fn buildPath(self: *Self, dir: []const u8, name: []const u8) ![]const u8 {
        return self.pool.internPath(dir, name);
    }
    
    /// Get performance statistics
    pub fn getStats(self: *const Self) StringPool {
        return self.pool;
    }
};