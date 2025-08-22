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

// Language implementations (only JSON and ZON are currently implemented)
pub const json = @import("json/mod.zig");
pub const zon = @import("zon/mod.zig");

// TODO: Other language implementations to be added:
// pub const typescript = @import("typescript/mod.zig");
// pub const svelte = @import("svelte/mod.zig");
// pub const zig = @import("zig/mod.zig");
// pub const css = @import("css/mod.zig");
// pub const html = @import("html/mod.zig");

/// Get language support for a specific language (delegates to registry)
pub fn getSupport(allocator: std.mem.Allocator, language: Language) !LanguageSupport {
    const registry = try @import("registry.zig").getGlobalRegistry(allocator);
    return registry.getSupport(language);
}

/// Check if a language is supported
pub fn isSupported(language: Language) bool {
    return switch (language) {
        .json, .zon => true,
        .typescript, .svelte, .zig, .css, .html => false, // Not yet implemented
        .unknown => false,
    };
}

/// Get all supported languages (currently implemented)
pub fn getSupportedLanguages() []const Language {
    const supported = [_]Language{ .json, .zon };
    return &supported;
}
