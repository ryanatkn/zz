const std = @import("std");
const StringStrategy = @import("strategy.zig").StringStrategy;
const MemoryStats = @import("stats.zig").MemoryStats;

/// Specialized string allocator with interning support
pub const StringAllocator = struct {
    allocator: std.mem.Allocator,
    arena: *std.heap.ArenaAllocator,
    strategy: StringStrategy,
    stats: *MemoryStats,
    
    // String interning table
    intern_table: ?StringInternTable = null,
    
    const Self = @This();
    
    pub fn init(
        allocator: std.mem.Allocator,
        arena: *std.heap.ArenaAllocator,
        strategy: StringStrategy,
        stats: *MemoryStats,
    ) Self {
        var self = Self{
            .allocator = allocator,
            .arena = arena,
            .strategy = strategy,
            .stats = stats,
        };
        
        // Initialize intern table if using interning
        if (strategy == .interned) {
            self.intern_table = StringInternTable.init(allocator) catch null;
        }
        
        return self;
    }
    
    pub fn deinit(self: *Self) void {
        if (self.intern_table) |*table| table.deinit();
    }
    
    pub fn allocate(self: *Self, text: []const u8) ![]const u8 {
        return switch (self.strategy) {
            .arena => try self.allocateArena(text),
            .persistent => try self.allocatePersistent(text),
            .interned => try self.allocateInterned(text),
        };
    }
    
    fn allocateArena(self: *Self, text: []const u8) ![]const u8 {
        const copy = try self.arena.allocator().dupe(u8, text);
        self.stats.string_bytes_used += text.len;
        self.stats.arena_bytes_used += text.len;
        self.stats.total_bytes_allocated += text.len;
        return copy;
    }
    
    fn allocatePersistent(self: *Self, text: []const u8) ![]const u8 {
        const copy = try self.allocator.dupe(u8, text);
        self.stats.string_bytes_used += text.len;
        self.stats.total_bytes_allocated += text.len;
        return copy;
    }
    
    fn allocateInterned(self: *Self, text: []const u8) ![]const u8 {
        if (self.intern_table) |*table| {
            // Check if string already exists
            if (table.get(text)) |interned| {
                self.stats.string_intern_hits += 1;
                self.stats.string_intern_bytes_saved += text.len;
                return interned;
            }
            
            // Add new string to intern table
            const copy = try self.allocator.dupe(u8, text);
            try table.put(copy);
            
            self.stats.strings_interned += 1;
            self.stats.string_bytes_used += text.len;
            self.stats.total_bytes_allocated += text.len;
            
            return copy;
        }
        
        // Fallback to persistent if intern table failed
        return self.allocatePersistent(text);
    }
};

/// String interning table for deduplication
const StringInternTable = struct {
    allocator: std.mem.Allocator,
    map: std.StringHashMap([]const u8),
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator) !Self {
        return Self{
            .allocator = allocator,
            .map = std.StringHashMap([]const u8).init(allocator),
        };
    }
    
    pub fn deinit(self: *Self) void {
        var iter = self.map.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.map.deinit();
    }
    
    pub fn get(self: *Self, text: []const u8) ?[]const u8 {
        return self.map.get(text);
    }
    
    pub fn put(self: *Self, text: []const u8) !void {
        try self.map.put(text, text);
    }
    
    pub fn contains(self: *Self, text: []const u8) bool {
        return self.map.contains(text);
    }
    
    pub fn count(self: Self) usize {
        return self.map.count();
    }
    
    /// Calculate memory saved by interning
    pub fn calculateSavings(self: Self) usize {
        var total_length: usize = 0;
        var unique_length: usize = 0;
        var string_count: usize = 0;
        
        var iter = self.map.iterator();
        while (iter.next()) |entry| {
            unique_length += entry.key_ptr.*.len;
            string_count += 1;
        }
        
        // Estimate average reuse (conservative)
        const estimated_reuse = @max(2, string_count / 10);
        total_length = unique_length * estimated_reuse;
        
        return total_length - unique_length;
    }
};