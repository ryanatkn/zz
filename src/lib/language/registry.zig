const std = @import("std");
const ts = @import("tree-sitter");
const Language = @import("detection.zig").Language;
const ExtractionFlags = @import("flags.zig").ExtractionFlags;
const Node = @import("../tree_sitter/node.zig").Node;
const ExtractionContext = @import("../tree_sitter/visitor.zig").ExtractionContext;
const FormatterOptions = @import("../parsing/formatter.zig").FormatterOptions;
const TreeSitterParser = @import("../tree_sitter/parser.zig").TreeSitterParser;
const AstCache = @import("../analysis/cache.zig").AstCache;
const AstCacheKey = @import("../analysis/cache.zig").AstCacheKey;

// Language implementations - import individual modules directly
// JSON
const json_formatter = @import("../languages/json/formatter.zig");
const json_grammar = @import("../languages/json/grammar.zig");
const json_visitor = @import("../languages/json/visitor.zig");

// TypeScript
const ts_formatter = @import("../languages/typescript/formatter.zig");
const ts_grammar = @import("../languages/typescript/grammar.zig");
const ts_visitor = @import("../languages/typescript/visitor.zig");

// CSS
const css_formatter = @import("../languages/css/formatter.zig");
const css_grammar = @import("../languages/css/grammar.zig");
const css_visitor = @import("../languages/css/visitor.zig");

// HTML
const html_formatter = @import("../languages/html/formatter.zig");
const html_grammar = @import("../languages/html/grammar.zig");
const html_visitor = @import("../languages/html/visitor.zig");

// Zig
const zig_formatter = @import("../languages/zig/formatter.zig");
const zig_grammar = @import("../languages/zig/grammar.zig");
const zig_visitor = @import("../languages/zig/visitor.zig");

// Svelte
const svelte_formatter = @import("../languages/svelte/formatter.zig");
const svelte_grammar = @import("../languages/svelte/grammar.zig");
const svelte_visitor = @import("../languages/svelte/visitor.zig");

/// Language implementation interface
pub const LanguageImpl = struct {
    /// Language name for debugging/logging
    name: []const u8,

    /// Get tree-sitter grammar
    grammar: *const fn () *ts.Language,


    /// AST visitor function - returns true to continue recursion, false to skip children
    visitor: *const fn (context: *ExtractionContext, node: *const Node) anyerror!bool,

    /// Format source code
    format: *const fn (allocator: std.mem.Allocator, source: []const u8, options: FormatterOptions) anyerror![]const u8,
};

