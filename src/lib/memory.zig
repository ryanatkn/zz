const std = @import("std");

/// Memory management utilities with idiomatic Zig patterns
/// Consolidates pools.zig and string_pool.zig with clean APIs

/// Arena allocator wrapper for temporary allocations
pub const Arena = struct {
    arena: std.heap.ArenaAllocator,

    pub fn init(backing: std.mem.Allocator) Arena {
        return Arena{
            .arena = std.heap.ArenaAllocator.init(backing),
        };
    }

    pub fn allocator(self: *Arena) std.mem.Allocator {
        return self.arena.allocator();
    }

    /// Clear all allocations at once
    pub fn reset(self: *Arena) void {
        _ = self.arena.reset(.retain_capacity);
    }

    pub fn deinit(self: *Arena) void {
        self.arena.deinit();
    }
};

/// String interning with performance tracking
pub const StringIntern = struct {
    allocator: std.mem.Allocator,
    arena: Arena,
    pool: std.StringHashMapUnmanaged([]const u8),
    
    // Performance counters
    hits: u64 = 0,
    misses: u64 = 0,

    pub fn init(allocator: std.mem.Allocator) StringIntern {
        return StringIntern{
            .allocator = allocator,
            .arena = Arena.init(allocator),
            .pool = std.StringHashMapUnmanaged([]const u8){},
        };
    }

    pub fn deinit(self: *StringIntern) void {
        self.pool.deinit(self.allocator);
        self.arena.deinit();
    }

    /// Get interned string - returns existing or creates new
    pub fn get(self: *StringIntern, str: []const u8) ![]const u8 {
        if (self.pool.get(str)) |interned| {
            self.hits += 1;
            return interned;
        }

        // Create new interned string
        const owned = try self.arena.allocator().dupe(u8, str);
        try self.pool.put(self.allocator, owned, owned);
        self.misses += 1;
        return owned;
    }

    /// Build and intern path from components
    pub fn path(self: *StringIntern, dir: []const u8, name: []const u8) ![]const u8 {
        // Use arena for temporary allocation
        const key = try std.fmt.allocPrint(self.arena.allocator(), "{s}/{s}", .{ dir, name });
        return self.get(key);
    }

    /// Get cache efficiency statistics
    pub fn efficiency(self: *const StringIntern) f64 {
        const total = self.hits + self.misses;
        if (total == 0) return 0.0;
        return @as(f64, @floatFromInt(self.hits)) / @as(f64, @floatFromInt(total));
    }

    /// Reset performance counters
    pub fn resetStats(self: *StringIntern) void {
        self.hits = 0;
        self.misses = 0;
    }

    /// Clear pool but retain capacity
    pub fn clear(self: *StringIntern) void {
        self.pool.clearRetainingCapacity(self.allocator);
        self.arena.reset();
        self.resetStats();
    }
};

/// Path cache with common patterns pre-loaded
pub const PathCache = struct {
    intern: StringIntern,
    common: std.StringHashMapUnmanaged([]const u8),

    const COMMON_PATHS = [_][]const u8{
        ".", "..", "src", "test", "tests", "node_modules", 
        ".git", ".zig-cache", "zig-out", "build.zig",
        "README.md", ".gitignore", "main.zig", "lib.zig",
    };

    pub fn init(allocator: std.mem.Allocator) !PathCache {
        var self = PathCache{
            .intern = StringIntern.init(allocator),
            .common = std.StringHashMapUnmanaged([]const u8){},
        };

        // Pre-load common paths
        for (COMMON_PATHS) |path| {
            const interned = try self.intern.get(path);
            try self.common.put(allocator, path, interned);
        }

        return self;
    }

    pub fn deinit(self: *PathCache) void {
        self.common.deinit(self.intern.allocator);
        self.intern.deinit();
    }

    /// Get cached or interned path
    pub fn get(self: *PathCache, path: []const u8) ![]const u8 {
        // Check common paths first (fastest)
        if (self.common.get(path)) |cached| {
            return cached;
        }
        
        // Fall back to general interning
        return self.intern.get(path);
    }

    /// Build path from components
    pub fn build(self: *PathCache, dir: []const u8, name: []const u8) ![]const u8 {
        return self.intern.path(dir, name);
    }
};

