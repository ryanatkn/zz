const std = @import("std");
const ts = @import("tree-sitter");

// Extern functions provided by tree-sitter C libraries
extern fn tree_sitter_zig() callconv(.C) *ts.Language;
extern fn tree_sitter_css() callconv(.C) *ts.Language;
extern fn tree_sitter_html() callconv(.C) *ts.Language;
extern fn tree_sitter_json() callconv(.C) *ts.Language;
extern fn tree_sitter_typescript() callconv(.C) *ts.Language;
extern fn tree_sitter_svelte() callconv(.C) *ts.Language;

pub const Language = enum {
    zig,
    css,
    html,
    json,
    typescript,
    svelte,
    unknown,

    pub fn fromExtension(ext: []const u8) Language {
        if (std.mem.eql(u8, ext, ".zig")) return .zig;
        if (std.mem.eql(u8, ext, ".css")) return .css;
        if (std.mem.eql(u8, ext, ".html") or std.mem.eql(u8, ext, ".htm")) return .html;
        if (std.mem.eql(u8, ext, ".json")) return .json;
        if (std.mem.eql(u8, ext, ".ts")) return .typescript;
        if (std.mem.eql(u8, ext, ".svelte")) return .svelte;
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
        // For now, only use tree-sitter for Zig
        // Other languages need language-specific node type handling
        if (language == .zig) {
            const parser = ts.Parser.create();
            try parser.setLanguage(tree_sitter_zig());
            return Parser{
                .allocator = allocator,
                .ts_parser = parser,
                .language = language,
            };
        }
        
        // Use simple extraction for all other languages
        return Parser{
            .allocator = allocator,
            .ts_parser = null,
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
        if (self.ts_parser != null and self.language != .unknown) {
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

        switch (self.language) {
            .zig => try self.extractZigSimple(source, flags, &result),
            .css => try self.extractCssSimple(source, flags, &result),
            .html => try self.extractHtmlSimple(source, flags, &result),
            .json => try self.extractJsonSimple(source, flags, &result),
            .typescript => try self.extractTypeScriptSimple(source, flags, &result),
            .svelte => try self.extractSvelteSimple(source, flags, &result),
            .unknown => {
                // For unknown languages, return full source
                try result.appendSlice(source);
            },
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
    
    fn extractCssSimple(_: *Parser, source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) !void {
        var lines = std.mem.tokenizeScalar(u8, source, '\n');
        
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t");
            
            // Skip empty lines
            if (trimmed.len == 0) continue;
            
            // For CSS, we want to extract based on flags
            if (flags.types or flags.structure) {
                // Always include the line for CSS when types or structure is requested
                try result.appendSlice(line);
                try result.append('\n');
            } else if (flags.signatures) {
                // CSS selectors only (class names, IDs, elements)
                if ((std.mem.startsWith(u8, trimmed, ".") or
                     std.mem.startsWith(u8, trimmed, "#") or
                     std.mem.indexOf(u8, line, "{") != null) and
                    !std.mem.startsWith(u8, trimmed, "/*")) {
                    try result.appendSlice(line);
                    try result.append('\n');
                }
            } else if (flags.imports) {
                if (std.mem.startsWith(u8, trimmed, "@import") or 
                    std.mem.startsWith(u8, trimmed, "@use")) {
                    try result.appendSlice(line);
                    try result.append('\n');
                }
            } else if (flags.docs) {
                if (std.mem.startsWith(u8, trimmed, "/*") or
                    std.mem.startsWith(u8, trimmed, "*")) {
                    try result.appendSlice(line);
                    try result.append('\n');
                }
            }
        }
    }
    
    fn extractHtmlSimple(_: *Parser, source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) !void {
        var lines = std.mem.tokenizeScalar(u8, source, '\n');
        
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t");
            
            // Skip empty lines
            if (trimmed.len == 0) continue;
            
            if (flags.structure or flags.types) {
                // HTML tags and structure
                if (std.mem.startsWith(u8, trimmed, "<") and !std.mem.startsWith(u8, trimmed, "<!--")) {
                    try result.appendSlice(line);
                    try result.append('\n');
                }
            }
            
            if (flags.signatures) {
                // Look for script tags and function definitions
                if (std.mem.indexOf(u8, line, "<script") != null or
                    std.mem.indexOf(u8, line, "function") != null or
                    std.mem.indexOf(u8, line, "onclick") != null or
                    std.mem.indexOf(u8, line, "onload") != null) {
                    try result.appendSlice(line);
                    try result.append('\n');
                }
            }
            
            if (flags.docs) {
                // HTML comments
                if (std.mem.indexOf(u8, trimmed, "<!--") != null or
                    std.mem.indexOf(u8, trimmed, "-->") != null) {
                    try result.appendSlice(line);
                    try result.append('\n');
                }
            }
        }
    }
    
    fn extractJsonSimple(_: *Parser, source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) !void {
        // JSON is structural, so we extract based on structure
        if (flags.structure or flags.types) {
            // For JSON, extract all structural elements
            var lines = std.mem.tokenizeScalar(u8, source, '\n');
            
            while (lines.next()) |line| {
                const trimmed = std.mem.trim(u8, line, " \t");
                
                // Skip empty lines
                if (trimmed.len == 0) continue;
                
                // Include all JSON structure
                try result.appendSlice(line);
                try result.append('\n');
            }
        } else if (flags.signatures) {
            // For signatures, just extract keys
            var lines = std.mem.tokenizeScalar(u8, source, '\n');
            
            while (lines.next()) |line| {
                const trimmed = std.mem.trim(u8, line, " \t");
                if (std.mem.indexOf(u8, trimmed, "\":") != null) {
                    try result.appendSlice(line);
                    try result.append('\n');
                }
            }
        }
    }
    
    fn extractTypeScriptSimple(_: *Parser, source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) !void {
        var lines = std.mem.tokenizeScalar(u8, source, '\n');
        var in_type = false;
        var brace_count: u32 = 0;
        
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t");
            
            // Track braces for multi-line types
            if (std.mem.indexOf(u8, line, "{") != null) {
                brace_count += 1;
                if (flags.types and (std.mem.indexOf(u8, trimmed, "interface") != null or
                    std.mem.indexOf(u8, trimmed, "class") != null or
                    std.mem.indexOf(u8, trimmed, "enum") != null)) {
                    in_type = true;
                }
            }
            if (std.mem.indexOf(u8, line, "}") != null) {
                if (brace_count > 0) brace_count -= 1;
                if (brace_count == 0) in_type = false;
            }
            
            if (flags.signatures) {
                if (std.mem.startsWith(u8, trimmed, "function ") or
                    std.mem.startsWith(u8, trimmed, "export function ") or
                    std.mem.startsWith(u8, trimmed, "async function ") or
                    std.mem.startsWith(u8, trimmed, "const ") or
                    std.mem.startsWith(u8, trimmed, "export const ") or
                    std.mem.indexOf(u8, trimmed, " => ") != null) {
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
                // Extract type definitions and their content
                if (in_type or
                    std.mem.startsWith(u8, trimmed, "interface ") or
                    std.mem.startsWith(u8, trimmed, "type ") or
                    std.mem.startsWith(u8, trimmed, "enum ") or
                    std.mem.startsWith(u8, trimmed, "class ") or
                    std.mem.startsWith(u8, trimmed, "export interface ") or
                    std.mem.startsWith(u8, trimmed, "export type ") or
                    std.mem.startsWith(u8, trimmed, "export enum ") or
                    std.mem.startsWith(u8, trimmed, "export class ")) {
                    try result.appendSlice(line);
                    try result.append('\n');
                }
            }
            
            if (flags.docs) {
                if (std.mem.startsWith(u8, trimmed, "/**") or
                    std.mem.startsWith(u8, trimmed, "*") or
                    std.mem.startsWith(u8, trimmed, "//")) {
                    try result.appendSlice(line);
                    try result.append('\n');
                }
            }
            
            if (flags.imports) {
                if (std.mem.startsWith(u8, trimmed, "import ") or
                    std.mem.startsWith(u8, trimmed, "export ") or
                    std.mem.startsWith(u8, trimmed, "require(")) {
                    try result.appendSlice(line);
                    try result.append('\n');
                }
            }
        }
    }
    
    fn extractSvelteSimple(_: *Parser, source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) !void {
        var lines = std.mem.tokenizeScalar(u8, source, '\n');
        var in_script = false;
        var in_style = false;
        
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t");
            
            // Track script and style sections
            if (std.mem.startsWith(u8, trimmed, "<script")) {
                in_script = true;
                if (flags.imports or flags.signatures) {
                    try result.appendSlice(line);
                    try result.append('\n');
                }
                continue;
            }
            if (std.mem.startsWith(u8, trimmed, "</script>")) {
                in_script = false;
                if (flags.imports or flags.signatures) {
                    try result.appendSlice(line);
                    try result.append('\n');
                }
                continue;
            }
            if (std.mem.startsWith(u8, trimmed, "<style")) {
                in_style = true;
                if (flags.types) {
                    try result.appendSlice(line);
                    try result.append('\n');
                }
                continue;
            }
            if (std.mem.startsWith(u8, trimmed, "</style>")) {
                in_style = false;
                if (flags.types) {
                    try result.appendSlice(line);
                    try result.append('\n');
                }
                continue;
            }
            
            if (in_script) {
                // TypeScript/JavaScript extraction within script tags
                if (flags.signatures or flags.types) {
                    if (std.mem.startsWith(u8, trimmed, "function ") or
                        std.mem.startsWith(u8, trimmed, "export ") or
                        std.mem.startsWith(u8, trimmed, "const ") or
                        std.mem.startsWith(u8, trimmed, "let ") or
                        std.mem.startsWith(u8, trimmed, "interface ") or
                        std.mem.startsWith(u8, trimmed, "type ") or
                        std.mem.indexOf(u8, trimmed, " => ") != null) {
                        try result.appendSlice(line);
                        try result.append('\n');
                    }
                }
                
                if (flags.imports) {
                    if (std.mem.startsWith(u8, trimmed, "import ")) {
                        try result.appendSlice(line);
                        try result.append('\n');
                    }
                }
            } else if (in_style) {
                // CSS extraction within style tags
                if (flags.types or flags.structure) {
                    try result.appendSlice(line);
                    try result.append('\n');
                }
            } else {
                // HTML template extraction
                if (flags.structure) {
                    if (std.mem.startsWith(u8, trimmed, "<") and !std.mem.startsWith(u8, trimmed, "<!--")) {
                        try result.appendSlice(line);
                        try result.append('\n');
                    }
                }
                
                if (flags.docs) {
                    if (std.mem.startsWith(u8, trimmed, "<!--")) {
                        try result.appendSlice(line);
                        try result.append('\n');
                    }
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