/// Language registry for managing all supported languages
pub const LanguageRegistry = struct {
    implementations: std.HashMap(Language, LanguageImpl, std.hash_map.AutoContext(Language), std.hash_map.default_max_load_percentage),
    tree_sitter_parser: TreeSitterParser,
    ast_cache: ?*AstCache,

    pub fn init(allocator: std.mem.Allocator) LanguageRegistry {
        var registry = LanguageRegistry{
            .implementations = std.HashMap(Language, LanguageImpl, std.hash_map.AutoContext(Language), std.hash_map.default_max_load_percentage).init(allocator),
            .tree_sitter_parser = TreeSitterParser.init(allocator),
            .ast_cache = null,
        };

        // Register built-in languages
        registry.registerBuiltinLanguages() catch unreachable;

        return registry;
    }

    pub fn deinit(self: *LanguageRegistry) void {
        self.implementations.deinit();
        self.tree_sitter_parser.deinit();
    }

    /// Register all built-in language implementations
    fn registerBuiltinLanguages(self: *LanguageRegistry) !void {
        // JSON
        try self.implementations.put(Language.json, LanguageImpl{
            .name = "json",
            .grammar = json_grammar.grammar,
            .visitor = json_visitor.visitor,
            .format = json_formatter.format,
        });

        // TypeScript (and JavaScript)
        try self.implementations.put(Language.typescript, LanguageImpl{
            .name = "typescript",
            .grammar = ts_grammar.grammar,
            .visitor = ts_visitor.visitor,
            .format = ts_formatter.format,
        });

        // CSS
        try self.implementations.put(Language.css, LanguageImpl{
            .name = "css",
            .grammar = css_grammar.grammar,
            .visitor = css_visitor.visitor,
            .format = css_formatter.format,
        });

        // HTML
        try self.implementations.put(Language.html, LanguageImpl{
            .name = "html",
            .grammar = html_grammar.grammar,
            .visitor = html_visitor.visitor,
            .format = html_formatter.format,
        });

        // Zig
        try self.implementations.put(Language.zig, LanguageImpl{
            .name = "zig",
            .grammar = zig_grammar.grammar,
            .visitor = zig_visitor.visitor,
            .format = zig_formatter.format,
        });

        // Svelte
        try self.implementations.put(Language.svelte, LanguageImpl{
            .name = "svelte",
            .grammar = svelte_grammar.grammar,
            .visitor = svelte_visitor.visitor,
            .format = svelte_formatter.format,
        });
    }

    /// Get language implementation
    pub fn getLanguage(self: *LanguageRegistry, language: Language) ?LanguageImpl {
        return self.implementations.get(language);
    }

    /// Check if language is supported
    pub fn isSupported(self: *LanguageRegistry, language: Language) bool {
        return self.implementations.contains(language);
    }

    /// Set AST cache for performance optimization  
    pub fn setAstCache(self: *LanguageRegistry, ast_cache: *AstCache) void {
        self.ast_cache = ast_cache;
    }
    
    /// Get AST cache statistics
    pub fn getAstCacheStats(self: *LanguageRegistry) ?AstCache.CacheStats {
        if (self.ast_cache) |cache| {
            return cache.getStats();
        }
        return null;
    }
    
    /// Generate cache key for extraction request
    fn generateCacheKey(source: []const u8, flags: ExtractionFlags) AstCacheKey {
        // Hash the source content
        var file_hasher = std.hash.XxHash64.init(0);
        file_hasher.update(source);
        const file_hash = file_hasher.final();
        
        // Hash the extraction flags
        var flags_hasher = std.hash.XxHash64.init(0);
        flags_hasher.update(std.mem.asBytes(&flags));
        const flags_hash = flags_hasher.final();
        
        return AstCacheKey.init(file_hash, 1, flags_hash); // parser version = 1
    }


    /// Extract code using tree-sitter AST with optional caching
    pub fn extract(
        self: *LanguageRegistry,
        allocator: std.mem.Allocator,
        language: Language,
        source: []const u8,
        flags: ExtractionFlags,
        result: *std.ArrayList(u8),
    ) !void {
        const lang_impl = self.getLanguage(language) orelse {
            // For unsupported languages, return full source if requested
            if (flags.full) {
                try result.appendSlice(source);
            }
            return;
        };

        // Try AST cache first if available
        if (self.ast_cache) |cache| {
            const cache_key = generateCacheKey(source, flags);
            if (cache.get(cache_key)) |cached_result| {
                try result.appendSlice(cached_result);
                std.log.debug("AST cache hit: {} bytes retrieved", .{cached_result.len});
                return;
            }
            std.log.debug("AST cache miss: computing fresh extraction", .{});
        }

        // Parse with tree-sitter
        var parse_result = self.tree_sitter_parser.parse(source, language) catch |err| {
            std.log.debug("Tree-sitter parsing failed for {s}: {}", .{ @tagName(language), err });
            return err;
        };
        defer parse_result.deinit();

        // Record starting length to capture what we extract
        const start_len = result.items.len;

        // Use visitor to extract
        var context = ExtractionContext{
            .allocator = allocator,
            .result = result,
            .flags = flags,
            .source = source,
        };

        try self.walkAST(&context, &parse_result.root_node, lang_impl.visitor);

        // Cache the result if cache is available
        if (self.ast_cache) |cache| {
            const extracted_content = result.items[start_len..];
            if (extracted_content.len > 0) {
                const cache_key = generateCacheKey(source, flags);
                cache.put(cache_key, extracted_content) catch |err| {
                    std.log.debug("Failed to cache AST result: {}", .{err});
                    // Don't fail the extraction due to cache issues
                };
                std.log.debug("AST cache store: {} bytes cached", .{extracted_content.len});
            }
        }
    }

    /// Walk AST with visitor - visitor controls recursion
    fn walkAST(
        self: *LanguageRegistry,
        context: *ExtractionContext,
        node: *const Node,
        visitor_fn: *const fn (context: *ExtractionContext, node: *const Node) anyerror!bool,
    ) !void {
        // Visit current node - visitor returns true to continue recursion
        const should_recurse = try visitor_fn(context, node);

        // Only recurse into children if visitor requests it
        if (should_recurse) {
            const count = node.childCount();
            var i: u32 = 0;
            while (i < count) : (i += 1) {
                if (node.child(i, context.source)) |child| {
                    var child_node = child;
                    try self.walkAST(context, &child_node, visitor_fn);
                }
            }
        }
    }

    /// Format source code using the appropriate language implementation
    pub fn format(
        self: *LanguageRegistry,
        allocator: std.mem.Allocator,
        language: Language,
        source: []const u8,
        options: FormatterOptions,
    ) ![]const u8 {
        if (self.getLanguage(language)) |lang_impl| {
            return lang_impl.format(allocator, source, options);
        } else {
            // Fallback: return original source for unsupported languages
            return allocator.dupe(u8, source);
        }
    }

    /// Get list of all supported languages
    pub fn getSupportedLanguages(self: *LanguageRegistry, allocator: std.mem.Allocator) ![]Language {
        var languages = std.ArrayList(Language).init(allocator);
        var iterator = self.implementations.keyIterator();
        while (iterator.next()) |language| {
            try languages.append(language.*);
        }
        return languages.toOwnedSlice();
    }

    /// Get language implementation info for debugging
    pub fn getLanguageInfo(self: *LanguageRegistry, language: Language) ?LanguageInfo {
        if (self.getLanguage(language)) |lang_impl| {
            return LanguageInfo{
                .language = language,
                .name = lang_impl.name,
                .has_grammar = true,
                .supports_formatting = true,
                .supports_ast_extraction = true,
            };
        }
        return null;
    }
};

