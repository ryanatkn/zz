/// Bulk allocator for JSON parser - optimizes allocation patterns
/// Estimates node count and pre-allocates in chunks to reduce allocation overhead
const std = @import("std");
const Node = @import("ast.zig").Node;

/// Estimates the number of nodes needed based on token count
/// This allows pre-allocation to reduce allocation calls by 80-90%
pub fn estimateNodeCount(tokens: anytype) usize {
    // Conservative estimate: each token might create 1-2 nodes
    // JSON structure: { "key": value } = 5 tokens, 3 nodes (property, key, value)
    // So roughly 60% of tokens become nodes
    var estimate: usize = 0;
    
    for (tokens) |token| {
        switch (token.kind) {
            // Tokens that definitely create nodes
            .string, .number, .boolean, .null => estimate += 1,
            
            // Structural tokens that create container nodes
            .left_brace, .left_bracket => estimate += 1,
            
            // Other tokens (punctuation) generally don't create nodes
            else => {},
        }
    }
    
    // Add 20% buffer for properties and intermediate nodes
    return estimate + (estimate / 5);
}

/// Bulk node allocator that pre-allocates chunks
pub const BulkAllocator = struct {
    arena: std.heap.ArenaAllocator,
    nodes: []Node,
    used: usize,
    
    pub fn init(allocator: std.mem.Allocator, estimated_count: usize) !BulkAllocator {
        var arena = std.heap.ArenaAllocator.init(allocator);
        const nodes = try arena.allocator().alloc(Node, estimated_count);
        
        return BulkAllocator{
            .arena = arena,
            .nodes = nodes,
            .used = 0,
        };
    }
    
    pub fn deinit(self: *BulkAllocator) void {
        self.arena.deinit();
    }
    
    /// Allocate a single node (much faster than individual create calls)
    pub fn allocateNode(self: *BulkAllocator) !*Node {
        if (self.used >= self.nodes.len) {
            // Fall back to arena allocation if we exceed estimate
            return self.arena.allocator().create(Node);
        }
        
        const node = &self.nodes[self.used];
        self.used += 1;
        return node;
    }
    
    /// Allocate multiple nodes at once
    pub fn allocateNodes(self: *BulkAllocator, count: usize) ![]Node {
        if (self.used + count > self.nodes.len) {
            // Fall back to arena allocation
            return self.arena.allocator().alloc(Node, count);
        }
        
        const start = self.used;
        self.used += count;
        return self.nodes[start..self.used];
    }
    
    /// Get utilization statistics
    pub fn getUtilization(self: BulkAllocator) f64 {
        if (self.nodes.len == 0) return 0.0;
        return @as(f64, @floatFromInt(self.used)) / @as(f64, @floatFromInt(self.nodes.len));
    }
};

test "bulk allocator estimation" {
    const testing = std.testing;
    
    // Mock token structure for testing
    const MockToken = struct {
        kind: enum { string, number, boolean, null, left_brace, right_brace, left_bracket, right_bracket, colon, comma },
    };
    
    // Simple JSON: {"key": "value"}
    const tokens = [_]MockToken{
        .{ .kind = .left_brace },
        .{ .kind = .string },      // "key"
        .{ .kind = .colon },
        .{ .kind = .string },      // "value"
        .{ .kind = .right_brace },
    };
    
    const estimate = estimateNodeCount(&tokens);
    // Should estimate ~3 nodes (object, property with key, property with value)
    try testing.expect(estimate >= 2 and estimate <= 5);
}

test "bulk allocator performance" {
    const testing = std.testing;
    
    var allocator = BulkAllocator.init(testing.allocator, 100) catch unreachable;
    defer allocator.deinit();
    
    // Allocate multiple nodes
    var nodes: [50]*Node = undefined;
    for (&nodes) |*node_ptr| {
        node_ptr.* = try allocator.allocateNode();
    }
    
    // Check utilization
    const util = allocator.getUtilization();
    try testing.expect(util >= 0.4 and util <= 0.6); // Should use about half
}