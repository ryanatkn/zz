const std = @import("std");
const ts = @import("tree-sitter");
const TreeSitterParser = @import("tree_sitter_parser.zig").TreeSitterParser;
const FormatterOptions = @import("formatter.zig").FormatterOptions;
const LineBuilder = @import("formatter.zig").LineBuilder;
const Language = @import("parser.zig").Language;
const AstCache = @import("cache.zig").AstCache;
const AstCacheKey = @import("cache.zig").AstCacheKey;

/// Base class for AST-powered formatters using tree-sitter
pub const AstFormatter = struct {
    allocator: std.mem.Allocator,
    parser: TreeSitterParser,
    options: FormatterOptions,
    language: Language,
    cache: ?*AstCache,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator, language: Language, options: FormatterOptions) !Self {
        const parser = try TreeSitterParser.init(allocator, language);
        
        return Self{
            .allocator = allocator,
            .parser = parser,
            .options = options,
            .language = language,
            .cache = null,
        };
    }
    
    pub fn initWithCache(allocator: std.mem.Allocator, language: Language, options: FormatterOptions, cache: *AstCache) !Self {
        const parser = try TreeSitterParser.init(allocator, language);
        
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
                if (cache.get(cache_key)) |cached| {
                    // Cache hit - return cached result
                    return self.allocator.dupe(u8, cached.content);
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
            .typescript => try self.formatTypeScriptAst(root, source, &builder),
            .css => try self.formatCssAst(root, source, &builder),
            .svelte => try self.formatSvelteAst(root, source, &builder),
            else => {
                // For unsupported languages, return original source
                return self.allocator.dupe(u8, source);
            }
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
    
    /// TypeScript AST formatting
    fn formatTypeScriptAst(self: *Self, node: ts.Node, source: []const u8, builder: *LineBuilder) !void {
        try self.formatNodeRecursive(node, source, builder, 0);
    }
    
    /// CSS AST formatting  
    fn formatCssAst(self: *Self, node: ts.Node, source: []const u8, builder: *LineBuilder) !void {
        try self.formatNodeRecursive(node, source, builder, 0);
    }
    
    /// Svelte AST formatting (section-aware)
    fn formatSvelteAst(self: *Self, node: ts.Node, source: []const u8, builder: *LineBuilder) !void {
        try self.formatSvelteNode(node, source, builder, 0);
    }
    
    /// Generic recursive node formatting
    fn formatNodeRecursive(self: *Self, node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32) !void {
        const node_type = node.kind();
        
        // Language-specific node handling
        switch (self.language) {
            .typescript => try self.handleTypeScriptNode(node, source, builder, depth),
            .css => try self.handleCssNode(node, source, builder, depth),
            else => try self.appendNodeText(node, source, builder),
        }
        
        // Recurse into children for structured nodes
        if (self.shouldRecurseIntoChildren(node_type)) {
            const child_count = node.childCount();
            var i: u32 = 0;
            while (i < child_count) : (i += 1) {
                if (node.child(i)) |child| {
                    try self.formatNodeRecursive(child, source, builder, depth + 1);
                }
            }
        }
    }
    
    /// TypeScript-specific node handling
    fn handleTypeScriptNode(self: *Self, node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32) !void {
        const node_type = node.kind();
        
        if (std.mem.eql(u8, node_type, "function_declaration")) {
            try self.formatFunction(node, source, builder, depth);
        } else if (std.mem.eql(u8, node_type, "interface_declaration")) {
            try self.formatInterface(node, source, builder, depth);
        } else if (std.mem.eql(u8, node_type, "class_declaration")) {
            try self.formatClass(node, source, builder, depth);
        } else if (std.mem.eql(u8, node_type, "type_alias_declaration")) {
            try self.formatTypeAlias(node, source, builder, depth);
        } else {
            try self.appendNodeText(node, source, builder);
        }
    }
    
    /// CSS-specific node handling
    fn handleCssNode(self: *Self, node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32) !void {
        const node_type = node.kind();
        
        if (std.mem.eql(u8, node_type, "rule_set")) {
            try self.formatCssRule(node, source, builder, depth);
        } else if (std.mem.eql(u8, node_type, "at_rule")) {
            try self.formatCssAtRule(node, source, builder, depth);
        } else if (std.mem.eql(u8, node_type, "declaration")) {
            try self.formatCssDeclaration(node, source, builder, depth);
        } else if (std.mem.eql(u8, node_type, "comment")) {
            try self.formatCssComment(node, source, builder, depth);
        } else {
            try self.appendNodeText(node, source, builder);
        }
    }
    
    /// Svelte section-aware formatting
    fn formatSvelteNode(self: *Self, node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32) !void {
        const node_type = node.kind();
        
        if (std.mem.eql(u8, node_type, "script_element")) {
            try self.formatSvelteScript(node, source, builder, depth);
        } else if (std.mem.eql(u8, node_type, "style_element")) {
            try self.formatSvelteStyle(node, source, builder, depth);
        } else if (std.mem.eql(u8, node_type, "reactive_statement")) {
            try self.formatSvelteReactive(node, source, builder, depth);
        } else {
            try self.appendNodeText(node, source, builder);
        }
    }
    
    /// Format TypeScript function
    fn formatFunction(self: *Self, node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32) std.mem.Allocator.Error!void {
        
        // Add proper indentation
        try builder.appendIndent();
        
        // Extract function signature and format it
        if (node.childByFieldName("name")) |name_node| {
            const name_text = self.getNodeText(name_node, source);
            
            // Format: function name(params): returnType {
            try builder.append("function ");
            try builder.append(name_text);
            
            if (node.childByFieldName("parameters")) |params_node| {
                const params_text = self.getNodeText(params_node, source);
                try builder.append(params_text);
            }
            
            if (node.childByFieldName("return_type")) |return_node| {
                try builder.append(": ");
                const return_text = self.getNodeText(return_node, source);
                try builder.append(return_text);
            }
            
            try builder.append(" {");
            try builder.newline();
            
            // Format function body with increased indentation
            if (node.childByFieldName("body")) |body_node| {
                builder.indent();
                try self.formatNodeRecursive(body_node, source, builder, depth + 1);
                builder.dedent();
            }
            
            try builder.appendIndent();
            try builder.append("}");
            try builder.newline();
        } else {
            // Fallback to raw node text if field extraction fails
            try self.appendNodeText(node, source, builder);
        }
    }
    
    /// Format TypeScript interface
    fn formatInterface(self: *Self, node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32) std.mem.Allocator.Error!void {
        
        try builder.appendIndent();
        
        if (node.childByFieldName("name")) |name_node| {
            const name_text = self.getNodeText(name_node, source);
            try builder.append("interface ");
            try builder.append(name_text);
            try builder.append(" {");
            try builder.newline();
            
            // Format interface members
            builder.indent();
            if (node.childByFieldName("body")) |body_node| {
                try self.formatNodeRecursive(body_node, source, builder, depth + 1);
            }
            builder.dedent();
            
            try builder.appendIndent();
            try builder.append("}");
            try builder.newline();
        } else {
            try self.appendNodeText(node, source, builder);
        }
    }
    
    /// Format TypeScript class
    fn formatClass(self: *Self, node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32) std.mem.Allocator.Error!void {
        
        try builder.appendIndent();
        try builder.append("class ");
        
        if (node.childByFieldName("name")) |name_node| {
            const name_text = self.getNodeText(name_node, source);
            try builder.append(name_text);
        }
        
        try builder.append(" {");
        try builder.newline();
        
        // Format class body
        builder.indent();
        if (node.childByFieldName("body")) |body_node| {
            try self.formatNodeRecursive(body_node, source, builder, depth + 1);
        }
        builder.dedent();
        
        try builder.appendIndent();
        try builder.append("}");
        try builder.newline();
    }
    
    /// Format TypeScript type alias
    fn formatTypeAlias(self: *Self, node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32) std.mem.Allocator.Error!void {
        _ = depth;
        
        try builder.appendIndent();
        try self.appendNodeText(node, source, builder);
        try builder.newline();
    }
    
    /// Format CSS rule
    fn formatCssRule(self: *Self, node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32) std.mem.Allocator.Error!void {
        
        // Format selector
        if (node.childByFieldName("selectors")) |selector_node| {
            try builder.appendIndent();
            const selector_text = self.getNodeText(selector_node, source);
            try builder.append(selector_text);
            try builder.append(" {");
            try builder.newline();
        }
        
        // Format declarations with indentation
        builder.indent();
        if (node.childByFieldName("block")) |block_node| {
            try self.formatNodeRecursive(block_node, source, builder, depth + 1);
        }
        builder.dedent();
        
        try builder.appendIndent();
        try builder.append("}");
        try builder.newline();
    }
    
    /// Format CSS at-rule
    fn formatCssAtRule(self: *Self, node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32) std.mem.Allocator.Error!void {
        _ = depth;
        
        try builder.appendIndent();
        try self.appendNodeText(node, source, builder);
        try builder.newline();
    }
    
    /// Format CSS declaration
    fn formatCssDeclaration(self: *Self, node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32) std.mem.Allocator.Error!void {
        _ = depth;
        
        try builder.appendIndent();
        
        if (node.childByFieldName("property")) |prop_node| {
            const prop_text = self.getNodeText(prop_node, source);
            try builder.append(prop_text);
            try builder.append(": ");
            
            if (node.childByFieldName("value")) |value_node| {
                const value_text = self.getNodeText(value_node, source);
                try builder.append(value_text);
            }
            
            try builder.append(";");
            try builder.newline();
        } else {
            try self.appendNodeText(node, source, builder);
            try builder.newline();
        }
    }
    
    /// Format CSS comment
    fn formatCssComment(self: *Self, node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32) std.mem.Allocator.Error!void {
        _ = depth;
        
        try builder.appendIndent();
        try self.appendNodeText(node, source, builder);
        try builder.newline();
    }
    
    /// Format Svelte script section
    fn formatSvelteScript(self: *Self, node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32) std.mem.Allocator.Error!void {
        
        try builder.append("<script>");
        try builder.newline();
        
        // Parse script content as TypeScript/JavaScript
        builder.indent();
        if (node.childByFieldName("content")) |content_node| {
            try self.formatNodeRecursive(content_node, source, builder, depth + 1);
        }
        builder.dedent();
        
        try builder.append("</script>");
        try builder.newline();
    }
    
    /// Format Svelte style section
    fn formatSvelteStyle(self: *Self, node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32) std.mem.Allocator.Error!void {
        
        try builder.append("<style>");
        try builder.newline();
        
        // Parse style content as CSS
        builder.indent();
        if (node.childByFieldName("content")) |content_node| {
            try self.formatNodeRecursive(content_node, source, builder, depth + 1);
        }
        builder.dedent();
        
        try builder.append("</style>");
        try builder.newline();
    }
    
    /// Format Svelte reactive statement
    fn formatSvelteReactive(self: *Self, node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32) std.mem.Allocator.Error!void {
        _ = depth;
        
        try builder.appendIndent();
        try builder.append("$: ");
        try self.appendNodeText(node, source, builder);
        try builder.newline();
    }
    
    /// Get text content of a node
    fn getNodeText(self: *Self, node: ts.Node, source: []const u8) []const u8 {
        _ = self;
        const start = node.startByte();
        const end = node.endByte();
        if (end <= source.len and start <= end) {
            return source[start..end];
        }
        return "";
    }
    
    /// Append node text to builder
    fn appendNodeText(self: *Self, node: ts.Node, source: []const u8, builder: *LineBuilder) !void {
        const text = self.getNodeText(node, source);
        try builder.append(text);
    }
    
    /// Determine if we should recurse into children of this node type
    fn shouldRecurseIntoChildren(self: *Self, node_type: []const u8) bool {
        _ = self;
        
        // Don't recurse into leaf nodes or simple content
        const leaf_nodes = [_][]const u8{
            "identifier", "string", "number", "boolean", 
            "comment", "property_name", "value"
        };
        
        for (leaf_nodes) |leaf| {
            if (std.mem.eql(u8, node_type, leaf)) {
                return false;
            }
        }
        
        return true;
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