/// Information about a language implementation
pub const LanguageInfo = struct {
    language: Language,
    name: []const u8,
    has_grammar: bool,
    supports_formatting: bool,
    supports_ast_extraction: bool,
};

/// Global language registry instance
var global_registry: ?LanguageRegistry = null;
var registry_mutex: std.Thread.Mutex = std.Thread.Mutex{};
var registry_allocator: ?std.mem.Allocator = null;

/// Get the global language registry (thread-safe singleton)
pub fn getGlobalRegistry(allocator: std.mem.Allocator) *LanguageRegistry {
    registry_mutex.lock();
    defer registry_mutex.unlock();

    if (global_registry == null) {
        global_registry = LanguageRegistry.init(allocator);
        registry_allocator = allocator;
    }

    return &global_registry.?;
}

/// Cleanup the global registry (call at program exit)
pub fn deinitGlobalRegistry() void {
    registry_mutex.lock();
    defer registry_mutex.unlock();

    if (global_registry) |*registry| {
        registry.deinit();
        global_registry = null;
        registry_allocator = null;
    }
}

/// Test-safe registry cleanup (for test environments)
pub fn cleanupGlobalRegistry() void {
    deinitGlobalRegistry();
}

// Tests
test "LanguageRegistry basic operations" {
    const allocator = std.testing.allocator;
    var registry = LanguageRegistry.init(allocator);
    defer registry.deinit();

    // Test language support
    try std.testing.expect(registry.isSupported(Language.json));
    try std.testing.expect(registry.isSupported(Language.typescript));
    try std.testing.expect(registry.isSupported(Language.zig)); // Now implemented
    try std.testing.expect(registry.isSupported(Language.html)); // Now implemented
    try std.testing.expect(registry.isSupported(Language.svelte)); // Now implemented

    // Test language info
    const json_info = registry.getLanguageInfo(Language.json).?;
    try std.testing.expect(std.mem.eql(u8, json_info.name, "json"));
    try std.testing.expect(json_info.has_grammar);
}

