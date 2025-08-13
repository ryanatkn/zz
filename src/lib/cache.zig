const std = @import("std");
const ts = @import("tree-sitter");

/// Reference to a cached AST node
pub const AstCacheKey = struct {
    file_hash: u64,
    parser_version: u32,
    extraction_flags_hash: u64,
    
    pub fn init(file_hash: u64, parser_version: u32, extraction_flags_hash: u64) AstCacheKey {
        return AstCacheKey{
            .file_hash = file_hash,
            .parser_version = parser_version,
            .extraction_flags_hash = extraction_flags_hash,
        };
    }

    pub fn eql(self: AstCacheKey, other: AstCacheKey) bool {
        return self.file_hash == other.file_hash and
               self.parser_version == other.parser_version and
               self.extraction_flags_hash == other.extraction_flags_hash;
    }

    pub fn hash(self: AstCacheKey) u64 {
        var hasher = std.hash.XxHash64.init(0);
        hasher.update(std.mem.asBytes(&self.file_hash));
        hasher.update(std.mem.asBytes(&self.parser_version));
        hasher.update(std.mem.asBytes(&self.extraction_flags_hash));
        return hasher.final();
    }
};

/// Cached extraction result
pub const CachedExtraction = struct {
    content: []const u8,
    created_at: i64,
    access_count: u32,
    last_accessed: i64,
    
    pub fn deinit(self: *CachedExtraction, allocator: std.mem.Allocator) void {
        allocator.free(self.content);
    }
};

/// LRU cache for AST extractions
pub const AstCache = struct {
    allocator: std.mem.Allocator,
    cache: std.HashMap(AstCacheKey, CachedExtraction, AstCacheKeyContext, 80),
    max_entries: usize,
    max_memory_bytes: usize,
    current_memory_bytes: usize,
    stats: CacheStats,

    const AstCacheKeyContext = struct {
        pub fn hash(self: @This(), key: AstCacheKey) u64 {
            _ = self;
            return key.hash();
        }
        
        pub fn eql(self: @This(), a: AstCacheKey, b: AstCacheKey) bool {
            _ = self;
            return a.eql(b);
        }
    };

    pub const CacheStats = struct {
        hits: u64 = 0,
        misses: u64 = 0,
        evictions: u64 = 0,
        memory_pressure_evictions: u64 = 0,
        
        pub fn hitRate(self: CacheStats) f64 {
            const total = self.hits + self.misses;
            if (total == 0) return 0.0;
            return @as(f64, @floatFromInt(self.hits)) / @as(f64, @floatFromInt(total));
        }
        
        pub fn efficiency(self: CacheStats) f64 {
            return self.hitRate() * 100.0;
        }
    };

    pub fn init(allocator: std.mem.Allocator, max_entries: usize, max_memory_mb: usize) AstCache {
        return AstCache{
            .allocator = allocator,
            .cache = std.HashMap(AstCacheKey, CachedExtraction, AstCacheKeyContext, 80).init(allocator),
            .max_entries = max_entries,
            .max_memory_bytes = max_memory_mb * 1024 * 1024,
            .current_memory_bytes = 0,
            .stats = CacheStats{},
        };
    }

    pub fn deinit(self: *AstCache) void {
        var iter = self.cache.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.cache.deinit();
    }

    /// Get cached extraction if available
    pub fn get(self: *AstCache, key: AstCacheKey) ?[]const u8 {
        const now = @as(i64, @intCast(std.time.nanoTimestamp()));
        
        if (self.cache.getPtr(key)) |cached| {
            self.stats.hits += 1;
            cached.access_count += 1;
            cached.last_accessed = now;
            return cached.content;
        } else {
            self.stats.misses += 1;
            return null;
        }
    }

    /// Put extraction result in cache
    pub fn put(self: *AstCache, key: AstCacheKey, content: []const u8) !void {
        const now = @as(i64, @intCast(std.time.nanoTimestamp()));
        const content_size = content.len;
        
        // Make room if needed
        try self.makeRoom(content_size);
        
        // Clone content for cache storage
        const cached_content = try self.allocator.dupe(u8, content);
        
        const cached = CachedExtraction{
            .content = cached_content,
            .created_at = now,
            .access_count = 1,
            .last_accessed = now,
        };

        // If key already exists, free old content
        if (self.cache.getPtr(key)) |existing| {
            self.current_memory_bytes -= existing.content.len;
            existing.deinit(self.allocator);
        }

        try self.cache.put(key, cached);
        self.current_memory_bytes += content_size;
    }

    /// Make room in cache by evicting least recently used entries
    fn makeRoom(self: *AstCache, needed_bytes: usize) !void {
        // Check if we need to evict for count limit
        while (self.cache.count() >= self.max_entries) {
            try self.evictLru();
            self.stats.evictions += 1;
        }
        
        // Check if we need to evict for memory limit
        while (self.current_memory_bytes + needed_bytes > self.max_memory_bytes and self.cache.count() > 0) {
            try self.evictLru();
            self.stats.memory_pressure_evictions += 1;
        }
    }

    /// Evict least recently used entry
    fn evictLru(self: *AstCache) !void {
        var oldest_key: ?AstCacheKey = null;
        var oldest_time: i64 = std.math.maxInt(i64);

        var iter = self.cache.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.last_accessed < oldest_time) {
                oldest_time = entry.value_ptr.last_accessed;
                oldest_key = entry.key_ptr.*;
            }
        }

        if (oldest_key) |key| {
            if (self.cache.fetchRemove(key)) |removed| {
                self.current_memory_bytes -= removed.value.content.len;
                var mutable_value = removed.value;
                mutable_value.deinit(self.allocator);
            }
        }
    }

    pub fn getStats(self: *AstCache) CacheStats {
        return self.stats;
    }

    pub fn getCurrentMemoryMB(self: *AstCache) f64 {
        return @as(f64, @floatFromInt(self.current_memory_bytes)) / (1024.0 * 1024.0);
    }
};

