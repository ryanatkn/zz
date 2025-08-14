const std = @import("std");
const ts = @import("tree-sitter");
const Language = @import("detection.zig").Language;
const ExtractionFlags = @import("flags.zig").ExtractionFlags;
const Node = @import("../tree_sitter/node.zig").Node;
const ExtractionContext = @import("../tree_sitter/visitor.zig").ExtractionContext;
const FormatterOptions = @import("../parsing/formatter.zig").FormatterOptions;
const TreeSitterParser = @import("../tree_sitter/parser.zig").TreeSitterParser;

// Language implementations
const JsonLanguage = @import("../languages/json/main.zig").JsonLanguage;
const TypeScriptLanguage = @import("../languages/typescript.zig").TypeScriptLanguage;
const CssLanguage = @import("../languages/css/main.zig").CssLanguage;
const HtmlLanguage = @import("../languages/html/main.zig").HtmlLanguage;
const ZigLanguage = @import("../languages/zig.zig").ZigLanguage;
const SvelteLanguage = @import("../languages/svelte.zig").SvelteLanguage;

/// Language implementation interface
pub const LanguageImpl = struct {
    /// Language name for debugging/logging
    name: []const u8,
    
    /// Get tree-sitter grammar
    grammar: *const fn() *ts.Language,
    
    /// Extract code using patterns or AST
    extract: *const fn(allocator: std.mem.Allocator, source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) anyerror!void,
    
    /// AST visitor function
    visitor: *const fn(context: *ExtractionContext, node: *const Node) anyerror!void,
    
    /// Format source code
    format: *const fn(allocator: std.mem.Allocator, source: []const u8, options: FormatterOptions) anyerror![]const u8,
};

/// Language registry for managing all supported languages
pub const LanguageRegistry = struct {
    implementations: std.HashMap(Language, LanguageImpl, std.hash_map.AutoContext(Language), std.hash_map.default_max_load_percentage),
    tree_sitter_parser: TreeSitterParser,

    pub fn init(allocator: std.mem.Allocator) LanguageRegistry {
        var registry = LanguageRegistry{
            .implementations = std.HashMap(Language, LanguageImpl, std.hash_map.AutoContext(Language), std.hash_map.default_max_load_percentage).init(allocator),
            .tree_sitter_parser = TreeSitterParser.init(allocator),
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
            .name = JsonLanguage.language_name,
            .grammar = JsonLanguage.grammar,
            .extract = JsonLanguage.extract,
            .visitor = JsonLanguage.visitor,
            .format = JsonLanguage.format,
        });

        // TypeScript (and JavaScript)
        const ts_impl = LanguageImpl{
            .name = TypeScriptLanguage.language_name,
            .grammar = TypeScriptLanguage.grammar,
            .extract = TypeScriptLanguage.extract,
            .visitor = TypeScriptLanguage.visitor,
            .format = TypeScriptLanguage.format,
        };
        try self.implementations.put(Language.typescript, ts_impl);

        // CSS
        try self.implementations.put(Language.css, LanguageImpl{
            .name = CssLanguage.language_name,
            .grammar = CssLanguage.grammar,
            .extract = CssLanguage.extract,
            .visitor = CssLanguage.visitor,
            .format = CssLanguage.format,
        });

        // HTML
        try self.implementations.put(Language.html, LanguageImpl{
            .name = HtmlLanguage.language_name,
            .grammar = HtmlLanguage.grammar,
            .extract = HtmlLanguage.extract,
            .visitor = HtmlLanguage.visitor,
            .format = HtmlLanguage.format,
        });

        // Zig
        try self.implementations.put(Language.zig, LanguageImpl{
            .name = ZigLanguage.language_name,
            .grammar = ZigLanguage.grammar,
            .extract = ZigLanguage.extract,
            .visitor = ZigLanguage.visitor,
            .format = ZigLanguage.format,
        });

        // Svelte
        try self.implementations.put(Language.svelte, LanguageImpl{
            .name = SvelteLanguage.language_name,
            .grammar = SvelteLanguage.grammar,
            .extract = SvelteLanguage.extract,
            .visitor = SvelteLanguage.visitor,
            .format = SvelteLanguage.format,
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

    /// Extract code using the appropriate language implementation
    pub fn extract(
        self: *LanguageRegistry,
        allocator: std.mem.Allocator,
        language: Language,
        source: []const u8,
        flags: ExtractionFlags,
        result: *std.ArrayList(u8),
    ) !void {
        if (self.getLanguage(language)) |lang_impl| {
            try lang_impl.extract(allocator, source, flags, result);
        } else {
            // Fallback: return full source for unsupported languages
            if (flags.full) {
                try result.appendSlice(source);
            }
        }
    }

    /// Extract using tree-sitter AST
    pub fn extractWithAST(
        self: *LanguageRegistry,
        allocator: std.mem.Allocator,
        language: Language,
        source: []const u8,
        flags: ExtractionFlags,
        result: *std.ArrayList(u8),
    ) !void {
        const lang_impl = self.getLanguage(language) orelse {
            return self.extract(allocator, language, source, flags, result);
        };

        // Parse with tree-sitter
        var parse_result = self.tree_sitter_parser.parse(source, language) catch {
            // Fallback to pattern-based extraction
            return self.extract(allocator, language, source, flags, result);
        };
        defer parse_result.deinit();

        // Use visitor to extract
        var context = ExtractionContext{
            .allocator = allocator,
            .result = result,
            .flags = flags,
            .source = source,
        };

        try self.walkAST(&context, &parse_result.root_node, lang_impl.visitor);
    }

    /// Walk AST with visitor
    fn walkAST(
        self: *LanguageRegistry,
        context: *ExtractionContext,
        node: *const Node,
        visitor_fn: *const fn(context: *ExtractionContext, node: *const Node) anyerror!void,
    ) !void {
        // Visit current node
        try visitor_fn(context, node);

        // Recurse into children
        const count = node.childCount();
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            if (node.child(i, context.source)) |child| {
                var child_node = child;
                try self.walkAST(context, &child_node, visitor_fn);
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

/// Get the global language registry (thread-safe singleton)
pub fn getGlobalRegistry(allocator: std.mem.Allocator) *LanguageRegistry {
    registry_mutex.lock();
    defer registry_mutex.unlock();
    
    if (global_registry == null) {
        global_registry = LanguageRegistry.init(allocator);
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
    }
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