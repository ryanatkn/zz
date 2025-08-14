const std = @import("std");
const ts = @import("tree-sitter");

/// Unified AST infrastructure consolidating ast.zig, ast_walker.zig, and parser.zig
/// Clean, idiomatic Zig with zero backwards compatibility

// ============================================================================
// Language Detection and Mapping
// ============================================================================

pub const Language = enum {
    zig,
    css,
    html,
    json,
    typescript,
    svelte,
    c,
    cpp,
    python,
    rust,
    go,
    unknown,

    pub fn fromExtension(ext: []const u8) Language {
        if (std.mem.eql(u8, ext, ".zig")) return .zig;
        if (std.mem.eql(u8, ext, ".css")) return .css;
        if (std.mem.eql(u8, ext, ".html") or std.mem.eql(u8, ext, ".htm")) return .html;
        if (std.mem.eql(u8, ext, ".json")) return .json;
        if (std.mem.eql(u8, ext, ".ts") or std.mem.eql(u8, ext, ".tsx")) return .typescript;
        if (std.mem.eql(u8, ext, ".svelte")) return .svelte;
        if (std.mem.eql(u8, ext, ".c") or std.mem.eql(u8, ext, ".h")) return .c;
        if (std.mem.eql(u8, ext, ".cpp") or std.mem.eql(u8, ext, ".cc") or std.mem.eql(u8, ext, ".hpp")) return .cpp;
        if (std.mem.eql(u8, ext, ".py")) return .python;
        if (std.mem.eql(u8, ext, ".rs")) return .rust;
        if (std.mem.eql(u8, ext, ".go")) return .go;
        return .unknown;
    }
    
    pub fn toString(self: Language) []const u8 {
        return switch (self) {
            .zig => "zig",
            .css => "css",
            .html => "html",
            .json => "json",
            .typescript => "typescript",
            .svelte => "svelte",
            .c => "c",
            .cpp => "cpp",
            .python => "python",
            .rust => "rust",
            .go => "go",
            .unknown => "unknown",
        };
    }
};

// ============================================================================
// Extraction Configuration
// ============================================================================

pub const ExtractionFlags = struct {
    signatures: bool = false,
    types: bool = false,
    docs: bool = false,
    structure: bool = false,
    imports: bool = false,
    errors: bool = false,
    tests: bool = false,
    full: bool = false,

    pub fn isDefault(self: ExtractionFlags) bool {
        return !self.signatures and !self.types and !self.docs and 
               !self.structure and !self.imports and !self.errors and 
               !self.tests and !self.full;
    }

    pub fn setDefault(self: *ExtractionFlags) void {
        if (self.isDefault()) {
            self.full = true;
        }
    }
};

// ============================================================================
// AST Node Abstraction
// ============================================================================

pub const Node = struct {
    /// The actual tree-sitter node (if available)
    ts_node: ?ts.Node,
    /// Node type as string
    kind: []const u8,
    /// Source text for this node
    text: []const u8,
    /// Start/end byte offsets
    start_byte: u32,
    end_byte: u32,
    /// Line/column positions
    start_line: u32,
    start_column: u32,
    end_line: u32,
    end_column: u32,
    
    /// Create from tree-sitter node
    pub fn fromTsNode(node: ts.Node, source: []const u8) Node {
        const start = node.startByte();
        const end = node.endByte();
        const text = if (end <= source.len) source[start..end] else "";
        const start_point = node.startPoint();
        const end_point = node.endPoint();
        
        return Node{
            .ts_node = node,
            .kind = node.kind(),
            .text = text,
            .start_byte = start,
            .end_byte = end,
            .start_line = start_point.row,
            .start_column = start_point.column,
            .end_line = end_point.row,
            .end_column = end_point.column,
        };
    }
    
    /// Create synthetic node for text-based extraction
    pub fn synthetic(kind: []const u8, text: []const u8, start: u32, end: u32) Node {
        return Node{
            .ts_node = null,
            .kind = kind,
            .text = text,
            .start_byte = start,
            .end_byte = end,
            .start_line = 0,
            .start_column = 0,
            .end_line = 0,
            .end_column = 0,
        };
    }
    
    /// Check if node has error
    pub fn hasError(self: *const Node) bool {
        if (self.ts_node) |node| {
            return node.hasError();
        }
        return false;
    }
    
    /// Get child count
    pub fn childCount(self: *const Node) u32 {
        if (self.ts_node) |node| {
            return node.childCount();
        }
        return 0;
    }
    
    /// Get child at index
    pub fn child(self: *const Node, index: u32, source: []const u8) ?Node {
        if (self.ts_node) |node| {
            if (node.child(index)) |child_node| {
                return Node.fromTsNode(child_node, source);
            }
        }
        return null;
    }
};

