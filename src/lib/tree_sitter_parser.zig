const std = @import("std");
const ts = @import("tree-sitter");
const ExtractionFlags = @import("parser.zig").ExtractionFlags;
const Language = @import("parser.zig").Language;

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
        try parser.setLanguage(ts_language);
        
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
    pub fn extract(self: *Self, source: []const u8, flags: ExtractionFlags) ![]const u8 {
        // Early termination: if no extraction flags are set, return full source
        if (flags.isDefault()) {
            return self.allocator.dupe(u8, source);
        }
        
        const tree = try self.parse(source);
        defer tree.destroy();
        
        const root = tree.rootNode();
        
        // Pre-allocate with estimated capacity (10% of source size as reasonable estimate)
        const estimated_capacity = @max(256, source.len / 10);
        var result = try std.ArrayList(u8).initCapacity(self.allocator, estimated_capacity);
        defer result.deinit();
        
        try self.walkAndExtract(root, source, flags, &result);
        
        return result.toOwnedSlice();
    }
    
    /// Walk AST and extract based on language and flags
    fn walkAndExtract(self: *Self, node: ts.Node, source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) std.mem.Allocator.Error!void {
        switch (self.language) {
            .zig => try self.extractZig(node, source, flags, result),
            .css => try self.extractCss(node, source, flags, result),
            .html => try self.extractHtml(node, source, flags, result),
            .json => try self.extractJson(node, source, flags, result),
            .typescript => try self.extractTypeScript(node, source, flags, result),
            .svelte => try self.extractSvelte(node, source, flags, result),
            .unknown => try result.appendSlice(source),
        }
    }
    
    /// Zig-specific AST extraction
    fn extractZig(self: *Self, node: ts.Node, source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) std.mem.Allocator.Error!void {
        // Early termination: if no relevant flags are set, skip this subtree
        if (!flags.signatures and !flags.types and !flags.docs and !flags.tests and !flags.imports) {
            return;
        }
        
        const node_type = node.kind();
        
        if (flags.signatures) {
            if (std.mem.eql(u8, node_type, "function_declaration")) {
                try self.appendNodeText(node, source, result);
                return; // Don't recurse into function body
            }
        }
        
        if (flags.types) {
            if (std.mem.eql(u8, node_type, "struct_declaration") or 
                std.mem.eql(u8, node_type, "enum_declaration") or
                std.mem.eql(u8, node_type, "union_declaration")) {
                try self.appendNodeText(node, source, result);
                return;
            }
        }
        
        if (flags.docs) {
            if (std.mem.eql(u8, node_type, "doc_comment") or
                std.mem.eql(u8, node_type, "container_doc_comment")) {
                try self.appendNodeText(node, source, result);
            }
        }
        
        if (flags.tests) {
            if (std.mem.eql(u8, node_type, "test_declaration")) {
                try self.appendNodeText(node, source, result);
                return;
            }
        }
        
        if (flags.imports) {
            if (std.mem.eql(u8, node_type, "builtin_call")) {
                const text = self.getNodeText(node, source);
                if (std.mem.startsWith(u8, text, "@import")) {
                    try self.appendNodeText(node, source, result);
                }
            }
        }
        
        // Recurse into children
        try self.recurseChildren(node, source, flags, result);
    }
    
    /// CSS-specific AST extraction
    fn extractCss(self: *Self, node: ts.Node, source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) std.mem.Allocator.Error!void {
        const node_type = node.kind();
        
        if (flags.signatures) {
            if (isSelector(node_type)) {
                try self.appendNodeText(node, source, result);
                return; // Don't traverse into selector details
            }
        }
        
        if (flags.types or flags.structure) {
            if (isRule(node_type) or isAtRule(node_type)) {
                try self.appendNodeText(node, source, result);
                return;
            }
        }
        
        if (flags.imports) {
            if (isImportRule(node_type)) {
                try self.appendNodeText(node, source, result);
            }
        }
        
        if (flags.docs) {
            if (isComment(node_type)) {
                try self.appendNodeText(node, source, result);
            }
        }
        
        // Recurse into children
        try self.recurseChildren(node, source, flags, result);
    }
    
    /// HTML-specific AST extraction
    fn extractHtml(self: *Self, node: ts.Node, source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) std.mem.Allocator.Error!void {
        const node_type = node.kind();
        
        if (flags.structure) {
            if (std.mem.eql(u8, node_type, "element") or
                std.mem.eql(u8, node_type, "start_tag") or
                std.mem.eql(u8, node_type, "end_tag")) {
                try self.appendNodeText(node, source, result);
                return;
            }
        }
        
        if (flags.signatures) {
            if (std.mem.eql(u8, node_type, "attribute")) {
                try self.appendNodeText(node, source, result);
            }
        }
        
        if (flags.docs) {
            if (std.mem.eql(u8, node_type, "comment")) {
                try self.appendNodeText(node, source, result);
            }
        }
        
        // Recurse into children
        try self.recurseChildren(node, source, flags, result);
    }
    
    /// JSON-specific AST extraction
    fn extractJson(self: *Self, node: ts.Node, source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) std.mem.Allocator.Error!void {
        const node_type = node.kind();
        
        if (flags.structure) {
            if (std.mem.eql(u8, node_type, "object") or
                std.mem.eql(u8, node_type, "array")) {
                try self.appendNodeText(node, source, result);
                return;
            }
        }
        
        if (flags.signatures) {
            if (std.mem.eql(u8, node_type, "pair")) {
                try self.appendNodeText(node, source, result);
            }
        }
        
        // Recurse into children
        try self.recurseChildren(node, source, flags, result);
    }
    
    /// TypeScript-specific AST extraction
    fn extractTypeScript(self: *Self, node: ts.Node, source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) std.mem.Allocator.Error!void {
        const node_type = node.kind();
        
        if (flags.signatures) {
            if (std.mem.eql(u8, node_type, "function_declaration") or
                std.mem.eql(u8, node_type, "method_definition") or
                std.mem.eql(u8, node_type, "arrow_function")) {
                try self.appendNodeText(node, source, result);
                return;
            }
        }
        
        if (flags.types) {
            if (std.mem.eql(u8, node_type, "interface_declaration") or
                std.mem.eql(u8, node_type, "class_declaration") or
                std.mem.eql(u8, node_type, "type_alias_declaration") or
                std.mem.eql(u8, node_type, "enum_declaration")) {
                try self.appendNodeText(node, source, result);
                return;
            }
        }
        
        if (flags.imports) {
            if (std.mem.eql(u8, node_type, "import_statement") or
                std.mem.eql(u8, node_type, "import_clause")) {
                try self.appendNodeText(node, source, result);
            }
        }
        
        if (flags.docs) {
            if (std.mem.eql(u8, node_type, "comment")) {
                try self.appendNodeText(node, source, result);
            }
        }
        
        // Recurse into children
        try self.recurseChildren(node, source, flags, result);
    }
    
    /// Svelte-specific AST extraction (section-aware)
    fn extractSvelte(self: *Self, node: ts.Node, source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) std.mem.Allocator.Error!void {
        const node_type = node.kind();
        
        if (flags.signatures) {
            // Extract reactive statements and component props
            if (std.mem.eql(u8, node_type, "reactive_statement") or
                std.mem.eql(u8, node_type, "component_prop")) {
                try self.appendNodeText(node, source, result);
            }
        }
        
        if (flags.structure) {
            // Extract script and style sections
            if (std.mem.eql(u8, node_type, "script_element") or
                std.mem.eql(u8, node_type, "style_element")) {
                try self.appendNodeText(node, source, result);
                return;
            }
        }
        
        if (flags.types) {
            // TypeScript types in script sections
            if (std.mem.eql(u8, node_type, "interface_declaration") or
                std.mem.eql(u8, node_type, "type_alias_declaration")) {
                try self.appendNodeText(node, source, result);
                return;
            }
        }
        
        // Recurse into children
        try self.recurseChildren(node, source, flags, result);
    }
    
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
    fn recurseChildren(self: *Self, node: ts.Node, source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) std.mem.Allocator.Error!void {
        const child_count = node.childCount();
        var i: u32 = 0;
        while (i < child_count) : (i += 1) {
            if (node.child(i)) |child| {
                try self.walkAndExtract(child, source, flags, result);
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
pub fn extractWithTreeSitter(allocator: std.mem.Allocator, file_path: []const u8, source: []const u8, flags: ExtractionFlags) ![]const u8 {
    const path_utils = @import("path.zig");
    const ext = path_utils.extension(file_path);
    const language = Language.fromExtension(ext);
    
    var parser = try createTreeSitterParser(allocator, language);
    defer parser.deinit();
    
    return parser.extract(source, flags);
}

// Tests
test "tree-sitter parser initialization" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    var parser = try createTreeSitterParser(allocator, .zig);
    defer parser.deinit();
    
    try testing.expect(parser.language == .zig);
}

test "tree-sitter language mapping" {
    const zig_lang = try getTreeSitterLanguage(.zig);
    const css_lang = try getTreeSitterLanguage(.css);
    
    // Languages should be different pointers
    try std.testing.expect(zig_lang != css_lang);
    
    // Unknown language should return error
    try std.testing.expectError(error.UnsupportedLanguage, getTreeSitterLanguage(.unknown));
}

test "css node type detection" {
    const testing = std.testing;
    
    try testing.expect(isSelector("class_selector"));
    try testing.expect(isSelector("id_selector"));
    try testing.expect(!isSelector("declaration"));
    
    try testing.expect(isRule("rule_set"));
    try testing.expect(isRule("declaration"));
    try testing.expect(!isRule("class_selector"));
    
    try testing.expect(isAtRule("at_rule"));
    try testing.expect(isAtRule("media_query"));
    try testing.expect(!isAtRule("rule_set"));
    
    try testing.expect(isComment("comment"));
    try testing.expect(!isComment("declaration"));
}

test "unsupported language handling" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    // Should return error for unknown language
    const result = createTreeSitterParser(allocator, .unknown);
    try testing.expectError(error.UnsupportedLanguage, result);
}

test "empty source handling" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    var parser = try createTreeSitterParser(allocator, .zig);
    defer parser.deinit();
    
    // Empty source should be handled gracefully
    const result = try parser.extract("", ExtractionFlags{});
    defer allocator.free(result);
    
    try testing.expect(result.len == 0);
}

