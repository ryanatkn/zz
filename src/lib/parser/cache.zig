/// Boundary caching system for fast re-parsing
///
/// Caches structural boundaries to avoid re-parsing unchanged regions.
const std = @import("std");
const Span = @import("../span/span.zig").Span;
const Boundary = @import("structural.zig").Boundary;
const Token = @import("../token/token.zig").Token;

/// Cache entry for parsed boundaries
pub const CacheEntry = struct {
    span: Span,
    hash: u64,
    boundaries: []Boundary,
    tokens: []Token,
    timestamp: i64,
    hit_count: u32 = 0,
};

/// LRU cache for boundaries
pub const BoundaryCache = struct {
    allocator: std.mem.Allocator,
    entries: std.AutoHashMap(u64, *CacheEntry),
    lru_list: std.TailQueue(*CacheEntry),
    max_entries: usize,
    total_hits: u64 = 0,
    total_misses: u64 = 0,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, max_entries: usize) Self {
        return .{
            .allocator = allocator,
            .entries = std.AutoHashMap(u64, *CacheEntry).init(allocator),
            .lru_list = std.TailQueue(*CacheEntry){},
            .max_entries = max_entries,
        };
    }

    pub fn deinit(self: *Self) void {
        var it = self.entries.iterator();
        while (it.next()) |entry| {
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.entries.deinit();

        while (self.lru_list.pop()) |node| {
            self.allocator.destroy(node);
        }
    }

    /// Get cached boundaries for span
    pub fn get(self: *Self, span: Span, hash: u64) ?[]Boundary {
        if (self.entries.get(hash)) |entry| {
            if (entry.span.start == span.start and entry.span.end == span.end) {
                // Cache hit
                self.total_hits += 1;
                entry.hit_count += 1;
                self.moveToFront(entry);
                return entry.boundaries;
            }
        }

        // Cache miss
        self.total_misses += 1;
        return null;
    }

    /// Add boundaries to cache
    pub fn put(
        self: *Self,
        span: Span,
        hash: u64,
        boundaries: []Boundary,
        tokens: []Token,
    ) !void {
        // Check if already exists
        if (self.entries.get(hash)) |existing| {
            self.removeEntry(existing);
        }

        // Evict if at capacity
        if (self.entries.count() >= self.max_entries) {
            self.evictLRU();
        }

        // Create new entry
        const entry = try self.allocator.create(CacheEntry);
        entry.* = .{
            .span = span,
            .hash = hash,
            .boundaries = boundaries,
            .tokens = tokens,
            .timestamp = std.time.timestamp(),
        };

        try self.entries.put(hash, entry);

        // Add to LRU list
        const node = try self.allocator.create(std.TailQueue(*CacheEntry).Node);
        node.data = entry;
        self.lru_list.prepend(node);
    }

    /// Invalidate cache entries overlapping with span
    pub fn invalidate(self: *Self, span: Span) void {
        var to_remove = std.ArrayList(u64).init(self.allocator);
        defer to_remove.deinit();

        var it = self.entries.iterator();
        while (it.next()) |entry| {
            const entry_span = entry.value_ptr.*.span;
            if (spansOverlap(span, entry_span)) {
                to_remove.append(entry.key_ptr.*) catch continue;
            }
        }

        for (to_remove.items) |hash| {
            if (self.entries.get(hash)) |entry| {
                self.removeEntry(entry);
            }
        }
    }

    /// Get cache statistics
    pub fn getStats(self: *Self) CacheStats {
        return .{
            .total_entries = self.entries.count(),
            .max_entries = self.max_entries,
            .hit_rate = if (self.total_hits + self.total_misses > 0)
                @as(f32, @floatFromInt(self.total_hits)) /
                    @as(f32, @floatFromInt(self.total_hits + self.total_misses))
            else
                0.0,
            .total_hits = self.total_hits,
            .total_misses = self.total_misses,
        };
    }

    fn moveToFront(self: *Self, entry: *CacheEntry) void {
        // Find node in LRU list
        var node = self.lru_list.first;
        while (node) |n| {
            if (n.data == entry) {
                self.lru_list.remove(n);
                self.lru_list.prepend(n);
                break;
            }
            node = n.next;
        }
    }

    fn evictLRU(self: *Self) void {
        if (self.lru_list.pop()) |node| {
            const entry = node.data;
            _ = self.entries.remove(self.hashEntry(entry));
            self.allocator.destroy(entry);
            self.allocator.destroy(node);
        }
    }

    fn removeEntry(self: *Self, entry: *CacheEntry) void {
        _ = self.entries.remove(self.hashEntry(entry));

        // Remove from LRU list
        var node = self.lru_list.first;
        while (node) |n| {
            if (n.data == entry) {
                self.lru_list.remove(n);
                self.allocator.destroy(n);
                break;
            }
            node = n.next;
        }

        self.allocator.destroy(entry);
    }

    fn hashEntry(self: *Self, entry: *CacheEntry) u64 {
        _ = self;
        return entry.hash;
    }

    fn spansOverlap(a: Span, b: Span) bool {
        return a.start < b.end and b.start < a.end;
    }
};

pub const CacheStats = struct {
    total_entries: usize,
    max_entries: usize,
    hit_rate: f32,
    total_hits: u64,
    total_misses: u64,
};

/// Hash tokens for cache key
pub fn hashTokens(tokens: []const Token) u64 {
    var hasher = std.hash.Wyhash.init(0);
    for (tokens) |token| {
        hasher.update(std.mem.asBytes(&token.kind));
        hasher.update(std.mem.asBytes(&token.span));
    }
    return hasher.final();
}
