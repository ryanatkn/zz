/// LexerRegistry - Central registry for language lexers
///
/// ⚠️ TEMPORARY MODULE - DELETE IN PHASE 4 ⚠️
/// This registry will be replaced by direct language imports when
/// all languages have native stream lexers.
///
/// TODO: Compile-time registration for zero-cost dispatch
/// TODO: Plugin system for custom languages (Phase 5)
/// TODO: Hot-reload support for development
/// TODO: Language auto-detection from content
const std = @import("std");
const Language = @import("../core/language.zig").Language;
const LexerBridge = @import("lexer_bridge.zig").LexerBridge;
const AtomTable = @import("../memory/atom_table.zig").AtomTable;

/// Registry for managing language lexers
pub const LexerRegistry = struct {
    allocator: std.mem.Allocator,
    atom_table: *AtomTable,
    bridges: std.EnumMap(Language, ?*LexerBridge),
    
    // TODO: Add cache for frequently used lexers
    // cache: LruCache(*LexerBridge, 8),
    
    // TODO: Add statistics for optimization
    stats: RegistryStats = .{},
    
    pub const RegistryStats = struct {
        lookups: u64 = 0,
        cache_hits: u64 = 0,
        cache_misses: u64 = 0,
        languages_registered: u8 = 0,
    };
    
    /// Initialize an empty registry
    pub fn init(allocator: std.mem.Allocator, atom_table: *AtomTable) LexerRegistry {
        return .{
            .allocator = allocator,
            .atom_table = atom_table,
            .bridges = std.EnumMap(Language, ?*LexerBridge).init(.{}),
        };
    }
    
    /// Clean up all registered lexers
    pub fn deinit(self: *LexerRegistry) void {
        var iter = self.bridges.iterator();
        while (iter.next()) |entry| {
            if (entry.value.*) |bridge| {
                bridge.deinit();
                self.allocator.destroy(bridge);
            }
        }
    }
    
    /// Register all default language lexers
    /// TODO: Make this compile-time with comptime loop
    pub fn registerDefaults(self: *LexerRegistry) !void {
        // Register implemented languages
        try self.registerLanguage(.json);
        try self.registerLanguage(.zon);
        
        // TODO: Register other languages as they're implemented
        // try self.registerLanguage(.typescript);
        // try self.registerLanguage(.zig);
        // try self.registerLanguage(.css);
        // try self.registerLanguage(.html);
        // try self.registerLanguage(.svelte);
    }
    
    /// Register a specific language
    pub fn registerLanguage(self: *LexerRegistry, language: Language) !void {
        // Check if already registered
        if (self.bridges.get(language) != null) {
            return;
        }
        
        // Create bridge for language
        const bridge = try self.allocator.create(LexerBridge);
        errdefer self.allocator.destroy(bridge);
        
        bridge.* = try LexerBridge.init(self.allocator, language, self.atom_table);
        self.bridges.put(language, bridge);
        self.stats.languages_registered += 1;
    }
    
    /// Get lexer for a language
    pub fn getLexer(self: *LexerRegistry, language: Language) ?*LexerBridge {
        self.stats.lookups += 1;
        
        // TODO: Check cache first
        // if (self.cache.get(language)) |bridge| {
        //     self.stats.cache_hits += 1;
        //     return bridge;
        // }
        
        if (self.bridges.get(language)) |bridge| {
            // TODO: Update cache
            // self.cache.put(language, bridge);
            return bridge;
        }
        
        self.stats.cache_misses += 1;
        return null;
    }
    
    /// Get lexer by file extension
    /// TODO: Make this table-driven for efficiency
    pub fn getLexerByExtension(self: *LexerRegistry, extension: []const u8) ?*LexerBridge {
        const language = detectLanguageFromExtension(extension) orelse return null;
        return self.getLexer(language);
    }
    
    /// Detect language from file extension
    /// TODO: Generate this at compile time from language definitions
    fn detectLanguageFromExtension(extension: []const u8) ?Language {
        // Normalize extension (remove leading dot if present)
        const ext = if (extension.len > 0 and extension[0] == '.')
            extension[1..]
        else
            extension;
        
        // Map extensions to languages
        // TODO: Use perfect hash or compile-time string map
        if (std.mem.eql(u8, ext, "json")) return .json;
        if (std.mem.eql(u8, ext, "zon")) return .zon;
        if (std.mem.eql(u8, ext, "ts") or std.mem.eql(u8, ext, "tsx")) return .typescript;
        if (std.mem.eql(u8, ext, "zig")) return .zig;
        if (std.mem.eql(u8, ext, "css")) return .css;
        if (std.mem.eql(u8, ext, "html") or std.mem.eql(u8, ext, "htm")) return .html;
        if (std.mem.eql(u8, ext, "svelte")) return .svelte;
        
        return null;
    }
    
    /// Detect language from content
    /// TODO: Implement content-based detection
    pub fn detectLanguageFromContent(self: *LexerRegistry, content: []const u8) ?Language {
        _ = self;
        _ = content;
        
        // TODO: Check for shebangs (#!)
        // TODO: Check for distinctive patterns (<!DOCTYPE, <?xml, etc.)
        // TODO: Use statistical analysis for ambiguous cases
        
        return null;
    }
    
    /// Get statistics about registry usage
    pub fn getStats(self: *const LexerRegistry) RegistryStats {
        return self.stats;
    }
};

/// Global registry instance
/// TODO: Consider thread-local registries for parallelism
var global_registry: ?*LexerRegistry = null;

/// Initialize global registry
pub fn initGlobal(allocator: std.mem.Allocator, atom_table: *AtomTable) !void {
    if (global_registry != null) return;
    
    const registry = try allocator.create(LexerRegistry);
    registry.* = LexerRegistry.init(allocator, atom_table);
    try registry.registerDefaults();
    
    global_registry = registry;
}

/// Deinitialize global registry
pub fn deinitGlobal() void {
    if (global_registry) |registry| {
        registry.deinit();
        registry.allocator.destroy(registry);
        global_registry = null;
    }
}

/// Get global registry
pub fn getGlobal() ?*LexerRegistry {
    return global_registry;
}

test "LexerRegistry basic operations" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    // Create atom table
    var atom_table = AtomTable.init(allocator);
    defer atom_table.deinit();
    
    // Create registry
    var registry = LexerRegistry.init(allocator, &atom_table);
    defer registry.deinit();
    
    // Register defaults
    try registry.registerDefaults();
    
    // Get JSON lexer
    const json_lexer = registry.getLexer(.json);
    try testing.expect(json_lexer != null);
    
    // Get ZON lexer
    const zon_lexer = registry.getLexer(.zon);
    try testing.expect(zon_lexer != null);
    
    // Try to get unregistered language
    const ts_lexer = registry.getLexer(.typescript);
    try testing.expect(ts_lexer == null);
    
    // Test extension detection
    const json_by_ext = registry.getLexerByExtension(".json");
    try testing.expect(json_by_ext != null);
    
    const json_by_ext2 = registry.getLexerByExtension("json");
    try testing.expect(json_by_ext2 != null);
    
    // Check statistics
    const stats = registry.getStats();
    try testing.expect(stats.lookups > 0);
    try testing.expect(stats.languages_registered >= 2);
    
    // TODO: Test content-based detection
    // TODO: Test cache behavior
    // TODO: Test concurrent access
}