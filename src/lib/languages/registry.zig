const std = @import("std");
const Language = @import("../core/language.zig").Language;

// Import all interface types from single module
const lang_interface = @import("interface.zig");
const Lexer = lang_interface.Lexer;
const Parser = lang_interface.Parser;
const Formatter = lang_interface.Formatter;
const Linter = lang_interface.Linter;
const Analyzer = lang_interface.Analyzer;

// Import language-specific AST types and Rule types
const JsonAST = @import("json/ast.zig").AST;
const ZonAST = @import("zon/ast.zig").AST;
const JsonRuleType = @import("json/linter.zig").JsonRuleType;
const ZonRuleType = @import("zon/linter.zig").ZonRuleType;

// Create a concrete LanguageSupport union for the registry
const LanguageSupport = union(enum) {
    json: lang_interface.LanguageSupport(JsonAST, JsonRuleType),
    zon: lang_interface.LanguageSupport(ZonAST, ZonRuleType),
    // Other languages will be added as they're implemented

    pub fn deinit(self: *LanguageSupport, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .json => |*support| if (support.deinitFn) |deinitFn| deinitFn(allocator),
            .zon => |*support| if (support.deinitFn) |deinitFn| deinitFn(allocator),
        }
    }
};

// Language module imports
const json_mod = @import("json/mod.zig");
const zon_mod = @import("zon/mod.zig");

// TODO: To add a new language module:
// 1. Add import: const lang_mod = @import("lang/mod.zig");
// 2. Add to LanguageSupport union below
// 3. Add case in getSupport() switch statement
// 4. Add to getSupportedLanguages() array

/// Enhanced language registry for unified language support
///
/// This registry provides centralized access to language implementations,
/// leveraging the stratified parser architecture for all languages.
pub const LanguageRegistry = struct {
    allocator: std.mem.Allocator,

    /// Cache of initialized language support instances
    cache: std.HashMap(Language, LanguageSupport, std.hash_map.AutoContext(Language), 80),

    pub fn init(allocator: std.mem.Allocator) LanguageRegistry {
        return LanguageRegistry{
            .allocator = allocator,
            .cache = std.HashMap(Language, LanguageSupport, std.hash_map.AutoContext(Language), 80).init(allocator),
        };
    }

    pub fn deinit(self: *LanguageRegistry) void {
        // Cleanup cached language support instances
        var iterator = self.cache.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.cache.deinit();
    }

    /// Get complete language support for a language
    pub fn getSupport(self: *LanguageRegistry, language: Language) !LanguageSupport {
        // Check cache first
        if (self.cache.get(language)) |support| {
            return support;
        }

        // Initialize new language support
        const support = switch (language) {
            .json => LanguageSupport{ .json = try json_mod.getSupport(self.allocator) },
            .zon => LanguageSupport{ .zon = try zon_mod.getSupport(self.allocator) },
            .zig, .css, .html, .typescript, .svelte => return error.UnsupportedLanguage, // Not yet implemented
            .unknown => return error.UnsupportedLanguage,
        };

        // Cache the support instance
        try self.cache.put(language, support);
        return support;
    }

    /// Get lexer for a language
    pub fn getLexer(self: *LanguageRegistry, language: Language) !Lexer {
        const support = try self.getSupport(language);
        return switch (support) {
            .json => |s| s.lexer,
            .zon => |s| s.lexer,
        };
    }

    // Note: Individual component getters removed for now due to generic type complexity
    // Use getSupport() directly and access the desired component from the union

    /// Check if language is supported
    pub fn isLanguageSupported(self: *LanguageRegistry, language: Language) bool {
        _ = self;
        return switch (language) {
            .json, .zon => true,
            .zig, .css, .html, .typescript, .svelte => false, // Not yet implemented
            .unknown => false,
        };
    }

    /// Get language from file extension (delegates to detection)
    pub fn getLanguage(self: *LanguageRegistry, extension: []const u8) Language {
        _ = self;
        return Language.fromExtension(extension);
    }

    /// Get language from file path
    pub fn getLanguageFromPath(self: *LanguageRegistry, file_path: []const u8) Language {
        _ = self;
        return Language.fromPath(file_path);
    }

    /// Get supported languages list
    pub fn getSupportedLanguages(self: *LanguageRegistry) []const Language {
        _ = self;
        // Only JSON and ZON are currently implemented
        const supported = [_]Language{ .json, .zon };
        return &supported;
    }

    /// Clear language cache (for development/testing)
    pub fn clearCache(self: *LanguageRegistry) void {
        var iterator = self.cache.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.cache.clearAndFree();
    }

    /// Get cache statistics for debugging
    pub fn getCacheStats(self: *LanguageRegistry) CacheStats {
        return CacheStats{
            .cached_languages = self.cache.count(),
            .capacity = self.cache.capacity(),
        };
    }

    pub const CacheStats = struct {
        cached_languages: u32,
        capacity: u32,
    };
};

/// Global registry instance for convenience
var global_registry: ?LanguageRegistry = null;
var global_registry_mutex = std.Thread.Mutex{};

/// Get or create global language registry
pub fn getGlobalRegistry(allocator: std.mem.Allocator) !*LanguageRegistry {
    global_registry_mutex.lock();
    defer global_registry_mutex.unlock();

    if (global_registry == null) {
        global_registry = LanguageRegistry.init(allocator);
    }

    return &global_registry.?;
}

/// Cleanup global registry
pub fn deinitGlobalRegistry() void {
    global_registry_mutex.lock();
    defer global_registry_mutex.unlock();

    if (global_registry) |*registry| {
        registry.deinit();
        global_registry = null;
    }
}

/// Convenience functions using global registry
/// Get language support using global registry
pub fn getSupport(allocator: std.mem.Allocator, language: Language) !LanguageSupport {
    const registry = try getGlobalRegistry(allocator);
    return registry.getSupport(language);
}

/// Get lexer using global registry
pub fn getLexer(allocator: std.mem.Allocator, language: Language) !Lexer {
    const registry = try getGlobalRegistry(allocator);
    return registry.getLexer(language);
}

/// Get parser using global registry
pub fn getParser(allocator: std.mem.Allocator, language: Language) !Parser {
    const registry = try getGlobalRegistry(allocator);
    return registry.getParser(language);
}

/// Get formatter using global registry
pub fn getFormatter(allocator: std.mem.Allocator, language: Language) !Formatter {
    const registry = try getGlobalRegistry(allocator);
    return registry.getFormatter(language);
}

/// Check if language is supported using global registry
pub fn isSupported(allocator: std.mem.Allocator, language: Language) !bool {
    const registry = try getGlobalRegistry(allocator);
    return registry.isLanguageSupported(language);
}
