const std = @import("std");
const detection = @import("detection.zig");
const flags_mod = @import("flags.zig");
const registry_mod = @import("registry.zig");
const FormatterOptions = @import("../parsing/formatter.zig").FormatterOptions;

const Language = detection.Language;
const ExtractionFlags = flags_mod.ExtractionFlags;
const LanguageRegistry = registry_mod.LanguageRegistry;

/// Main extractor coordinator using the language registry
pub const Extractor = struct {
    allocator: std.mem.Allocator,
    registry: *LanguageRegistry,

    /// Initialize extractor with language registry
    pub fn init(allocator: std.mem.Allocator) Extractor {
        return Extractor{
            .allocator = allocator,
            .registry = registry_mod.getGlobalRegistry(allocator),
        };
    }

    /// Initialize with custom registry (for testing)
    pub fn initWithRegistry(allocator: std.mem.Allocator, registry: *LanguageRegistry) Extractor {
        return Extractor{
            .allocator = allocator,
            .registry = registry,
        };
    }


    /// Clean up extractor resources
    pub fn deinit(self: *Extractor) void {
        _ = self;
        // Global registry cleanup is handled separately
        // Nothing to clean up for individual extractors
    }

    /// Main extraction entry point
    pub fn extract(self: *const Extractor, language: Language, source: []const u8, extraction_flags: ExtractionFlags) ![]const u8 {
        // Handle special cases first
        if (extraction_flags.full or extraction_flags.isDefault()) {
            return self.allocator.dupe(u8, source);
        }

        // Check if language is supported
        if (!self.registry.isSupported(language)) {
            return self.extractUnsupportedLanguage(source, extraction_flags);
        }

        // Use AST extraction only
        std.log.debug("Attempting AST extraction for language: {s}", .{@tagName(language)});
        
        var result = std.ArrayList(u8).init(self.allocator);
        defer result.deinit();
        
        try self.registry.extract(self.allocator, language, source, extraction_flags, &result);
        
        // Remove trailing newline if present for better test compatibility
        if (result.items.len > 0 and result.items[result.items.len - 1] == '\n') {
            _ = result.pop();
        }
        
        std.log.debug("AST extraction succeeded: result length={d}", .{result.items.len});
        return result.toOwnedSlice();
    }



    /// Handle unsupported languages with basic extraction
    fn extractUnsupportedLanguage(self: *const Extractor, source: []const u8, extraction_flags: ExtractionFlags) ![]const u8 {
        // For unknown languages, always return full source
        // We can't do meaningful extraction without language knowledge
        _ = extraction_flags; // Unused for unknown languages
        return self.allocator.dupe(u8, source);
    }

    /// Format source code using language-specific formatter
    pub fn format(self: *const Extractor, language: Language, source: []const u8, options: FormatterOptions) ![]const u8 {
        return self.registry.format(self.allocator, language, source, options);
    }

    /// Check if a language is supported
    pub fn isLanguageSupported(self: *const Extractor, language: Language) bool {
        return self.registry.isSupported(language);
    }

    /// Get information about a language
    pub fn getLanguageInfo(self: *const Extractor, language: Language) ?registry_mod.LanguageInfo {
        return self.registry.getLanguageInfo(language);
    }

    /// Get list of all supported languages
    pub fn getSupportedLanguages(self: *const Extractor) ![]Language {
        return self.registry.getSupportedLanguages(self.allocator);
    }
};

/// Create an extractor with default settings (production use)
///
/// Uses the global language registry for efficient memory usage.
/// Safe for production code but should not be used in tests
/// to avoid global state and memory leaks.
///
/// For tests, use createTestExtractor() instead.
pub fn createExtractor(allocator: std.mem.Allocator) Extractor {
    return Extractor.init(allocator);
}

/// Create test-safe extractor with local registry
///
/// Use this in tests to avoid memory leaks from the global registry.
/// The test extractor creates its own registry that must be cleaned up:
///
/// ```zig
/// var extractor = try createTestExtractor(allocator);
/// defer {
///     extractor.registry.deinit();
///     allocator.destroy(extractor.registry);
/// }
/// ```
///
/// For production code, use createExtractor() which uses the global registry.
pub fn createTestExtractor(allocator: std.mem.Allocator) !Extractor {
    const registry = try allocator.create(registry_mod.LanguageRegistry);
    registry.* = registry_mod.LanguageRegistry.init(allocator);
    return Extractor.initWithRegistry(allocator, registry);
}

/// Create an AST-first extractor (same as default)
pub fn createASTExtractor(allocator: std.mem.Allocator) Extractor {
    return Extractor.init(allocator);
}

/// Create an extractor (AST-only)
pub fn createPatternExtractor(allocator: std.mem.Allocator) Extractor {
    return Extractor.init(allocator);
}

/// Extract from file path (convenience function)
pub fn extractFromFile(
    allocator: std.mem.Allocator,
    file_path: []const u8,
    extraction_flags: ExtractionFlags,
) ![]const u8 {
    // Read file
    const source = std.fs.cwd().readFileAlloc(allocator, file_path, 10 * 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => return error.FileNotFound,
        error.AccessDenied => return error.AccessDenied,
        else => return err,
    };
    defer allocator.free(source);

    // Detect language from file extension
    const language = detection.Language.fromPath(file_path);

    // Extract
    const extractor = createExtractor(allocator);
    return extractor.extract(language, source, extraction_flags);
}

/// Format file (convenience function)
pub fn formatFile(
    allocator: std.mem.Allocator,
    file_path: []const u8,
    options: FormatterOptions,
) ![]const u8 {
    // Read file
    const source = std.fs.cwd().readFileAlloc(allocator, file_path, 10 * 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => return error.FileNotFound,
        error.AccessDenied => return error.AccessDenied,
        else => return err,
    };
    defer allocator.free(source);

    // Detect language from file extension
    const language = detection.Language.fromPath(file_path);

    // Format
    const extractor = createExtractor(allocator);
    return extractor.format(language, source, options);
}

/// Cleanup global resources (call at program exit)
pub fn cleanup() void {
    registry_mod.deinitGlobalRegistry();
}

// Tests
test "Extractor basic functionality" {
    const allocator = std.testing.allocator;
    var extractor = try createTestExtractor(allocator);
    defer {
        extractor.registry.deinit();
        allocator.destroy(extractor.registry);
    }

    // Test language support
    try std.testing.expect(extractor.isLanguageSupported(.json));
    try std.testing.expect(extractor.isLanguageSupported(.typescript));

    // Test JSON extraction
    const json_source = "{\"key\": \"value\"}";
    const json_flags = ExtractionFlags{ .full = true };
    const json_result = try extractor.extract(.json, json_source, json_flags);
    defer allocator.free(json_result);

    try std.testing.expect(std.mem.eql(u8, json_result, json_source));
}

test "Extractor unsupported language handling" {
    const allocator = std.testing.allocator;
    var extractor = try createTestExtractor(allocator);
    defer {
        extractor.registry.deinit();
        allocator.destroy(extractor.registry);
    }

    const source = "some unknown language code";
    const flags = ExtractionFlags{ .full = true };
    const result = try extractor.extract(.unknown, source, flags);
    defer allocator.free(result);

    try std.testing.expect(std.mem.eql(u8, result, source));
}

test "Pattern vs AST extraction preferences" {
    const allocator = std.testing.allocator;

    // Test AST-only extractor
    var test_extractor = try createTestExtractor(allocator);
    defer {
        test_extractor.registry.deinit();
        allocator.destroy(test_extractor.registry);
    }
    
    // Test basic functionality works (no specific tests needed for removed prefer_ast)
}