/// Simple memory pools for ArrayList reuse
pub const ListPool = struct {
    string_lists: std.ArrayList(std.ArrayList([]u8)),
    const_string_lists: std.ArrayList(std.ArrayList([]const u8)),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ListPool {
        return ListPool{
            .string_lists = std.ArrayList(std.ArrayList([]u8)).init(allocator),
            .const_string_lists = std.ArrayList(std.ArrayList([]const u8)).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ListPool) void {
        // Deinit all pooled lists
        for (self.string_lists.items) |*list| {
            list.deinit();
        }
        for (self.const_string_lists.items) |*list| {
            list.deinit();
        }
        self.string_lists.deinit();
        self.const_string_lists.deinit();
    }

    /// Get ArrayList([]u8) from pool or create new
    pub fn getStringList(self: *ListPool) std.ArrayList([]u8) {
        if (self.string_lists.items.len > 0) {
            return self.string_lists.pop().?;
        }
        return std.ArrayList([]u8).init(self.allocator);
    }

    /// Return ArrayList([]u8) to pool
    pub fn putStringList(self: *ListPool, list: std.ArrayList([]u8)) void {
        var mut_list = list;
        mut_list.clearRetainingCapacity();
        self.string_lists.append(mut_list) catch {
            // If pool is full, just deinit
            mut_list.deinit();
        };
    }

    /// Get ArrayList([]const u8) from pool or create new
    pub fn getConstStringList(self: *ListPool) std.ArrayList([]const u8) {
        if (self.const_string_lists.items.len > 0) {
            return self.const_string_lists.pop().?;
        }
        return std.ArrayList([]const u8).init(self.allocator);
    }

    /// Return ArrayList([]const u8) to pool
    pub fn putConstStringList(self: *ListPool, list: std.ArrayList([]const u8)) void {
        var mut_list = list;
        mut_list.clearRetainingCapacity();
        self.const_string_lists.append(mut_list) catch {
            // If pool is full, just deinit
            mut_list.deinit();
        };
    }
};

// RAII helper functions for automatic cleanup
pub fn withStringList(pool: *ListPool, comptime func: anytype) !@TypeOf(func(@as(std.ArrayList([]u8), undefined))) {
    const list = pool.getStringList();
    defer pool.putStringList(list);
    return try func(list);
}

pub fn withConstStringList(pool: *ListPool, comptime func: anytype) !@TypeOf(func(@as(*std.ArrayList([]const u8), undefined)).*) {
    var list = pool.getConstStringList();
    defer pool.putConstStringList(list);
    return try func(&list);
}

test "Arena basic functionality" {
    const testing = std.testing;
    
    var arena = Arena.init(testing.allocator);
    defer arena.deinit();
    
    const str1 = try arena.allocator().dupe(u8, "hello");
    const str2 = try arena.allocator().dupe(u8, "world");
    
    try testing.expectEqualStrings("hello", str1);
    try testing.expectEqualStrings("world", str2);
    
    arena.reset();
    
    // After reset, can allocate again
    const str3 = try arena.allocator().dupe(u8, "reset");
    try testing.expectEqualStrings("reset", str3);
}

test "StringIntern efficiency" {
    const testing = std.testing;
    
    var intern = StringIntern.init(testing.allocator);
    defer intern.deinit();
    
    const str1 = try intern.get("test");
    const str2 = try intern.get("test");
    
    // Should be same pointer (interned)
    try testing.expect(str1.ptr == str2.ptr);
    try testing.expect(intern.efficiency() > 0.0);
}

test "PathCache common paths" {
    const testing = std.testing;
    
    var cache = try PathCache.init(testing.allocator);
    defer cache.deinit();
    
    const src1 = try cache.get("src");
    const src2 = try cache.get("src");
    
    // Should be same pointer (cached)
    try testing.expect(src1.ptr == src2.ptr);
}

test "ListPool reuse" {
    const testing = std.testing;
    
    var pool = ListPool.init(testing.allocator);
    defer pool.deinit();
    
    // Test basic reuse
    const list1 = pool.getStringList();
    pool.putStringList(list1);
    
    const list2 = pool.getStringList();
    pool.putStringList(list2);
}