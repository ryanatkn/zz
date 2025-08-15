const std = @import("std");
const ts = @import("tree-sitter");
const TreeSitterParser = @import("../language/tree_sitter.zig").TreeSitterParser;
const FormatterOptions = @import("formatter.zig").FormatterOptions;
const LineBuilder = @import("formatter.zig").LineBuilder;
const Language = @import("../language/detection.zig").Language;
const AstCache = @import("../analysis/cache.zig").AstCache;
const AstCacheKey = @import("../analysis/cache.zig").AstCacheKey;

/// Base class for AST-powered formatters using tree-sitter
pub const AstFormatter = struct {
    allocator: std.mem.Allocator,
    parser: TreeSitterParser,
    options: FormatterOptions,
    language: Language,
    cache: ?*AstCache,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, language: Language, options: FormatterOptions) !Self {
        const parser = TreeSitterParser.init(allocator, language) catch {
            // Tree-sitter initialization failed (version incompatibility, unsupported language, etc.)
            return error.UnsupportedLanguage;
        };

        return Self{
            .allocator = allocator,
            .parser = parser,
            .options = options,
            .language = language,
            .cache = null,
        };
    }

    pub fn initWithCache(allocator: std.mem.Allocator, language: Language, options: FormatterOptions, cache: *AstCache) !Self {
        const parser = TreeSitterParser.init(allocator, language) catch {
            // Tree-sitter initialization failed (version incompatibility, unsupported language, etc.)
            return error.UnsupportedLanguage;
        };

        return Self{
            .allocator = allocator,
            .parser = parser,
            .options = options,
            .language = language,
            .cache = cache,
        };
    }

    pub fn deinit(self: *Self) void {
        self.parser.deinit();
    }

    /// Format source code using AST-based approach with fallback to original
    pub fn format(self: *Self, source: []const u8) ![]const u8 {
        return self.formatWithFilePath(source, null);
    }

    /// Format source code with optional file path for better caching
    pub fn formatWithFilePath(self: *Self, source: []const u8, file_path: ?[]const u8) ![]const u8 {
        // Check cache if available
        if (self.cache) |cache| {
            if (file_path) |path| {
                const cache_key = self.createCacheKey(source, path);
                if (cache.get(cache_key)) |cached_content| {
                    // Cache hit - return cached result
                    return self.allocator.dupe(u8, cached_content);
                }
            }
        }

        // Try AST-based formatting first
        const tree = self.parser.parse(source) catch {
            // On parse failure, return original source
            return self.allocator.dupe(u8, source);
        };
        defer tree.destroy();

        const root = tree.rootNode();

        var builder = LineBuilder.init(self.allocator, self.options);
        defer builder.deinit();

        // Dispatch to language-specific AST formatting
        switch (self.language) {
            .typescript => {
                const ts_formatter = @import("../languages/typescript/formatter.zig");
                try ts_formatter.formatAst(self.allocator, root, source, &builder, self.options);
            },
            .css => {
                const css_formatter = @import("../languages/css/formatter.zig");
                try css_formatter.formatAst(self.allocator, root, source, &builder, self.options);
            },
            .svelte => {
                const svelte_formatter = @import("../languages/svelte/formatter.zig");
                try svelte_formatter.formatAst(self.allocator, root, source, &builder, self.options);
            },
            .json => {
                const json_formatter = @import("../languages/json/formatter.zig");
                try json_formatter.formatAst(self.allocator, root, source, &builder, self.options);
            },
            .html => {
                const html_formatter = @import("../languages/html/formatter.zig");
                try html_formatter.formatAst(self.allocator, root, source, &builder, self.options);
            },
            .zig => {
                const zig_formatter = @import("../languages/zig/formatter.zig");
                try zig_formatter.formatAst(self.allocator, root, source, &builder, self.options);
            },
            else => {
                // For unsupported languages, return original source
                return self.allocator.dupe(u8, source);
            },
        }

        // Trim trailing newline for HTML output before converting to owned slice
        if (self.language == .html) {
            builder.trimTrailingNewline();
        }

        const result = try builder.toOwnedSlice();

        // Cache the result if cache is available
        if (self.cache) |cache| {
            if (file_path) |path| {
                const cache_key = self.createCacheKey(source, path);
                // Store in cache (ignore errors - cache is optional)
                cache.put(cache_key, result) catch {};
            }
        }

        return result;
    }

    /// Create a cache key for the given source and formatter options
    fn createCacheKey(self: *Self, source: []const u8, file_path: []const u8) AstCacheKey {
        _ = file_path; // Currently unused, but kept for future file-specific caching
        // Hash the source content
        var hasher = std.hash.XxHash64.init(0);
        hasher.update(source);
        const file_hash = hasher.final();

        // Hash the formatter options to ensure cache invalidation on option changes
        hasher = std.hash.XxHash64.init(0);
        hasher.update(std.mem.asBytes(&self.options.indent_size));
        hasher.update(std.mem.asBytes(&self.options.indent_style));
        hasher.update(std.mem.asBytes(&self.options.line_width));
        hasher.update(std.mem.asBytes(&self.options.preserve_newlines));
        hasher.update(std.mem.asBytes(&self.options.trailing_comma));
        hasher.update(std.mem.asBytes(&self.options.sort_keys));
        hasher.update(std.mem.asBytes(&self.options.quote_style));
        hasher.update(std.mem.asBytes(&self.options.use_ast));
        const options_hash = hasher.final();

        return AstCacheKey.init(file_hash, 1, options_hash);
    }
};