// ============================================================================
// Unified Extractor
// ============================================================================

pub const Extractor = struct {
    allocator: std.mem.Allocator,
    language: Language,
    use_ast: bool,
    
    pub fn init(allocator: std.mem.Allocator, language: Language) Extractor {
        return Extractor{
            .allocator = allocator,
            .language = language,
            .use_ast = false, // Default to text-based
        };
    }
    
    pub fn initWithAst(allocator: std.mem.Allocator, language: Language) Extractor {
        return Extractor{
            .allocator = allocator,
            .language = language,
            .use_ast = true,
        };
    }
    
    /// Main extraction entry point
    pub fn extract(self: Extractor, source: []const u8, flags: ExtractionFlags) ![]const u8 {
        var mutable_flags = flags;
        mutable_flags.setDefault();
        
        // Return full source if requested
        if (mutable_flags.full) {
            return self.allocator.dupe(u8, source);
        }
        
        // Choose extraction method
        if (self.use_ast and self.language != .unknown) {
            return self.extractWithAst(source, mutable_flags);
        } else {
            return self.extractText(source, mutable_flags);
        }
    }
    
    /// AST-based extraction using tree-sitter
    fn extractWithAst(self: Extractor, source: []const u8, flags: ExtractionFlags) ![]const u8 {
        // Try to use tree-sitter parser
        const TreeSitterParser = @import("tree_sitter_parser.zig").TreeSitterParser;
        var parser = TreeSitterParser.init(self.allocator, self.language) catch {
            // Fall back to text extraction if tree-sitter fails
            return self.extractText(source, flags);
        };
        defer parser.deinit();
        
        return parser.extract(source, flags) catch {
            // Fall back on parse errors
            return self.extractText(source, flags);
        };
    }
    
    /// Text-based extraction (fallback)
    fn extractText(self: Extractor, source: []const u8, flags: ExtractionFlags) ![]const u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        defer result.deinit();
        
        // Dispatch to language-specific text extraction
        switch (self.language) {
            .zig => try self.extractZigText(source, flags, &result),
            .typescript => try self.extractTypeScriptText(source, flags, &result),
            .python => try self.extractPythonText(source, flags, &result),
            .rust => try self.extractRustText(source, flags, &result),
            .go => try self.extractGoText(source, flags, &result),
            else => {
                // Generic extraction or full source
                try result.appendSlice(source);
            }
        }
        
        return result.toOwnedSlice();
    }
    
    // Simple text-based extraction implementations
    fn extractZigText(self: Extractor, source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) !void {
        _ = self;
        var lines = std.mem.splitScalar(u8, source, '\n');
        
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t");
            
            // Functions
            if (flags.signatures and std.mem.startsWith(u8, trimmed, "pub fn ")) {
                try result.appendSlice(line);
                try result.append('\n');
            }
            
            // Types
            if (flags.types and (std.mem.startsWith(u8, trimmed, "pub const ") or
                                 std.mem.startsWith(u8, trimmed, "const ") or
                                 std.mem.startsWith(u8, trimmed, "pub struct") or
                                 std.mem.startsWith(u8, trimmed, "pub enum"))) {
                try result.appendSlice(line);
                try result.append('\n');
            }
            
            // Imports
            if (flags.imports and std.mem.indexOf(u8, line, "@import(") != null) {
                try result.appendSlice(line);
                try result.append('\n');
            }
            
            // Tests
            if (flags.tests and std.mem.startsWith(u8, trimmed, "test ")) {
                try result.appendSlice(line);
                try result.append('\n');
            }
        }
    }
    
    fn extractTypeScriptText(self: Extractor, source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) !void {
        _ = self;
        var lines = std.mem.splitScalar(u8, source, '\n');
        
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t");
            
            // Functions
            if (flags.signatures and (std.mem.startsWith(u8, trimmed, "function ") or
                                      std.mem.startsWith(u8, trimmed, "export function ") or
                                      std.mem.indexOf(u8, trimmed, "=>") != null)) {
                try result.appendSlice(line);
                try result.append('\n');
            }
            
            // Types
            if (flags.types and (std.mem.startsWith(u8, trimmed, "interface ") or
                                 std.mem.startsWith(u8, trimmed, "type ") or
                                 std.mem.startsWith(u8, trimmed, "class ") or
                                 std.mem.startsWith(u8, trimmed, "enum "))) {
                try result.appendSlice(line);
                try result.append('\n');
            }
            
            // Imports
            if (flags.imports and (std.mem.startsWith(u8, trimmed, "import ") or
                                  std.mem.startsWith(u8, trimmed, "export "))) {
                try result.appendSlice(line);
                try result.append('\n');
            }
        }
    }
    
    fn extractPythonText(self: Extractor, source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) !void {
        _ = self;
        var lines = std.mem.splitScalar(u8, source, '\n');
        
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t");
            
            if (flags.signatures and std.mem.startsWith(u8, trimmed, "def ")) {
                try result.appendSlice(line);
                try result.append('\n');
            }
            
            if (flags.types and std.mem.startsWith(u8, trimmed, "class ")) {
                try result.appendSlice(line);
                try result.append('\n');
            }
            
            if (flags.imports and (std.mem.startsWith(u8, trimmed, "import ") or
                                  std.mem.startsWith(u8, trimmed, "from "))) {
                try result.appendSlice(line);
                try result.append('\n');
            }
        }
    }
    
    fn extractRustText(self: Extractor, source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) !void {
        _ = self;
        var lines = std.mem.splitScalar(u8, source, '\n');
        
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t");
            
            if (flags.signatures and (std.mem.startsWith(u8, trimmed, "fn ") or
                                      std.mem.startsWith(u8, trimmed, "pub fn "))) {
                try result.appendSlice(line);
                try result.append('\n');
            }
            
            if (flags.types and (std.mem.startsWith(u8, trimmed, "struct ") or
                                std.mem.startsWith(u8, trimmed, "enum ") or
                                std.mem.startsWith(u8, trimmed, "trait "))) {
                try result.appendSlice(line);
                try result.append('\n');
            }
            
            if (flags.imports and std.mem.startsWith(u8, trimmed, "use ")) {
                try result.appendSlice(line);
                try result.append('\n');
            }
        }
    }
    
    fn extractGoText(self: Extractor, source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) !void {
        _ = self;
        var lines = std.mem.splitScalar(u8, source, '\n');
        
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t");
            
            if (flags.signatures and std.mem.startsWith(u8, trimmed, "func ")) {
                try result.appendSlice(line);
                try result.append('\n');
            }
            
            if (flags.types and (std.mem.startsWith(u8, trimmed, "type ") or
                                std.mem.startsWith(u8, trimmed, "struct "))) {
                try result.appendSlice(line);
                try result.append('\n');
            }
            
            if (flags.imports and std.mem.startsWith(u8, trimmed, "import ")) {
                try result.appendSlice(line);
                try result.append('\n');
            }
        }
    }
};