test "LanguageRegistry extraction" {
    const allocator = std.testing.allocator;
    var registry = LanguageRegistry.init(allocator);
    defer registry.deinit();

    const json_source = "{\"key\": \"value\"}";
    const flags = ExtractionFlags{ .full = true };

    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    try registry.extract(allocator, Language.json, json_source, flags, &result);
    try std.testing.expect(std.mem.eql(u8, result.items, json_source));
}

test "LanguageRegistry AST cache functionality" {
    const allocator = std.testing.allocator;
    
    var registry = LanguageRegistry.init(allocator);
    defer registry.deinit();
    
    var ast_cache = AstCache.init(allocator, 10, 1); // 10 entries, 1MB
    defer ast_cache.deinit();
    
    // Enable AST caching
    registry.setAstCache(&ast_cache);
    
    const svelte_source = 
        \\<script>
        \\    export let name = 'World';
        \\    function greet() {
        \\        console.log('Hello ' + name);
        \\    }
        \\</script>
        \\<div>Hello {name}!</div>
    ;
    
    const flags = ExtractionFlags{ .signatures = true };

    // First extraction - should be a cache miss
    var result1 = std.ArrayList(u8).init(allocator);
    defer result1.deinit();
    
    try registry.extract(allocator, Language.svelte, svelte_source, flags, &result1);
    try std.testing.expect(result1.items.len > 0);
    
    // Verify cache stats - should have 1 miss
    const stats1 = registry.getAstCacheStats().?;
    try std.testing.expect(stats1.misses == 1);
    try std.testing.expect(stats1.hits == 0);

    // Second extraction with same source and flags - should be a cache hit
    var result2 = std.ArrayList(u8).init(allocator);
    defer result2.deinit();
    
    try registry.extract(allocator, Language.svelte, svelte_source, flags, &result2);
    try std.testing.expect(result2.items.len > 0);
    
    // Verify cache stats - should have 1 miss, 1 hit
    const stats2 = registry.getAstCacheStats().?;
    try std.testing.expect(stats2.misses == 1);
    try std.testing.expect(stats2.hits == 1);
    
    // Results should be identical
    try std.testing.expect(std.mem.eql(u8, result1.items, result2.items));
    
    // Third extraction with different flags - should be another cache miss
    var result3 = std.ArrayList(u8).init(allocator);
    defer result3.deinit();
    
    const structure_flags = ExtractionFlags{ .structure = true };
    try registry.extract(allocator, Language.svelte, svelte_source, structure_flags, &result3);
    try std.testing.expect(result3.items.len > 0);
    
    // Verify cache stats - should have 2 misses, 1 hit
    const stats3 = registry.getAstCacheStats().?;
    try std.testing.expect(stats3.misses == 2);
    try std.testing.expect(stats3.hits == 1);
    
    // Fourth extraction with same flags as second - should be cache hit
    var result4 = std.ArrayList(u8).init(allocator);
    defer result4.deinit();
    
    try registry.extract(allocator, Language.svelte, svelte_source, flags, &result4);
    
    // Verify cache stats - should have 2 misses, 2 hits
    const stats4 = registry.getAstCacheStats().?;
    try std.testing.expect(stats4.misses == 2);
    try std.testing.expect(stats4.hits == 2);
    try std.testing.expect(stats4.efficiency() == 50.0); // 50% hit rate
}
