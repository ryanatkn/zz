const std = @import("std");
const Language = @import("detection.zig").Language;

/// Legacy language registry compatibility stub - uses pure Zig language detection
pub const LanguageRegistry = struct {
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) LanguageRegistry {
        return LanguageRegistry{
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *LanguageRegistry) void {
        _ = self;
    }
    
    /// Check if language is supported (delegates to pure Zig language detection)
    pub fn isLanguageSupported(self: *LanguageRegistry, language: Language) bool {
        _ = self;
        return switch (language) {
            .zig, .typescript, .css, .html, .json, .svelte => true,
            .unknown => false,
        };
    }
    
    /// Get language from file extension (delegates to pure Zig detection)
    pub fn getLanguage(self: *LanguageRegistry, extension: []const u8) Language {
        _ = self;
        return Language.fromExtension(extension);
    }
    
    /// Get supported languages list
    pub fn getSupportedLanguages(self: *LanguageRegistry) []const Language {
        _ = self;
        const supported = [_]Language{ .zig, .typescript, .css, .html, .json, .svelte };
        return &supported;
    }
};