// ============================================================================
// Visitor Pattern for AST Traversal
// ============================================================================

pub const Visitor = struct {
    /// Function type for visiting nodes
    pub const VisitFn = *const fn (node: *const Node, context: *anyopaque) anyerror!void;
    
    /// Visit a node and its children
    pub fn visit(
        node: *const Node,
        source: []const u8,
        visitor_fn: VisitFn,
        context: *anyopaque,
    ) !void {
        // Visit current node
        try visitor_fn(node, context);
        
        // Visit children
        const count = node.childCount();
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            if (node.child(i, source)) |child_node| {
                var child = child_node;
                try visit(&child, source, visitor_fn, context);
            }
        }
    }
    
    /// Helper to check if node type should be extracted based on flags
    pub fn shouldExtract(node_type: []const u8, flags: ExtractionFlags) bool {
        // Functions
        if (std.mem.eql(u8, node_type, "function_definition") or
            std.mem.eql(u8, node_type, "function_declaration") or
            std.mem.eql(u8, node_type, "method_definition")) {
            return flags.signatures;
        }
        
        // Types
        if (std.mem.eql(u8, node_type, "struct") or
            std.mem.eql(u8, node_type, "class") or
            std.mem.eql(u8, node_type, "interface") or
            std.mem.eql(u8, node_type, "enum")) {
            return flags.types;
        }
        
        // Imports
        if (std.mem.eql(u8, node_type, "import_statement") or
            std.mem.eql(u8, node_type, "import")) {
            return flags.imports;
        }
        
        // Tests
        if (std.mem.eql(u8, node_type, "test_decl") or
            std.mem.startsWith(u8, node_type, "test_")) {
            return flags.tests;
        }
        
        // Comments/docs
        if (std.mem.eql(u8, node_type, "comment") or
            std.mem.eql(u8, node_type, "doc_comment")) {
            return flags.docs;
        }
        
        return flags.full;
    }
};

// ============================================================================
// Public API
// ============================================================================

/// Detect language from file path
pub fn detectLanguage(path: []const u8) Language {
    const ext = std.fs.path.extension(path);
    return Language.fromExtension(ext);
}

/// Create an extractor for a specific language
pub fn createExtractor(allocator: std.mem.Allocator, language: Language) Extractor {
    return Extractor.init(allocator, language);
}

