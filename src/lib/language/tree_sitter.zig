const std = @import("std");
const ts = @import("tree-sitter");
const detection = @import("detection.zig");
const flags_mod = @import("flags.zig");
const imports_mod = @import("../parsing/imports.zig");

const Language = detection.Language;
const ExtractionFlags = flags_mod.ExtractionFlags;
const ImportInfo = imports_mod.Import;
const ExtractionResult = imports_mod.ExtractionResult;

// Language-specific tree-sitter grammars
extern fn tree_sitter_zig() callconv(.C) *ts.Language;
extern fn tree_sitter_css() callconv(.C) *ts.Language;
extern fn tree_sitter_html() callconv(.C) *ts.Language;
extern fn tree_sitter_json() callconv(.C) *ts.Language;
extern fn tree_sitter_typescript() callconv(.C) *ts.Language;
extern fn tree_sitter_svelte() callconv(.C) *ts.Language;

/// Tree-sitter parser with language support for all 6 languages
pub const TreeSitterParser = struct {
    allocator: std.mem.Allocator,
    parser: *ts.Parser,
    language: Language,
    ts_language: *ts.Language,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, language: Language) !Self {
        const parser = ts.Parser.create();
        const ts_language = try getTreeSitterLanguage(language);

        // Try to set language, but handle version incompatibility gracefully
        parser.setLanguage(ts_language) catch |err| {
            parser.destroy();
            return err;
        };

        return Self{
            .allocator = allocator,
            .parser = parser,
            .language = language,
            .ts_language = ts_language,
        };
    }

    pub fn deinit(self: *Self) void {
        self.parser.destroy();
    }

    /// Parse source code and return syntax tree
    pub fn parse(self: *Self, source: []const u8) !*ts.Tree {
        const tree = self.parser.parseString(source, null);
        return tree orelse error.ParseFailed;
    }

    /// Extract code using real tree-sitter AST
    pub fn extract(self: *Self, source: []const u8, extraction_flags: ExtractionFlags) ![]const u8 {
        // Early termination: if no extraction flags are set, return full source
        if (extraction_flags.isDefault()) {
            return self.allocator.dupe(u8, source);
        }

        const tree = try self.parse(source);
        defer tree.destroy();

        const root = tree.rootNode();

        // Pre-allocate with estimated capacity (10% of source size as reasonable estimate)
        const estimated_capacity = @max(256, source.len / 10);
        var result = try std.ArrayList(u8).initCapacity(self.allocator, estimated_capacity);
        defer result.deinit();

        try self.walkAndExtract(root, source, extraction_flags, &result);

        return result.toOwnedSlice();
    }

    /// Extract imports and exports from source using AST analysis
    /// This provides a unified interface that leverages imports_mod.Extractor but uses this parser
    pub fn extractImports(self: *Self, file_path: []const u8, source: []const u8) !ExtractionResult {
        var import_extractor = imports_mod.Extractor.init(self.allocator);

        // Use the imports_mod.Extractor but with our tree-sitter parser for enhanced accuracy
        switch (self.language) {
            .typescript, .javascript => return self.extractTypeScriptImports(file_path, source),
            .zig => return self.extractZigImports(file_path, source),
            .css => return self.extractCssImports(file_path, source),
            .svelte => return self.extractSvelteImports(file_path, source),
            else => return import_extractor.extract(file_path, source),
        }
    }

    // Core extraction methods for each language

    /// Walk AST and extract based on language and flags
    fn walkAndExtract(self: *Self, node: ts.Node, source: []const u8, extraction_flags: ExtractionFlags, result: *std.ArrayList(u8)) std.mem.Allocator.Error!void {
        switch (self.language) {
            .zig => try self.extractZig(node, source, extraction_flags, result),
            .css => try self.extractCss(node, source, extraction_flags, result),
            .html => try self.extractHtml(node, source, extraction_flags, result),
            .json => try self.extractJson(node, source, extraction_flags, result),
            .typescript => try self.extractTypeScript(node, source, extraction_flags, result),
            .svelte => try self.extractSvelte(node, source, extraction_flags, result),
            .unknown => try result.appendSlice(source),
        }
    }

    /// Zig-specific AST extraction
    fn extractZig(self: *Self, node: ts.Node, source: []const u8, extraction_flags: ExtractionFlags, result: *std.ArrayList(u8)) std.mem.Allocator.Error!void {
        // Early termination: if no relevant flags are set, skip this subtree
        if (!extraction_flags.signatures and !extraction_flags.types and !extraction_flags.docs and !extraction_flags.tests and !extraction_flags.imports) {
            return;
        }

        const node_type = node.kind();

        if (extraction_flags.signatures) {
            if (std.mem.eql(u8, node_type, "function_declaration")) {
                try self.appendNodeText(node, source, result);
                return; // Don't recurse into function body
            }
        }

        if (extraction_flags.types) {
            if (std.mem.eql(u8, node_type, "struct_declaration") or
                std.mem.eql(u8, node_type, "enum_declaration") or
                std.mem.eql(u8, node_type, "union_declaration"))
            {
                try self.appendNodeText(node, source, result);
                return;
            }
        }

        if (extraction_flags.docs) {
            if (std.mem.eql(u8, node_type, "doc_comment") or
                std.mem.eql(u8, node_type, "container_doc_comment"))
            {
                try self.appendNodeText(node, source, result);
            }
        }

        if (extraction_flags.tests) {
            if (std.mem.eql(u8, node_type, "test_declaration")) {
                try self.appendNodeText(node, source, result);
                return;
            }
        }

        if (extraction_flags.imports) {
            if (std.mem.eql(u8, node_type, "builtin_call")) {
                const text = self.getNodeText(node, source);
                if (std.mem.startsWith(u8, text, "@import")) {
                    try self.appendNodeText(node, source, result);
                }
            }
        }

        // Recurse into children
        try self.recurseChildren(node, source, extraction_flags, result);
    }

    /// CSS-specific AST extraction
    fn extractCss(self: *Self, node: ts.Node, source: []const u8, extraction_flags: ExtractionFlags, result: *std.ArrayList(u8)) std.mem.Allocator.Error!void {
        const node_type = node.kind();

        if (extraction_flags.signatures) {
            if (isSelector(node_type)) {
                try self.appendNodeText(node, source, result);
                return; // Don't traverse into selector details
            }
        }

        if (extraction_flags.types or extraction_flags.structure) {
            if (isRule(node_type) or isAtRule(node_type)) {
                try self.appendNodeText(node, source, result);
                return;
            }
        }

        if (extraction_flags.imports) {
            if (isImportRule(node_type)) {
                try self.appendNodeText(node, source, result);
            }
        }

        if (extraction_flags.docs) {
            if (isComment(node_type)) {
                try self.appendNodeText(node, source, result);
            }
        }

        // Recurse into children
        try self.recurseChildren(node, source, extraction_flags, result);
    }

    /// Placeholder methods for other languages
    fn extractHtml(self: *Self, node: ts.Node, source: []const u8, extraction_flags: ExtractionFlags, result: *std.ArrayList(u8)) std.mem.Allocator.Error!void {
        // Simplified HTML extraction - full implementation would be similar to above
        if (extraction_flags.structure) {
            try result.appendSlice(source);
            return;
        }
        try self.recurseChildren(node, source, extraction_flags, result);
    }

    fn extractJson(self: *Self, node: ts.Node, source: []const u8, extraction_flags: ExtractionFlags, result: *std.ArrayList(u8)) std.mem.Allocator.Error!void {
        // Simplified JSON extraction
        if (extraction_flags.structure) {
            try result.appendSlice(source);
            return;
        }
        try self.recurseChildren(node, source, extraction_flags, result);
    }

    fn extractTypeScript(self: *Self, node: ts.Node, source: []const u8, extraction_flags: ExtractionFlags, result: *std.ArrayList(u8)) std.mem.Allocator.Error!void {
        // Simplified TypeScript extraction
        const node_type = node.kind();

        if (extraction_flags.signatures) {
            if (std.mem.eql(u8, node_type, "function_declaration") or
                std.mem.eql(u8, node_type, "method_definition") or
                std.mem.eql(u8, node_type, "arrow_function"))
            {
                try self.appendNodeText(node, source, result);
                return;
            }
        }

        try self.recurseChildren(node, source, extraction_flags, result);
    }

    fn extractSvelte(self: *Self, node: ts.Node, source: []const u8, extraction_flags: ExtractionFlags, result: *std.ArrayList(u8)) std.mem.Allocator.Error!void {
        // Simplified Svelte extraction
        if (extraction_flags.structure) {
            try result.appendSlice(source);
            return;
        }
        try self.recurseChildren(node, source, extraction_flags, result);
    }

    // Import extraction methods (simplified versions)

    fn extractTypeScriptImports(self: *Self, file_path: []const u8, source: []const u8) !ExtractionResult {
        // Fallback to text-based extraction for now
        var import_extractor = imports_mod.Extractor.init(self.allocator);
        return import_extractor.extract(file_path, source);
    }

    fn extractZigImports(self: *Self, file_path: []const u8, source: []const u8) !ExtractionResult {
        // Fallback to text-based extraction for now
        var import_extractor = imports_mod.Extractor.init(self.allocator);
        return import_extractor.extract(file_path, source);
    }

    fn extractCssImports(self: *Self, file_path: []const u8, source: []const u8) !ExtractionResult {
        _ = self;
        _ = file_path;
        _ = source;
        return ExtractionResult{ .imports = &.{}, .exports = &.{} };
    }

    fn extractSvelteImports(self: *Self, file_path: []const u8, source: []const u8) !ExtractionResult {
        // Fallback to text-based extraction for now
        var import_extractor = imports_mod.Extractor.init(self.allocator);
        return import_extractor.extract(file_path, source);
    }

    // Utility methods

    /// Get the text content of a node
    fn getNodeText(self: *Self, node: ts.Node, source: []const u8) []const u8 {
        _ = self;
        const start = node.startByte();
        const end = node.endByte();
        if (end <= source.len) {
            return source[start..end];
        }
        return "";
    }

    /// Append node text to result with newline
    fn appendNodeText(self: *Self, node: ts.Node, source: []const u8, result: *std.ArrayList(u8)) std.mem.Allocator.Error!void {
        _ = self;
        const start = node.startByte();
        const end = node.endByte();
        // Bounds check and append in one operation
        if (end <= source.len and start <= end) {
            try result.appendSlice(source[start..end]);
            try result.append('\n');
        }
    }

    /// Recursively process child nodes
    fn recurseChildren(self: *Self, node: ts.Node, source: []const u8, extraction_flags: ExtractionFlags, result: *std.ArrayList(u8)) std.mem.Allocator.Error!void {
        const child_count = node.childCount();
        var i: u32 = 0;
        while (i < child_count) : (i += 1) {
            if (node.child(i)) |child| {
                try self.walkAndExtract(child, source, extraction_flags, result);
            }
        }
    }
};

