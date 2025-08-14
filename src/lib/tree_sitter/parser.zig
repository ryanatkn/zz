const std = @import("std");
const ts = @import("tree-sitter");
const Node = @import("node.zig").Node;
const Language = @import("../language/detection.zig").Language;

/// Parser cache for managing tree-sitter parsers
pub const ParserCache = struct {
    allocator: std.mem.Allocator,
    parsers: std.HashMap(Language, *ts.Parser, std.hash_map.AutoContext(Language), std.hash_map.default_max_load_percentage),

    pub fn init(allocator: std.mem.Allocator) ParserCache {
        return ParserCache{
            .allocator = allocator,
            .parsers = std.HashMap(Language, *ts.Parser, std.hash_map.AutoContext(Language), std.hash_map.default_max_load_percentage).init(allocator),
        };
    }

    pub fn deinit(self: *ParserCache) void {
        var iterator = self.parsers.valueIterator();
        while (iterator.next()) |parser| {
            parser.*.destroy();
        }
        self.parsers.deinit();
    }

    pub fn getParser(self: *ParserCache, language: Language) !*ts.Parser {
        if (self.parsers.get(language)) |parser| {
            return parser;
        }

        // Create new parser for this language
        const parser = ts.Parser.create();
        const grammar = try getGrammarForLanguage(language);
        try parser.setLanguage(grammar);

        try self.parsers.put(language, parser);
        return parser;
    }
};

/// Tree-sitter parser wrapper with caching and error handling
pub const TreeSitterParser = struct {
    allocator: std.mem.Allocator,
    cache: ParserCache,

    pub fn init(allocator: std.mem.Allocator) TreeSitterParser {
        return TreeSitterParser{
            .allocator = allocator,
            .cache = ParserCache.init(allocator),
        };
    }

    pub fn deinit(self: *TreeSitterParser) void {
        self.cache.deinit();
    }

    /// Parse source code and return wrapped tree
    pub fn parse(self: *TreeSitterParser, source: []const u8, language: Language) !ParseResult {
        const parser = try self.cache.getParser(language);

        const tree = parser.parseString(source, null) orelse return ParseError.ParseFailed;

        return ParseResult{
            .tree = tree,
            .root_node = Node.fromTsNode(tree.rootNode(), source),
            .source = source,
        };
    }

    /// Parse with existing tree for incremental parsing
    pub fn parseIncremental(self: *TreeSitterParser, source: []const u8, language: Language, old_tree: *ts.Tree) !ParseResult {
        const parser = try self.cache.getParser(language);

        const tree = parser.parseString(source, old_tree) orelse return ParseError.ParseFailed;

        return ParseResult{
            .tree = tree,
            .root_node = Node.fromTsNode(tree.rootNode(), source),
            .source = source,
        };
    }
};

/// Result of parsing operation
pub const ParseResult = struct {
    tree: *ts.Tree,
    root_node: Node,
    source: []const u8,

    pub fn deinit(self: *ParseResult) void {
        self.tree.destroy();
    }

    /// Check if parse had errors
    pub fn hasError(self: *const ParseResult) bool {
        return self.root_node.hasError();
    }

    /// Get all error nodes
    pub fn getErrorNodes(self: *const ParseResult, allocator: std.mem.Allocator) ![]Node {
        var errors = std.ArrayList(Node).init(allocator);
        try self.collectErrorNodes(&errors, &self.root_node);
        return errors.toOwnedSlice();
    }

    fn collectErrorNodes(self: *const ParseResult, errors: *std.ArrayList(Node), node: *const Node) !void {
        if (node.hasError()) {
            try errors.append(node.*);
        }

        const count = node.childCount();
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            if (node.child(i, self.source)) |child| {
                var child_node = child;
                try self.collectErrorNodes(errors, &child_node);
            }
        }
    }
};

/// Parse errors
pub const ParseError = error{
    ParseFailed,
    UnsupportedLanguage,
    GrammarLoadFailed,
};

/// Get tree-sitter grammar for language
fn getGrammarForLanguage(language: Language) !*ts.Language {
    return switch (language) {
        .zig => tree_sitter_zig(),
        .css => tree_sitter_css(),
        .html => tree_sitter_html(),
        .json => tree_sitter_json(),
        .typescript => tree_sitter_typescript(),
        .svelte => tree_sitter_svelte(),
        else => ParseError.UnsupportedLanguage,
    };
}

// External grammar functions (defined in build.zig)
extern fn tree_sitter_zig() *ts.Language;
extern fn tree_sitter_css() *ts.Language;
extern fn tree_sitter_html() *ts.Language;
extern fn tree_sitter_json() *ts.Language;
extern fn tree_sitter_typescript() *ts.Language;
extern fn tree_sitter_svelte() *ts.Language;