/// Parser instance for language-specific parsing
pub const ParserInstance = struct {
    language: []const u8,
    parser: ?*ts.Parser,
    version: u32,
    created_at: i64,
    last_used: i64,
    usage_count: u32,
    
    pub fn init(language: []const u8, version: u32) ParserInstance {
        const now = @as(i64, @intCast(std.time.nanoTimestamp()));
        return ParserInstance{
            .language = language,
            .parser = null,
            .version = version,
            .created_at = now,
            .last_used = now,
            .usage_count = 0,
        };
    }

    pub fn deinit(self: *ParserInstance, allocator: std.mem.Allocator) void {
        if (self.parser) |parser| {
            _ = parser; // TODO: Use actual tree-sitter when integrated
            // ts.ts_parser_delete(parser);
        }
        allocator.free(self.language);
    }

    pub fn use(self: *ParserInstance) void {
        self.last_used = @as(i64, @intCast(std.time.nanoTimestamp()));
        self.usage_count += 1;
    }
};

/// Cache for parser instances to avoid re-initialization
pub const ParserCache = struct {
    allocator: std.mem.Allocator,
    parsers: std.HashMap([]const u8, ParserInstance, std.hash_map.StringContext, 80),
    max_parsers: usize,
    stats: ParserCacheStats,

    pub const ParserCacheStats = struct {
        hits: u64 = 0,
        misses: u64 = 0,
        initializations: u64 = 0,
        evictions: u64 = 0,

        pub fn hitRate(self: ParserCacheStats) f64 {
            const total = self.hits + self.misses;
            if (total == 0) return 0.0;
            return @as(f64, @floatFromInt(self.hits)) / @as(f64, @floatFromInt(total));
        }
    };

    pub fn init(allocator: std.mem.Allocator, max_parsers: usize) ParserCache {
        return ParserCache{
            .allocator = allocator,
            .parsers = std.HashMap([]const u8, ParserInstance, std.hash_map.StringContext, 80).init(allocator),
            .max_parsers = max_parsers,
            .stats = ParserCacheStats{},
        };
    }

    pub fn deinit(self: *ParserCache) void {
        var iter = self.parsers.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.parsers.deinit();
    }

    /// Get or create a parser for the given language
    pub fn getParser(self: *ParserCache, language: []const u8) !?*ParserInstance {
        if (self.parsers.getPtr(language)) |parser| {
            self.stats.hits += 1;
            parser.use();
            return parser;
        } else {
            self.stats.misses += 1;
            return try self.createParser(language);
        }
    }

    /// Create a new parser instance for the language
    fn createParser(self: *ParserCache, language: []const u8) !?*ParserInstance {
        // Make room if needed
        try self.makeRoom();
        
        const language_key = try self.allocator.dupe(u8, language);
        const parser_instance = ParserInstance.init(language_key, 1);
        
        // TODO: Initialize actual tree-sitter parser based on language
        // For now, we just track the metadata
        
        try self.parsers.put(language_key, parser_instance);
        self.stats.initializations += 1;
        
        return self.parsers.getPtr(language_key);
    }

    /// Make room by evicting least recently used parser
    fn makeRoom(self: *ParserCache) !void {
        if (self.parsers.count() >= self.max_parsers) {
            try self.evictLru();
            self.stats.evictions += 1;
        }
    }

    /// Evict least recently used parser
    fn evictLru(self: *ParserCache) !void {
        var oldest_key: ?[]const u8 = null;
        var oldest_time: i64 = std.math.maxInt(i64);

        var iter = self.parsers.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.last_used < oldest_time) {
                oldest_time = entry.value_ptr.last_used;
                oldest_key = entry.key_ptr.*;
            }
        }

        if (oldest_key) |key| {
            if (self.parsers.fetchRemove(key)) |removed| {
                var mutable_value = removed.value;
                mutable_value.deinit(self.allocator);
            }
        }
    }

    pub fn getStats(self: *ParserCache) ParserCacheStats {
        return self.stats;
    }
};

