const std = @import("std");

/// Unified language support module
///
/// This module provides a unified interface for all supported languages,
/// leveraging the Pure Zig Stratified Parser architecture.

// Re-export core types
pub const Language = @import("../core/language.zig").Language;
pub const ExtractionFlags = @import("../core/extraction.zig").ExtractionFlags;

// Core interfaces
const interface_types = @import("interface.zig");
pub const LanguageSupport = interface_types.LanguageSupport;
pub const Lexer = interface_types.Lexer;
pub const Parser = interface_types.Parser;
pub const Formatter = interface_types.Formatter;
pub const Linter = interface_types.Linter;
pub const Analyzer = interface_types.Analyzer;

// Enhanced registry
pub const LanguageRegistry = @import("registry.zig").LanguageRegistry;

// Common utilities
pub const common = @import("common/mod.zig");

// Language implementations
pub const typescript = @import("typescript/mod.zig");
pub const svelte = @import("svelte/mod.zig");
pub const json = @import("json/mod.zig");
pub const zig = @import("zig/mod.zig");
pub const zon = @import("zon/mod.zig");
pub const css = @import("css/mod.zig");
pub const html = @import("html/mod.zig");

/// Get language support for a specific language
pub fn getSupport(allocator: std.mem.Allocator, language: Language) !LanguageSupport {
    return switch (language) {
        .typescript => typescript.getSupport(allocator),
        .svelte => svelte.getSupport(allocator),
        .json => json.getSupport(allocator),
        .zig => zig.getSupport(allocator),
        .zon => zon.getSupport(allocator),
        .css => css.getSupport(allocator),
        .html => html.getSupport(allocator),
        .unknown => error.UnsupportedLanguage,
    };
}

/// Check if a language is supported
pub fn isSupported(language: Language) bool {
    return switch (language) {
        .typescript, .svelte, .json, .zig, .zon, .css, .html => true,
        .unknown => false,
    };
}

/// Get all supported languages
pub fn getSupportedLanguages() []const Language {
    const supported = [_]Language{ .typescript, .svelte, .json, .zig, .zon, .css, .html };
    return &supported;
}
