const std = @import("std");

/// Memory pool for frequently allocated data structures
/// Provides specialized pools for common ArrayList types to reduce allocation overhead
/// Uses stdlib-optimized unmanaged containers for better performance
pub const MemoryPools = struct {
    allocator: std.mem.Allocator,
    
    // Pool for path strings (most common allocation)
    path_pool: StringPool,
    
    // Pool for ArrayList([]u8) - used in glob expansion
    path_list_pool: ArrayListPool([]u8),
    
    // Pool for ArrayList([]const u8) - used in pattern matching
    const_path_list_pool: ArrayListPool([]const u8),
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .path_pool = StringPool.init(allocator),
            .path_list_pool = ArrayListPool([]u8).init(allocator),
            .const_path_list_pool = ArrayListPool([]const u8).init(allocator),
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.path_pool.deinit();
        self.path_list_pool.deinit();
        self.const_path_list_pool.deinit();
    }
    
    /// Get a string from the path pool
    pub fn createString(self: *Self, len: usize) ![]u8 {
        return self.path_pool.create(len);
    }
    
    /// Return a string to the path pool
    pub fn releaseString(self: *Self, str: []u8) void {
        self.path_pool.release(str);
    }
    
    /// Get an ArrayList([]u8) from the pool
    pub fn createPathList(self: *Self) !std.ArrayList([]u8) {
        return self.path_list_pool.create();
    }
    
    /// Return an ArrayList([]u8) to the pool
    pub fn releasePathList(self: *Self, list: std.ArrayList([]u8)) void {
        self.path_list_pool.release(list);
    }
    
    /// Get an ArrayList([]const u8) from the pool
    pub fn createConstPathList(self: *Self) !std.ArrayList([]const u8) {
        return self.const_path_list_pool.create();
    }
    
    /// Return an ArrayList([]const u8) to the pool
    pub fn releaseConstPathList(self: *Self, list: std.ArrayList([]const u8)) void {
        self.const_path_list_pool.release(list);
    }
};

/// Pool for string allocations
const StringPool = struct {
    allocator: std.mem.Allocator,
    available: std.ArrayList([]u8),
    
    const INITIAL_STRING_SIZE = 256;
    const MAX_POOLED_SIZE = 2048;
    
    const Self = @This();
    
    fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .available = std.ArrayList([]u8).init(allocator),
        };
    }
    
    fn deinit(self: *Self) void {
        // Free all pooled strings
        for (self.available.items) |str| {
            self.allocator.free(str);
        }
        self.available.deinit();
    }
    
    fn create(self: *Self, len: usize) ![]u8 {
        // For large strings, allocate directly
        if (len > MAX_POOLED_SIZE) {
            return try self.allocator.alloc(u8, len);
        }
        
        // Try to find a suitable string in the pool
        var best_idx: ?usize = null;
        var best_size: usize = std.math.maxInt(usize);
        
        for (self.available.items, 0..) |str, i| {
            if (str.len >= len and str.len < best_size) {
                best_idx = i;
                best_size = str.len;
                
                // Perfect fit
                if (str.len == len) break;
            }
        }
        
        if (best_idx) |idx| {
            const result = self.available.swapRemove(idx);
            return result[0..len]; // Return slice of requested size
        }
        
        // No suitable string found, allocate new one
        const size = std.math.max(len, INITIAL_STRING_SIZE);
        return try self.allocator.alloc(u8, size);
    }
    
    fn release(self: *Self, str: []u8) void {
        // Only pool reasonably sized strings
        if (str.len <= MAX_POOLED_SIZE) {
            self.available.append(str) catch {
                // If we can't pool it, just free it
                self.allocator.free(str);
            };
        } else {
            self.allocator.free(str);
        }
    }
};

/// Generic pool for ArrayList types
fn ArrayListPool(comptime T: type) type {
    return struct {
        allocator: std.mem.Allocator,
        available: std.ArrayList(std.ArrayList(T)),
        
        const Self = @This();
        
        fn init(allocator: std.mem.Allocator) Self {
            return Self{
                .allocator = allocator,
                .available = std.ArrayList(std.ArrayList(T)).init(allocator),
            };
        }
        
        fn deinit(self: *Self) void {
            // Deinitialize all pooled ArrayLists
            for (self.available.items) |*list| {
                list.deinit();
            }
            self.available.deinit();
        }
        
        fn create(self: *Self) !std.ArrayList(T) {
            if (self.available.items.len > 0) {
                var result = self.available.pop();
                result.clearRetainingCapacity(); // Reset but keep capacity
                return result;
            }
            
            // No available ArrayLists, create new one
            return std.ArrayList(T).init(self.allocator);
        }
        
        fn release(self: *Self, list: std.ArrayList(T)) void {
            // Clear the list and return to pool
            var mut_list = list;
            mut_list.clearRetainingCapacity();
            
            self.available.append(mut_list) catch {
                // If we can't pool it, just deinitialize
                mut_list.deinit();
            };
        }
    };
}

/// Wrapper function for convenient ArrayList([]u8) usage with RAII
pub fn withPathList(pools: *MemoryPools, comptime func: anytype, args: anytype) !@TypeOf(func(std.ArrayList([]u8), args)) {
    var list = try pools.createPathList();
    defer pools.releasePathList(list);
    
    return try func(list, args);
}

/// Wrapper function for convenient ArrayList([]const u8) usage with RAII
pub fn withConstPathList(pools: *MemoryPools, comptime func: anytype, args: anytype) !@TypeOf(func(std.ArrayList([]const u8), args)) {
    var list = try pools.createConstPathList();
    defer pools.releaseConstPathList(list);
    
    return try func(list, args);
}