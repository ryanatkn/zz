const std = @import("std");
const FormatterOptions = @import("formatter.zig").FormatterOptions;

/// Legacy cached formatter compatibility stub - delegates to stratified parser
pub const CachedFormatterManager = struct {
    allocator: std.mem.Allocator,
    cache: std.StringHashMap([]u8),

    pub fn init(allocator: std.mem.Allocator) CachedFormatterManager {
        return CachedFormatterManager{
            .allocator = allocator,
            .cache = std.StringHashMap([]u8).init(allocator),
        };
    }

    pub fn deinit(self: *CachedFormatterManager) void {
        var iterator = self.cache.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.cache.deinit();
    }

    /// Format with caching (stub implementation)
    pub fn formatCached(self: *CachedFormatterManager, key: []const u8, content: []const u8, options: FormatterOptions) ![]u8 {
        _ = options;

        if (self.cache.get(key)) |cached| {
            return try self.allocator.dupe(u8, cached);
        }

        // For now, just store and return the content
        // In the future, this would use the stratified parser for formatting
        const result = try self.allocator.dupe(u8, content);
        const owned_key = try self.allocator.dupe(u8, key);
        const cached_result = try self.allocator.dupe(u8, result);

        try self.cache.put(owned_key, cached_result);
        return result;
    }

    /// Clear the cache
    pub fn clearCache(self: *CachedFormatterManager) void {
        var iterator = self.cache.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.cache.clearAndFree();
    }
};
