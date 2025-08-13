const std = @import("std");
const ts = @import("tree-sitter");

// Extern function provided by tree-sitter-zig C library
extern fn tree_sitter_zig() callconv(.C) *ts.Language;

pub const Language = enum {
    zig,
    typescript,
    javascript,
    rust,
    go,
    python,
    c,
    cpp,
    unknown,

    pub fn fromExtension(ext: []const u8) Language {
        if (std.mem.eql(u8, ext, ".zig")) return .zig;
        if (std.mem.eql(u8, ext, ".ts") or std.mem.eql(u8, ext, ".tsx")) return .typescript;
        if (std.mem.eql(u8, ext, ".js") or std.mem.eql(u8, ext, ".jsx")) return .javascript;
        if (std.mem.eql(u8, ext, ".rs")) return .rust;
        if (std.mem.eql(u8, ext, ".go")) return .go;
        if (std.mem.eql(u8, ext, ".py")) return .python;
        if (std.mem.eql(u8, ext, ".c") or std.mem.eql(u8, ext, ".h")) return .c;
        if (std.mem.eql(u8, ext, ".cpp") or std.mem.eql(u8, ext, ".cc") or std.mem.eql(u8, ext, ".hpp")) return .cpp;
        return .unknown;
    }
};

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
            self.full = true; // Default to full source for backward compatibility
        }
    }
};

pub const Parser = struct {
    allocator: std.mem.Allocator,
    ts_parser: ?*ts.Parser,
    language: Language,

    pub fn init(allocator: std.mem.Allocator, language: Language) !Parser {
        const parser = ts.Parser.create();
        
        // Set language based on type
        if (language == .zig) {
            try parser.setLanguage(tree_sitter_zig());
        }
        // TODO: Add other languages as we get their grammars
        
        return Parser{
            .allocator = allocator,
            .ts_parser = parser,
            .language = language,
        };
    }

    pub fn deinit(self: *Parser) void {
        if (self.ts_parser) |parser| {
            parser.destroy();
        }
    }

    pub fn extract(self: *Parser, source: []const u8, flags: ExtractionFlags) ![]const u8 {
        // For now, if full flag is set or no specific flags, return full source
        if (flags.full or flags.isDefault()) {
            return self.allocator.dupe(u8, source);
        }

        // Try AST-based extraction for supported languages
        if (self.ts_parser != null and self.language == .zig) {
            return self.extractWithTreeSitter(source, flags) catch |err| {
                // Fall back to simple extraction on error
                std.debug.print("Tree-sitter extraction failed: {}, falling back to simple\n", .{err});
                return self.extractSimple(source, flags);
            };
        }
        
        // Fall back to simple extraction for unsupported languages
        return self.extractSimple(source, flags);
    }

    fn extractSimple(self: *Parser, source: []const u8, flags: ExtractionFlags) ![]const u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        defer result.deinit();

        if (self.language == .zig) {
            try self.extractZigSimple(source, flags, &result);
        } else {
            // For other languages, return full source for now
            try result.appendSlice(source);
        }

        return result.toOwnedSlice();
    }

    fn extractZigSimple(_: *Parser, source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) !void {
        var lines = std.mem.tokenizeScalar(u8, source, '\n');
        
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t");
            
            // Extract based on flags
            if (flags.signatures) {
                if (std.mem.startsWith(u8, trimmed, "pub fn") or 
                    std.mem.startsWith(u8, trimmed, "fn")) {
                    // Extract until the opening brace or semicolon
                    if (std.mem.indexOf(u8, line, "{")) |brace_pos| {
                        try result.appendSlice(line[0..brace_pos + 1]);
                        try result.append('\n');
                    } else {
                        try result.appendSlice(line);
                        try result.append('\n');
                    }
                }
            }
            
            if (flags.types) {
                if (std.mem.startsWith(u8, trimmed, "pub const") or
                    std.mem.startsWith(u8, trimmed, "const") or
                    std.mem.startsWith(u8, trimmed, "pub var") or
                    std.mem.startsWith(u8, trimmed, "var")) {
                    try result.appendSlice(line);
                    try result.append('\n');
                }
            }
            
            if (flags.docs) {
                if (std.mem.startsWith(u8, trimmed, "///") or
                    std.mem.startsWith(u8, trimmed, "//!")) {
                    try result.appendSlice(line);
                    try result.append('\n');
                }
            }
            
            if (flags.imports) {
                if (std.mem.indexOf(u8, trimmed, "@import") != null) {
                    try result.appendSlice(line);
                    try result.append('\n');
                }
            }
            
            if (flags.errors) {
                if (std.mem.indexOf(u8, line, "error") != null or
                    std.mem.indexOf(u8, line, "catch") != null or
                    std.mem.indexOf(u8, line, "try") != null) {
                    try result.appendSlice(line);
                    try result.append('\n');
                }
            }
            
            if (flags.tests) {
                if (std.mem.startsWith(u8, trimmed, "test")) {
                    try result.appendSlice(line);
                    try result.append('\n');
                }
            }
        }
    }
    
    fn extractWithTreeSitter(self: *Parser, source: []const u8, flags: ExtractionFlags) ![]const u8 {
        const parser = self.ts_parser orelse return error.NoParser;
        
        // Parse the source code
        const tree = parser.parseString(source, null) orelse return error.ParseFailed;
        defer tree.destroy();
        
        const root = tree.rootNode();
        
        var result = std.ArrayList(u8).init(self.allocator);
        defer result.deinit();
        
        // Walk the tree and extract based on flags
        try self.walkNode(root, source, flags, &result);
        
        return result.toOwnedSlice();
    }
    
    fn walkNode(self: *Parser, node: ts.Node, source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) !void {
        const node_type = node.kind();
        
        // Extract based on node type and flags
        if (flags.signatures) {
            if (std.mem.eql(u8, node_type, "function_declaration")) {
                const start = node.startByte();
                const end = node.endByte();
                try result.appendSlice(source[start..end]);
                try result.append('\n');
                return; // Don't recurse into function bodies for signatures
            }
        }
        
        if (flags.types) {
            if (std.mem.eql(u8, node_type, "struct_declaration") or 
                std.mem.eql(u8, node_type, "enum_declaration") or
                std.mem.eql(u8, node_type, "union_declaration")) {
                const start = node.startByte();
                const end = node.endByte();
                try result.appendSlice(source[start..end]);
                try result.append('\n');
                return; // Don't recurse into type bodies
            }
        }
        
        if (flags.docs) {
            if (std.mem.eql(u8, node_type, "doc_comment") or
                std.mem.eql(u8, node_type, "container_doc_comment")) {
                const start = node.startByte();
                const end = node.endByte();
                try result.appendSlice(source[start..end]);
                try result.append('\n');
            }
        }
        
        if (flags.tests) {
            if (std.mem.eql(u8, node_type, "test_declaration")) {
                const start = node.startByte();
                const end = node.endByte();
                try result.appendSlice(source[start..end]);
                try result.append('\n');
                return; // Don't recurse into test bodies
            }
        }
        
        // Recurse into children
        const child_count = node.childCount();
        var i: u32 = 0;
        while (i < child_count) : (i += 1) {
            const child = node.child(i) orelse continue;
            try self.walkNode(child, source, flags, result);
        }
    }
};