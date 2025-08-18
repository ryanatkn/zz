const std = @import("std");
const Language = @import("../core/language.zig").Language;
const LanguageSupport = @import("interface.zig").LanguageSupport;
const Lexer = @import("interface.zig").Lexer;
const Parser = @import("interface.zig").Parser;
const Formatter = @import("interface.zig").Formatter;
const Linter = @import("interface.zig").Linter;
const Analyzer = @import("interface.zig").Analyzer;

/// Enhanced language registry for unified language support
///
/// This registry provides centralized access to language implementations,
/// leveraging the stratified parser architecture for all languages.
pub const LanguageRegistry = struct {
    allocator: std.mem.Allocator,

    /// Cache of initialized language support instances
    cache: std.HashMap(Language, LanguageSupport),

    pub fn init(allocator: std.mem.Allocator) LanguageRegistry {
        return LanguageRegistry{
            .allocator = allocator,
            .cache = std.HashMap(Language, LanguageSupport).init(allocator),
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
            .typescript => @import("typescript/mod.zig").getSupport(self.allocator),
            .svelte => @import("svelte/mod.zig").getSupport(self.allocator),
            .json => @import("json/mod.zig").getSupport(self.allocator),
            .zig => @import("zig/mod.zig").getSupport(self.allocator),
            .zon => @import("zon/mod.zig").getSupport(self.allocator),
            .css => @import("css/mod.zig").getSupport(self.allocator),
            .html => @import("html/mod.zig").getSupport(self.allocator),
            .unknown => return error.UnsupportedLanguage,
        };

        // Cache the support instance
        try self.cache.put(language, support);
        return support;
    }

    /// Get lexer for a language
    pub fn getLexer(self: *LanguageRegistry, language: Language) !Lexer {
        const support = try self.getSupport(language);
        return support.lexer;
    }

    /// Get parser for a language
    pub fn getParser(self: *LanguageRegistry, language: Language) !Parser {
        const support = try self.getSupport(language);
        return support.parser;
    }

    /// Get formatter for a language
    pub fn getFormatter(self: *LanguageRegistry, language: Language) !Formatter {
        const support = try self.getSupport(language);
        return support.formatter;
    }

    /// Get linter for a language (may be null)
    pub fn getLinter(self: *LanguageRegistry, language: Language) !?Linter {
        const support = try self.getSupport(language);
        return support.linter;
    }

    /// Get analyzer for a language (may be null)
    pub fn getAnalyzer(self: *LanguageRegistry, language: Language) !?Analyzer {
        const support = try self.getSupport(language);
        return support.analyzer;
    }

    /// Check if language is supported
    pub fn isLanguageSupported(self: *LanguageRegistry, language: Language) bool {
        _ = self;
        return switch (language) {
            .typescript, .svelte, .json, .zig, .zon, .css, .html => true,
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
        const supported = [_]Language{ .typescript, .svelte, .json, .zig, .zon, .css, .html };
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
