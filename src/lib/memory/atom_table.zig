const std = @import("std");

/// Atom ID type for interned strings
pub const AtomId = u32;

/// Slab-allocated buffer for memory-efficient string storage
/// Reduces overhead compared to ArrayList by pre-allocating in chunks
const SlabBuffer = struct {
    slabs: std.ArrayList([]u8),
    current_slab: usize,
    current_pos: usize,
    allocator: std.mem.Allocator,
    
    const SLAB_SIZE = 4096; // 4KB slabs for good memory efficiency
    
    pub fn init(allocator: std.mem.Allocator) SlabBuffer {
        return SlabBuffer{
            .slabs = std.ArrayList([]u8).init(allocator),
            .current_slab = 0,
            .current_pos = 0,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *SlabBuffer) void {
        for (self.slabs.items) |slab| {
            self.allocator.free(slab);
        }
        self.slabs.deinit();
    }
    
    /// Allocate space for a string, returning a slice where it can be written
    pub fn allocateString(self: *SlabBuffer, len: usize) ![]u8 {
        // If string is too large for slab system, allocate separately
        if (len > SLAB_SIZE / 2) {
            const large_alloc = try self.allocator.alloc(u8, len);
            try self.slabs.append(large_alloc);
            return large_alloc;
        }
        
        // Check if current slab has enough space
        if (self.slabs.items.len == 0 or 
            self.current_pos + len > self.slabs.items[self.current_slab].len) {
            // Need a new slab
            const new_slab = try self.allocator.alloc(u8, SLAB_SIZE);
            try self.slabs.append(new_slab);
            self.current_slab = self.slabs.items.len - 1;
            self.current_pos = 0;
        }
        
        const slab = self.slabs.items[self.current_slab];
        const result = slab[self.current_pos..self.current_pos + len];
        self.current_pos += len;
        
        return result;
    }
    
    /// Get total bytes allocated (sum of all slab sizes)
    pub fn getTotalBytes(self: SlabBuffer) usize {
        var total: usize = 0;
        for (self.slabs.items) |slab| {
            total += slab.len;
        }
        return total;
    }
    
    /// Get actual bytes used (more precise than total allocated)
    pub fn getUsedBytes(self: SlabBuffer) usize {
        if (self.slabs.items.len == 0) return 0;
        
        var used: usize = 0;
        // Count all full slabs
        for (self.slabs.items[0..self.slabs.items.len-1]) |slab| {
            used += slab.len;
        }
        // Add current position in last slab
        used += self.current_pos;
        
        return used;
    }
    
    /// Clear all allocated strings while retaining slab capacity
    pub fn clear(self: *SlabBuffer) void {
        self.current_slab = 0;
        self.current_pos = 0;
        // Keep first slab if it exists, free the rest
        if (self.slabs.items.len > 1) {
            for (self.slabs.items[1..]) |slab| {
                self.allocator.free(slab);
            }
            self.slabs.shrinkRetainingCapacity(1);
        }
    }
};

/// Invalid atom ID constant
pub const INVALID_ATOM: AtomId = 0;

/// AtomTable - Global string interning with hash-consing
///
/// Implements string interning per TODO_STREAM_FIRST_PRINCIPLES.md:
/// - Single allocation for all strings
/// - Return stable IDs, not pointers
/// - Hash-consing for deduplication
/// - Zero-copy lookups
///
/// Design:
/// - Atoms start at ID 1 (0 is reserved for invalid/none)
/// - Strings are stored contiguously in slab-allocated buffers
/// - Hash map provides O(1) lookup by string
/// - Reverse lookup array provides O(1) lookup by ID
/// - Slab allocation reduces memory overhead for small strings
pub const AtomTable = struct {
    /// Slab-allocated buffer for all interned strings (more memory efficient)
    buffer: SlabBuffer,
    /// Map from string hash to atom ID
    lookup: std.StringHashMap(AtomId),
    /// Array of string slices for reverse lookup
    strings: std.ArrayList([]const u8),
    /// Allocator for internal structures
    allocator: std.mem.Allocator,
    /// Statistics
    stats: Stats,

    pub const Stats = struct {
        total_atoms: u32 = 0,
        total_bytes: usize = 0,
        lookup_hits: u64 = 0,
        lookup_misses: u64 = 0,
    };

    /// Initialize an empty atom table
    pub fn init(allocator: std.mem.Allocator) AtomTable {
        return .{
            .buffer = SlabBuffer.init(allocator),
            .lookup = std.StringHashMap(AtomId).init(allocator),
            .strings = std.ArrayList([]const u8).init(allocator),
            .allocator = allocator,
            .stats = .{},
        };
    }

    /// Clean up all resources
    pub fn deinit(self: *AtomTable) void {
        self.buffer.deinit();
        self.lookup.deinit();
        self.strings.deinit();
    }

    /// Intern a string, returning its atom ID
    /// If the string is already interned, returns existing ID
    pub fn intern(self: *AtomTable, str: []const u8) !AtomId {
        // Check if already interned
        if (self.lookup.get(str)) |id| {
            self.stats.lookup_hits += 1;
            return id;
        }

        self.stats.lookup_misses += 1;

        // Allocate new atom ID (starting from 1)
        const id = @as(AtomId, @intCast(self.strings.items.len + 1));

        // Store string in slab buffer
        const interned = try self.buffer.allocateString(str.len);
        std.mem.copyForwards(u8, interned, str);

        // Add to lookup table
        try self.lookup.put(interned, id);
        try self.strings.append(interned);

        // Update stats
        self.stats.total_atoms = id;
        self.stats.total_bytes = self.buffer.getUsedBytes();

        return id;
    }

    /// Look up string by atom ID
    /// Returns null for invalid IDs
    pub inline fn getString(self: *const AtomTable, id: AtomId) ?[]const u8 {
        if (id == 0 or id > self.strings.items.len) {
            return null;
        }
        return self.strings.items[id - 1];
    }

    /// Get atom ID for a string without interning
    /// Returns null if string is not interned
    pub inline fn getAtom(self: *const AtomTable, str: []const u8) ?AtomId {
        return self.lookup.get(str);
    }

    /// Check if an atom ID is valid
    pub inline fn isValid(self: *const AtomTable, id: AtomId) bool {
        return id > 0 and id <= self.strings.items.len;
    }

    /// Get total number of interned atoms
    pub inline fn count(self: *const AtomTable) u32 {
        return @intCast(self.strings.items.len);
    }

    /// Get memory usage statistics
    pub inline fn getStats(self: *const AtomTable) Stats {
        return self.stats;
    }

    /// Clear all atoms (useful for testing)
    pub fn clear(self: *AtomTable) void {
        self.buffer.clear();
        self.lookup.clearRetainingCapacity();
        self.strings.clearRetainingCapacity();
        self.stats = .{};
    }
};

/// Global atom table instance (optional, for convenience)
/// Applications can create their own instances as needed
pub var global_atoms: ?AtomTable = null;

/// Initialize the global atom table
pub fn initGlobal(allocator: std.mem.Allocator) void {
    global_atoms = AtomTable.init(allocator);
}

/// Deinitialize the global atom table
pub fn deinitGlobal() void {
    if (global_atoms) |*atoms| {
        atoms.deinit();
        global_atoms = null;
    }
}

/// Intern a string in the global table
pub fn internGlobal(str: []const u8) !AtomId {
    if (global_atoms) |*atoms| {
        return atoms.intern(str);
    }
    return error.GlobalTableNotInitialized;
}

/// Look up a string in the global table
pub fn lookupGlobal(id: AtomId) ?[]const u8 {
    if (global_atoms) |*atoms| {
        return atoms.getString(id);
    }
    return null;
}

test "AtomTable basic interning" {
    const testing = std.testing;

    var table = AtomTable.init(testing.allocator);
    defer table.deinit();

    // First string gets ID 1
    const id1 = try table.intern("hello");
    try testing.expectEqual(@as(AtomId, 1), id1);

    // Same string returns same ID
    const id2 = try table.intern("hello");
    try testing.expectEqual(id1, id2);

    // Different string gets new ID
    const id3 = try table.intern("world");
    try testing.expectEqual(@as(AtomId, 2), id3);

    // Verify lookups
    try testing.expectEqualStrings("hello", table.getString(id1).?);
    try testing.expectEqualStrings("world", table.getString(id3).?);

    // Invalid ID returns null
    try testing.expect(table.getString(0) == null);
    try testing.expect(table.getString(999) == null);
}

test "AtomTable deduplication" {
    const testing = std.testing;

    var table = AtomTable.init(testing.allocator);
    defer table.deinit();

    // Intern same string multiple times
    const strings = [_][]const u8{ "foo", "bar", "foo", "baz", "bar", "foo" };
    var ids: [strings.len]AtomId = undefined;

    for (strings, 0..) |str, i| {
        ids[i] = try table.intern(str);
    }

    // Check deduplication worked
    try testing.expectEqual(ids[0], ids[2]); // "foo"
    try testing.expectEqual(ids[0], ids[5]); // "foo"
    try testing.expectEqual(ids[1], ids[4]); // "bar"

    // Should only have 3 unique atoms
    try testing.expectEqual(@as(u32, 3), table.count());

    // Check stats
    const stats = table.getStats();
    try testing.expectEqual(@as(u32, 3), stats.total_atoms);
    try testing.expect(stats.lookup_hits > 0);
}

test "AtomTable getAtom without interning" {
    const testing = std.testing;

    var table = AtomTable.init(testing.allocator);
    defer table.deinit();

    // String not interned yet
    try testing.expect(table.getAtom("test") == null);

    // Intern it
    const id = try table.intern("test");

    // Now getAtom should find it
    const found_id = table.getAtom("test");
    try testing.expect(found_id != null);
    try testing.expectEqual(id, found_id.?);
}

test "AtomTable memory efficiency" {
    // Slab allocation should keep memory usage efficient
    // 100 strings (~10-12 bytes each) should use <1500 bytes total
    const testing = std.testing;

    var table = AtomTable.init(testing.allocator);
    defer table.deinit();

    // Intern many strings
    for (0..100) |i| {
        var buf: [32]u8 = undefined;
        const str = try std.fmt.bufPrint(&buf, "string_{d}", .{i});
        // The table copies the string internally, so we can use the temporary buffer
        _ = try table.intern(str);
    }

    // Check memory usage is reasonable
    const stats = table.getStats();
    try testing.expectEqual(@as(u32, 100), stats.total_atoms);

    // Each string is ~10-12 bytes, so total should be ~1000-1500 bytes
    try testing.expect(stats.total_bytes < 1500);
}

test "Global atom table" {
    const testing = std.testing;

    // Initialize global table
    initGlobal(testing.allocator);
    defer deinitGlobal();

    // Use global functions
    const id1 = try internGlobal("global_test");
    const id2 = try internGlobal("global_test");

    try testing.expectEqual(id1, id2);
    try testing.expectEqualStrings("global_test", lookupGlobal(id1).?);
}