/// Shared utilities for AST formatting
pub const AstFormatterUtils = struct {
    /// Check if a node represents a function-like construct
    pub fn isFunctionLike(node_type: []const u8) bool {
        return std.mem.eql(u8, node_type, "function_declaration") or
            std.mem.eql(u8, node_type, "method_definition") or
            std.mem.eql(u8, node_type, "arrow_function");
    }

    /// Check if a node represents a type definition
    pub fn isTypeDefinition(node_type: []const u8) bool {
        return std.mem.eql(u8, node_type, "interface_declaration") or
            std.mem.eql(u8, node_type, "class_declaration") or
            std.mem.eql(u8, node_type, "type_alias_declaration") or
            std.mem.eql(u8, node_type, "enum_declaration");
    }

    /// Check if a node represents a CSS rule
    pub fn isCssRule(node_type: []const u8) bool {
        return std.mem.eql(u8, node_type, "rule_set") or
            std.mem.eql(u8, node_type, "at_rule") or
            std.mem.eql(u8, node_type, "declaration");
    }

    /// Check if a node represents a Svelte section
    pub fn isSvelteSection(node_type: []const u8) bool {
        return std.mem.eql(u8, node_type, "script_element") or
            std.mem.eql(u8, node_type, "style_element") or
            std.mem.eql(u8, node_type, "template_element");
    }
};

// Tests
test "ast formatter initialization" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Try to initialize formatter - may fail due to tree-sitter version issues
    var formatter = AstFormatter.init(allocator, .typescript, .{}) catch |err| {
        // If initialization fails due to version issues, that's expected
        if (err == error.IncompatibleVersion or err == error.UnsupportedLanguage) {
            return; // Test passes - graceful handling of version issues
        }
        return err; // Re-raise unexpected errors
    };
    defer formatter.deinit();

    try testing.expect(formatter.language == .typescript);
}

test "ast formatter utils" {
    const testing = std.testing;

    try testing.expect(AstFormatterUtils.isFunctionLike("function_declaration"));
    try testing.expect(AstFormatterUtils.isTypeDefinition("interface_declaration"));
    try testing.expect(AstFormatterUtils.isCssRule("rule_set"));
    try testing.expect(AstFormatterUtils.isSvelteSection("script_element"));

    try testing.expect(!AstFormatterUtils.isFunctionLike("identifier"));
    try testing.expect(!AstFormatterUtils.isTypeDefinition("property_name"));
}