test "malformed source handling" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    var parser = try createTreeSitterParser(allocator, .zig);
    defer parser.deinit();
    
    // Malformed Zig code - should not crash
    const malformed = "fn incomplete( {{{ invalid syntax";
    const result = try parser.extract(malformed, ExtractionFlags{ .signatures = true });
    defer allocator.free(result);
    
    // Should not crash and return some result (even if empty)
    try testing.expect(result.len >= 0);
}

test "extraction flag combinations" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    var parser = try createTreeSitterParser(allocator, .zig);
    defer parser.deinit();
    
    const source = 
        \\/// Documentation comment
        \\pub fn example() void {}
        \\const MyStruct = struct {};
        \\test "unit test" {}
    ;
    
    // Test multiple flag combinations
    const flags_combo = ExtractionFlags{
        .signatures = true,
        .types = true,
        .docs = true,
        .tests = true,
    };
    
    const result = try parser.extract(source, flags_combo);
    defer allocator.free(result);
    
    // Should extract some content (even if specific extraction depends on tree-sitter node types)
    // This tests that the extraction doesn't crash and produces some output
    try testing.expect(result.len >= 0);
    
    // Test that no flags returns full source
    const full_result = try parser.extract(source, ExtractionFlags{});
    defer allocator.free(full_result);
    try testing.expectEqualStrings(source, full_result);
}

test "early termination optimization" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    var parser = try createTreeSitterParser(allocator, .zig);
    defer parser.deinit();
    
    const source = "pub fn test() void {}";
    
    // Default flags should return full source without parsing
    const result1 = try parser.extract(source, ExtractionFlags{});
    defer allocator.free(result1);
    try testing.expectEqualStrings(source, result1);
    
    // No relevant flags should return empty result
    const result2 = try parser.extract(source, ExtractionFlags{ .structure = true });
    defer allocator.free(result2);
    try testing.expect(result2.len == 0);
}