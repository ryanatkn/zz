const std = @import("std");
const ExtractionFlags = @import("language/flags.zig").ExtractionFlags;
const line_processing = @import("text/line_processing.zig");
const patterns = @import("text/patterns.zig");
const builders = @import("text/builders.zig");
const ResultBuilder = builders.ResultBuilder;

/// Base extractor functionality shared across all language extractors
/// Provides common extraction patterns to eliminate duplication

pub const LanguagePatterns = struct {
    /// Patterns for function/method signatures
    functions: ?[]const []const u8 = null,
    
    /// Patterns for type definitions
    types: ?[]const []const u8 = null,
    
    /// Patterns for imports/includes
    imports: ?[]const []const u8 = null,
    
    /// Patterns for documentation comments
    docs: ?[]const []const u8 = null,
    
    /// Patterns for test definitions
    tests: ?[]const []const u8 = null,
    
    /// Patterns for structure (language-specific)
    structure: ?[]const []const u8 = null,
    
    /// Custom extraction function for complex patterns
    custom_extract: ?*const fn(line: []const u8, flags: ExtractionFlags) bool = null,
};

/// Extract code using language patterns
pub fn extractWithPatterns(
    source: []const u8,
    flags: ExtractionFlags,
    result: *std.ArrayList(u8),
    language_patterns: LanguagePatterns,
) !void {
    var builder = ResultBuilder{ .buffer = result.* };
    defer result.* = builder.buffer;
    
    var lines = std.mem.splitScalar(u8, source, '\n');
    var block_tracker = line_processing.BlockTracker.init();
    
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        
        // Skip empty lines unless in a block
        if (trimmed.len == 0 and !block_tracker.isInBlock()) continue;
        
        // Handle multi-line blocks
        if (block_tracker.isInBlock()) {
            try builder.appendLine(line);
            block_tracker.processLine(line);
            continue;
        }
        
        var should_include = false;
        var starts_block = false;
        
        // Check function patterns
        if (flags.signatures) {
            if (language_patterns.functions) |func_patterns| {
                if (patterns.startsWithAny(trimmed, func_patterns)) {
                    should_include = true;
                }
            }
        }
        
        // Check type patterns
        if (flags.types) {
            if (language_patterns.types) |type_patterns| {
                if (patterns.startsWithAny(trimmed, type_patterns)) {
                    should_include = true;
                    // Check if this starts a block
                    if (std.mem.indexOf(u8, line, "{") != null) {
                        starts_block = true;
                    }
                }
            }
        }
        
        // Check import patterns
        if (flags.imports) {
            if (language_patterns.imports) |import_patterns| {
                if (patterns.startsWithAny(trimmed, import_patterns)) {
                    should_include = true;
                }
            }
        }
        
        // Check documentation patterns
        if (flags.docs) {
            if (language_patterns.docs) |doc_patterns| {
                if (patterns.startsWithAny(trimmed, doc_patterns)) {
                    should_include = true;
                }
            }
        }
        
        // Check test patterns
        if (flags.tests) {
            if (language_patterns.tests) |test_patterns| {
                if (patterns.startsWithAny(trimmed, test_patterns)) {
                    should_include = true;
                }
            }
        }
        
        // Check structure patterns
        if (flags.structure) {
            if (language_patterns.structure) |struct_patterns| {
                if (patterns.startsWithAny(trimmed, struct_patterns) or
                    patterns.containsAny(line, struct_patterns)) {
                    should_include = true;
                }
            }
        }
        
        // Custom extraction logic
        if (language_patterns.custom_extract) |custom| {
            if (custom(line, flags)) {
                should_include = true;
            }
        }
        
        if (should_include) {
            try builder.appendLine(line);
            if (starts_block) {
                block_tracker.processLine(line);
            }
        }
    }
}

/// Extract lines matching specific prefixes
pub fn extractByPrefixes(
    source: []const u8,
    prefixes: []const []const u8,
    result: *std.ArrayList(u8),
) !void {
    var builder = ResultBuilder{ .buffer = result.* };
    defer result.* = builder.buffer;
    
    try line_processing.extractLinesWithPrefixes(source, prefixes, builder.list());
}

/// Extract lines containing specific patterns
pub fn extractContaining(
    source: []const u8,
    substrings: []const []const u8,
    result: *std.ArrayList(u8),
) !void {
    var builder = ResultBuilder{ .buffer = result.* };
    defer result.* = builder.buffer;
    
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |line| {
        if (patterns.containsAny(line, substrings)) {
            try builder.appendLine(line);
        }
    }
}

/// Filter and extract non-empty lines
pub fn extractNonEmpty(
    source: []const u8,
    result: *std.ArrayList(u8),
) !void {
    var builder = ResultBuilder{ .buffer = result.* };
    defer result.* = builder.buffer;
    
    try line_processing.filterNonEmpty(source, builder.list());
}

/// Create language patterns for Zig
pub fn zigPatterns() LanguagePatterns {
    return .{
        .functions = &patterns.Patterns.zig_functions,
        .types = &patterns.Patterns.zig_types,
        .docs = &patterns.Patterns.zig_docs,
        .tests = &[_][]const u8{"test "},
        .imports = null, // Zig uses custom logic for @import
    };
}

/// Create language patterns for TypeScript/JavaScript
pub fn typeScriptPatterns() LanguagePatterns {
    return .{
        .functions = &patterns.Patterns.ts_functions,
        .types = &patterns.Patterns.ts_types,
        .imports = &patterns.Patterns.ts_imports,
        .docs = &[_][]const u8{"/**", "//"},
    };
}

/// Create language patterns for CSS
pub fn cssPatterns() LanguagePatterns {
    return .{
        .functions = &patterns.Patterns.css_selectors,
        .structure = &patterns.Patterns.css_at_rules,
        .imports = &[_][]const u8{"@import", "@use"},
        .docs = &[_][]const u8{"/*"},
    };
}

/// Create language patterns for HTML
pub fn htmlPatterns() LanguagePatterns {
    return .{
        .structure = &[_][]const u8{"<", ">"},
        .imports = &[_][]const u8{"<link", "<script"},
        .docs = &[_][]const u8{"<!--"},
    };
}

/// Create language patterns for JSON
pub fn jsonPatterns() LanguagePatterns {
    return .{
        .structure = &patterns.Patterns.json_structural,
    };
}

test "extractWithPatterns for Zig" {
    const allocator = std.testing.allocator;
    const source =
        \\pub fn test() void {}
        \\const value = 42;
        \\/// Documentation
        \\fn private() void {}
        \\test "example" {}
    ;
    
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();
    
    const flags = ExtractionFlags{ .signatures = true };
    const zig_patterns = zigPatterns();
    
    try extractWithPatterns(source, flags, &result, zig_patterns);
    
    const output = result.items;
    try std.testing.expect(std.mem.indexOf(u8, output, "pub fn test()") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "fn private()") != null);
}

test "extractByPrefixes" {
    const allocator = std.testing.allocator;
    const source =
        \\import foo from 'bar';
        \\const value = 42;
        \\export function test() {}
        \\let x = 10;
    ;
    
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();
    
    const prefixes = [_][]const u8{ "import", "export" };
    try extractByPrefixes(source, &prefixes, &result);
    
    const output = result.items;
    try std.testing.expect(std.mem.indexOf(u8, output, "import foo") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "export function") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "const value") == null);
}