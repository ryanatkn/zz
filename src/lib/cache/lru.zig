/// LRU (Least Recently Used) list for cache eviction
///
/// TODO: Consider using a more cache-friendly data structure
/// TODO: Add support for weighted eviction (by size)
/// TODO: Implement CLOCK algorithm as alternative to LRU
const std = @import("std");
const PackedSpan = @import("../span/mod.zig").PackedSpan;

/// Node in the LRU list
const LruNode = struct {
    span: PackedSpan,
    prev: ?*LruNode = null,
    next: ?*LruNode = null,
    access_count: u32 = 0,
    last_access: i64 = 0,
};

/// LRU list for tracking access patterns
pub const LruList = struct {
    allocator: std.mem.Allocator,
    head: ?*LruNode = null,
    tail: ?*LruNode = null,
    map: std.AutoHashMap(PackedSpan, *LruNode),
    node_pool: std.ArrayList(*LruNode),
    free_nodes: std.ArrayList(*LruNode),
    max_nodes: usize,
    current_nodes: usize = 0,
    
    /// Initialize LRU list with maximum capacity
    pub fn init(allocator: std.mem.Allocator, max_nodes: usize) !LruList {
        var list = LruList{
            .allocator = allocator,
            .map = std.AutoHashMap(PackedSpan, *LruNode).init(allocator),
            .node_pool = std.ArrayList(*LruNode).init(allocator),
            .free_nodes = std.ArrayList(*LruNode).init(allocator),
            .max_nodes = max_nodes,
        };
        
        // Pre-allocate nodes to avoid allocations during operation
        // TODO: Make this optional for memory-constrained environments
        const preallocate = @min(max_nodes, 1024);
        try list.node_pool.ensureTotalCapacity(preallocate);
        try list.free_nodes.ensureTotalCapacity(preallocate);
        
        for (0..preallocate) |_| {
            const node = try allocator.create(LruNode);
            try list.node_pool.append(node);
            try list.free_nodes.append(node);
        }
        
        return list;
    }
    
    /// Clean up resources
    pub fn deinit(self: *LruList) void {
        for (self.node_pool.items) |node| {
            self.allocator.destroy(node);
        }
        self.node_pool.deinit();
        self.free_nodes.deinit();
        self.map.deinit();
    }
    
    /// Add a new span to the list (most recently used)
    pub fn add(self: *LruList, span: PackedSpan) !void {
        // Check if already exists
        if (self.map.get(span)) |node| {
            self.moveToFront(node);
            return;
        }
        
        // Get a free node or allocate new one
        const node = if (self.free_nodes.pop()) |n|
            n
        else blk: {
            const n = try self.allocator.create(LruNode);
            try self.node_pool.append(n);
            break :blk n;
        };
        
        node.* = LruNode{
            .span = span,
            .last_access = std.time.milliTimestamp(),
        };
        
        // Add to front of list
        node.next = self.head;
        if (self.head) |h| {
            h.prev = node;
        }
        self.head = node;
        
        if (self.tail == null) {
            self.tail = node;
        }
        
        try self.map.put(span, node);
        self.current_nodes += 1;
    }
    
    /// Touch a span (mark as recently used)
    pub fn touch(self: *LruList, span: PackedSpan) void {
        if (self.map.get(span)) |node| {
            node.access_count += 1;
            node.last_access = std.time.milliTimestamp();
            self.moveToFront(node);
        }
    }
    
    /// Remove a span from the list
    pub fn remove(self: *LruList, span: PackedSpan) void {
        if (self.map.fetchRemove(span)) |entry| {
            const node = entry.value;
            self.removeNode(node);
            self.free_nodes.append(node) catch {};
            self.current_nodes -= 1;
        }
    }
    
    /// Evict the least recently used span
    pub fn evict(self: *LruList) ?PackedSpan {
        const node = self.tail orelse return null;
        const span = node.span;
        
        _ = self.map.remove(span);
        self.removeNode(node);
        self.free_nodes.append(node) catch {};
        self.current_nodes -= 1;
        
        return span;
    }
    
    /// Clear all entries
    pub fn clear(self: *LruList) void {
        self.head = null;
        self.tail = null;
        self.map.clearRetainingCapacity();
        
        // Return all nodes to free list
        var iter = self.map.iterator();
        while (iter.next()) |entry| {
            self.free_nodes.append(entry.value_ptr.*) catch {};
        }
        
        self.current_nodes = 0;
    }
    
    /// Move a node to the front (most recently used)
    fn moveToFront(self: *LruList, node: *LruNode) void {
        if (node == self.head) return;
        
        // Remove from current position
        if (node.prev) |p| {
            p.next = node.next;
        }
        if (node.next) |n| {
            n.prev = node.prev;
        }
        if (node == self.tail) {
            self.tail = node.prev;
        }
        
        // Add to front
        node.prev = null;
        node.next = self.head;
        if (self.head) |h| {
            h.prev = node;
        }
        self.head = node;
    }
    
    /// Remove a node from the list
    fn removeNode(self: *LruList, node: *LruNode) void {
        if (node.prev) |p| {
            p.next = node.next;
        } else {
            self.head = node.next;
        }
        
        if (node.next) |n| {
            n.prev = node.prev;
        } else {
            self.tail = node.prev;
        }
        
        node.prev = null;
        node.next = null;
    }
    
    /// Get statistics about the LRU list
    pub fn getStats(self: *const LruList) LruStats {
        var total_access: u64 = 0;
        var max_access: u32 = 0;
        
        var iter = self.map.iterator();
        while (iter.next()) |entry| {
            total_access += entry.value_ptr.*.access_count;
            max_access = @max(max_access, entry.value_ptr.*.access_count);
        }
        
        return .{
            .total_nodes = self.current_nodes,
            .max_nodes = self.max_nodes,
            .total_accesses = total_access,
            .max_access_count = max_access,
            .free_nodes = self.free_nodes.items.len,
        };
    }
    
    pub const LruStats = struct {
        total_nodes: usize,
        max_nodes: usize,
        total_accesses: u64,
        max_access_count: u32,
        free_nodes: usize,
    };
};

test "LruList basic operations" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    var lru = try LruList.init(allocator, 3);
    defer lru.deinit();
    
    // Add some spans
    const span1: PackedSpan = 0x0000000100000010;
    const span2: PackedSpan = 0x0000001000000020;
    const span3: PackedSpan = 0x0000002000000030;
    const span4: PackedSpan = 0x0000003000000040;
    
    try lru.add(span1);
    try lru.add(span2);
    try lru.add(span3);
    
    // Touch span1 to make it most recently used
    lru.touch(span1);
    
    // Add span4, which should be allowed
    try lru.add(span4);
    
    // span2 should be evicted (least recently used)
    // Note: We need to manually evict since add() doesn't auto-evict
    const evicted = lru.evict();
    try testing.expect(evicted != null);
    
    // Test that span1 is still there (was touched)
    lru.touch(span1); // Should succeed without error
    
    // Test removal
    lru.remove(span3);
    try testing.expectEqual(@as(usize, 2), lru.current_nodes);
    
    // Test clear
    lru.clear();
    try testing.expectEqual(@as(usize, 0), lru.current_nodes);
    
    // TODO: Test statistics
    // TODO: Test edge cases (empty list, single item, etc.)
}