/// Get tree-sitter language for the given language enum
fn getTreeSitterLanguage(language: Language) !*ts.Language {
    return switch (language) {
        .zig => tree_sitter_zig(),
        .css => tree_sitter_css(),
        .html => tree_sitter_html(),
        .json => tree_sitter_json(),
        .typescript => tree_sitter_typescript(),
        .svelte => tree_sitter_svelte(),
        .unknown => error.UnsupportedLanguage, // Don't fallback to arbitrary grammar
    };
}

/// CSS node type checking functions
fn isSelector(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "selectors") or
        std.mem.eql(u8, node_type, "class_selector") or
        std.mem.eql(u8, node_type, "id_selector") or
        std.mem.eql(u8, node_type, "tag_name") or
        std.mem.eql(u8, node_type, "universal_selector") or
        std.mem.eql(u8, node_type, "attribute_selector") or
        std.mem.eql(u8, node_type, "pseudo_class_selector") or
        std.mem.eql(u8, node_type, "pseudo_element_selector");
}

fn isRule(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "rule_set") or
        std.mem.eql(u8, node_type, "declaration") or
        std.mem.eql(u8, node_type, "property_name") or
        std.mem.eql(u8, node_type, "value");
}

fn isAtRule(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "at_rule") or
        std.mem.eql(u8, node_type, "media_query") or
        std.mem.eql(u8, node_type, "keyframes_statement") or
        std.mem.eql(u8, node_type, "supports_statement");
}

fn isImportRule(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "import_statement") or
        (std.mem.eql(u8, node_type, "at_rule"));
}

fn isComment(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "comment");
}

/// Public API for creating tree-sitter parsers
pub fn createTreeSitterParser(allocator: std.mem.Allocator, language: Language) !TreeSitterParser {
    return TreeSitterParser.init(allocator, language);
}

/// Helper function to extract with automatic language detection
pub fn extractWithTreeSitter(allocator: std.mem.Allocator, file_path: []const u8, source: []const u8, extraction_flags: ExtractionFlags) ![]const u8 {
    const path_utils = @import("../core/path.zig");
    const ext = path_utils.extension(file_path);
    const language = Language.fromExtension(ext);

    var parser = try createTreeSitterParser(allocator, language);
    defer parser.deinit();

    return parser.extract(source, extraction_flags);
}

// Tests

test "tree-sitter parser initialization" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var parser = try createTreeSitterParser(allocator, .zig);
    defer parser.deinit();

    try testing.expect(parser.language == .zig);
}

test "unsupported language handling" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Should return error for unknown language
    const result = createTreeSitterParser(allocator, .unknown);
    try testing.expectError(error.UnsupportedLanguage, result);
}