/// Create an AST-based extractor
pub fn createAstExtractor(allocator: std.mem.Allocator, language: Language) Extractor {
    return Extractor.initWithAst(allocator, language);
}

/// Extract code from source with automatic language detection
pub fn extractCode(
    allocator: std.mem.Allocator,
    file_path: []const u8,
    source: []const u8,
    flags: ExtractionFlags,
) ![]const u8 {
    const language = detectLanguage(file_path);
    var extractor = createExtractor(allocator, language);
    return extractor.extract(source, flags);
}

test "language detection" {
    const testing = std.testing;
    
    try testing.expect(detectLanguage("test.zig") == .zig);
    try testing.expect(detectLanguage("style.css") == .css);
    try testing.expect(detectLanguage("index.html") == .html);
    try testing.expect(detectLanguage("data.json") == .json);
    try testing.expect(detectLanguage("app.ts") == .typescript);
    try testing.expect(detectLanguage("component.svelte") == .svelte);
    try testing.expect(detectLanguage("main.c") == .c);
    try testing.expect(detectLanguage("lib.rs") == .rust);
    try testing.expect(detectLanguage("server.go") == .go);
    try testing.expect(detectLanguage("script.py") == .python);
    try testing.expect(detectLanguage("unknown.xyz") == .unknown);
}

test "extraction flags" {
    const testing = std.testing;
    
    var flags = ExtractionFlags{};
    try testing.expect(flags.isDefault());
    
    flags.setDefault();
    try testing.expect(flags.full);
    
    flags = ExtractionFlags{ .signatures = true };
    try testing.expect(!flags.isDefault());
}

test "basic text extraction" {
    const testing = std.testing;
    
    const source = 
        \\pub fn test() void {}
        \\const value = 42;
        \\test "example" {}
    ;
    
    var extractor = createExtractor(testing.allocator, .zig);
    
    // Extract signatures
    const sigs = try extractor.extract(source, .{ .signatures = true });
    defer testing.allocator.free(sigs);
    try testing.expect(std.mem.indexOf(u8, sigs, "pub fn test") != null);
    
    // Extract types
    const types = try extractor.extract(source, .{ .types = true });
    defer testing.allocator.free(types);
    try testing.expect(std.mem.indexOf(u8, types, "const value") != null);
    
    // Extract tests
    const tests = try extractor.extract(source, .{ .tests = true });
    defer testing.allocator.free(tests);
    try testing.expect(std.mem.indexOf(u8, tests, "test \"example\"") != null);
}

// ============================================================================
// AST Walker - Unified traversal for all parsers
// ============================================================================

pub const AstWalker = struct {
    pub const WalkContext = struct {
        allocator: std.mem.Allocator,
        result: *std.ArrayList(u8),
        flags: ExtractionFlags,
        source: []const u8,
    };
    
    pub fn walkNodeWithVisitor(
        allocator: std.mem.Allocator,
        root: *const Node,
        source: []const u8,
        flags: ExtractionFlags,
        result: *std.ArrayList(u8),
        visitor_fn: fn(*WalkContext, *const Node) anyerror!void
    ) !void {
        var context = WalkContext{
            .allocator = allocator,
            .result = result,
            .flags = flags,
            .source = source,
        };
        
        try walkNodeRecursive(&context, root, visitor_fn);
    }
    
    fn walkNodeRecursive(
        context: *WalkContext,
        node: *const Node,
        visitor_fn: fn(*WalkContext, *const Node) anyerror!void
    ) !void {
        try visitor_fn(context, node);
        
        // Recurse into children
        for (node.children) |child| {
            try walkNodeRecursive(context, &child, visitor_fn);
        }
    }
    
    pub const GenericVisitor = struct {
        pub fn visitNode(context: *WalkContext, node: *const Node) !void {
            // Default implementation - extract text if node matches flags
            if (shouldExtractNode(context.flags, node.kind)) {
                try context.result.appendSlice(node.text);
                try context.result.append('\n');
            }
        }
    };
    
    fn shouldExtractNode(flags: ExtractionFlags, kind: []const u8) bool {
        if (flags.full) return true;
        
        if (flags.signatures and (std.mem.eql(u8, kind, "function") or 
                                  std.mem.eql(u8, kind, "method"))) {
            return true;
        }
        
        if (flags.types and (std.mem.eql(u8, kind, "class") or
                             std.mem.eql(u8, kind, "interface") or
                             std.mem.eql(u8, kind, "struct"))) {
            return true;
        }
        
        if (flags.imports and std.mem.eql(u8, kind, "import")) {
            return true;
        }
        
        if (flags.tests and std.mem.eql(u8, kind, "test")) {
            return true;
        }
        
        return false;
    }
};