/// Combined cache system for parsers and AST extractions
pub const CacheSystem = struct {
    allocator: std.mem.Allocator,
    parser_cache: ParserCache,
    ast_cache: AstCache,
    
    pub fn init(allocator: std.mem.Allocator) CacheSystem {
        return CacheSystem{
            .allocator = allocator,
            .parser_cache = ParserCache.init(allocator, 16), // Max 16 parsers
            .ast_cache = AstCache.init(allocator, 1000, 100), // Max 1000 entries, 100MB
        };
    }
    
    pub fn deinit(self: *CacheSystem) void {
        self.parser_cache.deinit();
        self.ast_cache.deinit();
    }
    
    pub fn getParserStats(self: *CacheSystem) ParserCache.ParserCacheStats {
        return self.parser_cache.getStats();
    }
    
    pub fn getAstStats(self: *CacheSystem) AstCache.CacheStats {
        return self.ast_cache.getStats();
    }
    
    /// Get cached extraction or compute if missing
    pub fn getOrComputeExtraction(
        self: *CacheSystem, 
        key: AstCacheKey, 
        compute_fn: *const fn(allocator: std.mem.Allocator) anyerror![]const u8
    ) ![]const u8 {
        // Try cache first
        if (self.ast_cache.get(key)) |cached| {
            return cached;
        }
        
        // Compute and cache result
        const result = try compute_fn(self.allocator);
        try self.ast_cache.put(key, result);
        return result;
    }
};

// Tests
test "ast cache basic operations" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var cache = AstCache.init(allocator, 10, 1); // 10 entries, 1MB
    defer cache.deinit();

    const key = AstCacheKey.init(123, 1, 456);
    const content = "test extraction result";

    // Test miss
    try testing.expect(cache.get(key) == null);
    try testing.expect(cache.getStats().misses == 1);

    // Test put and hit
    try cache.put(key, content);
    const cached = cache.get(key);
    try testing.expect(cached != null);
    try testing.expect(std.mem.eql(u8, cached.?, content));
    try testing.expect(cache.getStats().hits == 1);
}

test "parser cache basic operations" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var cache = ParserCache.init(allocator, 5);
    defer cache.deinit();

    // Test miss and creation
    const parser = try cache.getParser("zig");
    try testing.expect(parser != null);
    try testing.expect(cache.getStats().misses == 1);
    try testing.expect(cache.getStats().initializations == 1);

    // Test hit
    const parser2 = try cache.getParser("zig");
    try testing.expect(parser2 != null);
    try testing.expect(cache.getStats().hits == 1);
}

test "cache system integration" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var system = CacheSystem.init(allocator);
    defer system.deinit();

    const parser_stats = system.getParserStats();
    const ast_stats = system.getAstStats();
    
    try testing.expect(parser_stats.hits == 0);
    try testing.expect(ast_stats.hits == 0);
}