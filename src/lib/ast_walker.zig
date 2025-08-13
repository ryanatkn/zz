const std = @import("std");
const AstNode = @import("ast.zig").AstNode;
const ExtractionFlags = @import("parser.zig").ExtractionFlags;
const collection_helpers = @import("collection_helpers.zig");

/// Unified AST walker to consolidate duplicate walkNode implementations across parsers
pub const AstWalker = struct {
    
    /// Context passed to all walker operations to reduce parameter passing
    pub const WalkContext = struct {
        allocator: std.mem.Allocator,
        source: []const u8,
        flags: ExtractionFlags,
        result: *collection_helpers.CollectionHelpers.ManagedArrayList(u8),
        depth: u32 = 0,
        language_specific_data: ?*anyopaque = null,
        
        pub fn init(
            allocator: std.mem.Allocator,
            source: []const u8,
            flags: ExtractionFlags,
            result: *collection_helpers.CollectionHelpers.ManagedArrayList(u8)
        ) WalkContext {
            return .{
                .allocator = allocator,
                .source = source,
                .flags = flags,
                .result = result,
            };
        }
        
        /// Append text to result with proper formatting
        pub fn appendText(self: *WalkContext, text: []const u8) !void {
            try self.result.appendSlice(text);
        }
        
        /// Append formatted text to result
        pub fn appendFmt(self: *WalkContext, comptime format: []const u8, args: anytype) !void {
            const formatted = try std.fmt.allocPrint(self.allocator, format, args);
            defer self.allocator.free(formatted);
            try self.result.appendSlice(formatted);
        }
        
        /// Check if we should extract nodes of this type based on flags
        pub fn shouldExtract(self: *const WalkContext, node_type: []const u8) bool {
            // Function definitions
            if (std.mem.eql(u8, node_type, "function_definition") or
                std.mem.eql(u8, node_type, "function_declaration") or
                std.mem.eql(u8, node_type, "method_definition") or
                std.mem.eql(u8, node_type, "function") or
                std.mem.eql(u8, node_type, "function_item") or // Rust
                std.mem.eql(u8, node_type, "function_signature")) {
                return self.flags.signatures;
            }
            
            // Type definitions
            if (std.mem.eql(u8, node_type, "struct") or
                std.mem.eql(u8, node_type, "class") or
                std.mem.eql(u8, node_type, "interface") or
                std.mem.eql(u8, node_type, "enum") or
                std.mem.eql(u8, node_type, "union") or
                std.mem.eql(u8, node_type, "type_definition") or
                std.mem.eql(u8, node_type, "struct_item") or // Rust
                std.mem.eql(u8, node_type, "enum_item")) { // Rust
                return self.flags.types;
            }
            
            // Documentation/comments
            if (std.mem.eql(u8, node_type, "doc_comment") or
                std.mem.eql(u8, node_type, "comment") or
                std.mem.eql(u8, node_type, "line_comment") or
                std.mem.eql(u8, node_type, "block_comment")) {
                return self.flags.docs;
            }
            
            // Import statements
            if (std.mem.eql(u8, node_type, "import") or
                std.mem.eql(u8, node_type, "import_statement") or
                std.mem.eql(u8, node_type, "use_statement") or
                std.mem.eql(u8, node_type, "include") or
                std.mem.eql(u8, node_type, "@import")) {
                return self.flags.imports;
            }
            
            // Test blocks
            if (std.mem.eql(u8, node_type, "test_decl") or
                std.mem.eql(u8, node_type, "test") or
                std.mem.eql(u8, node_type, "test_declaration") or
                std.mem.startsWith(u8, node_type, "test_")) {
                return self.flags.tests;
            }
            
            // Error handling patterns
            if (std.mem.eql(u8, node_type, "try") or
                std.mem.eql(u8, node_type, "catch") or
                std.mem.eql(u8, node_type, "error") or
                std.mem.eql(u8, node_type, "error_union") or
                std.mem.eql(u8, node_type, "switch") or
                std.mem.eql(u8, node_type, "if")) {
                return self.flags.errors;
            }
            
            // Structure patterns (HTML, XML, document structure)
            if (std.mem.eql(u8, node_type, "document") or
                std.mem.eql(u8, node_type, "element") or
                std.mem.eql(u8, node_type, "tag") or
                std.mem.eql(u8, node_type, "html") or
                std.mem.indexOf(u8, node_type, "_tag") != null) {
                return self.flags.structure;
            }
            
            return self.flags.full;
        }
    };

    /// Language-specific node visitor function type
    pub const NodeVisitorFn = *const fn(*WalkContext, *const AstNode) anyerror!void;
    
    /// Base walker with common traversal logic
    pub const BaseWalker = struct {
        allocator: std.mem.Allocator,
        visitor_fn: NodeVisitorFn,
        max_depth: u32,
        
        pub fn init(allocator: std.mem.Allocator, visitor_fn: NodeVisitorFn, max_depth: u32) BaseWalker {
            return .{
                .allocator = allocator,
                .visitor_fn = visitor_fn,
                .max_depth = max_depth,
            };
        }
        
        /// Main traversal entry point
        pub fn traverse(self: *BaseWalker, root: *const AstNode, context: *WalkContext) !void {
            try self.traverseNode(root, context);
        }
        
        /// Recursive node traversal
        fn traverseNode(self: *BaseWalker, node: *const AstNode, context: *WalkContext) !void {
            // Check depth limit
            if (self.max_depth > 0 and context.depth >= self.max_depth) {
                return;
            }
            
            // Visit current node with language-specific logic
            try self.visitor_fn(context, node);
            
            // Traverse children
            const children = try node.getChildren(self.allocator, context.source);
            defer self.allocator.free(children);
            
            context.depth += 1;
            defer context.depth -= 1;
            
            for (children) |*child| {
                try self.traverseNode(child, context);
            }
        }
    };

    /// Convenience function to replace the common walkNode pattern
    pub fn walkNodeWithVisitor(
        allocator: std.mem.Allocator,
        root: *const AstNode,
        source: []const u8,
        flags: ExtractionFlags,
        result: *std.ArrayList(u8),
        visitor_fn: NodeVisitorFn
    ) !void {
        // Convert ArrayList to ManagedArrayList for the new interface
        var managed_result = collection_helpers.CollectionHelpers.ManagedArrayList(u8).init(allocator);
        defer managed_result.deinit();
        
        // Copy existing content
        try managed_result.appendSlice(result.items);
        
        var context = WalkContext.init(allocator, source, flags, &managed_result);
        var walker = BaseWalker.init(allocator, visitor_fn, 100); // Default max depth
        try walker.traverse(root, &context);
        
        // Copy back to original ArrayList
        try result.appendSlice(managed_result.items());
    }

    /// Generic visitor that delegates to language-specific extractors
    pub const GenericVisitor = struct {
        /// Extract function signatures from AST node
        pub fn extractFunction(context: *WalkContext, node: *const AstNode) !void {
            if (!context.shouldExtract(node.node_type)) return;
            
            try context.appendFmt("// Function: {s}\n", .{node.node_type});
            try context.appendText(node.text);
            try context.appendText("\n\n");
        }
        
        /// Extract type definitions from AST node
        pub fn extractType(context: *WalkContext, node: *const AstNode) !void {
            if (!context.shouldExtract(node.node_type)) return;
            
            try context.appendFmt("// Type: {s}\n", .{node.node_type});
            try context.appendText(node.text);
            try context.appendText("\n\n");
        }
        
        /// Extract documentation comments from AST node
        pub fn extractDoc(context: *WalkContext, node: *const AstNode) !void {
            if (!context.shouldExtract(node.node_type)) return;
            
            try context.appendText(node.text);
            try context.appendText("\n");
        }
        
        /// Extract import statements from AST node
        pub fn extractImport(context: *WalkContext, node: *const AstNode) !void {
            if (!context.shouldExtract(node.node_type)) return;
            
            try context.appendText(node.text);
            try context.appendText("\n");
        }
        
        /// Generic node visitor for common patterns
        pub fn visitNode(context: *WalkContext, node: *const AstNode) !void {
            // Check node type and delegate to appropriate extractor
            if (std.mem.indexOf(u8, node.node_type, "function") != null) {
                try extractFunction(context, node);
            } else if (std.mem.indexOf(u8, node.node_type, "struct") != null or
                       std.mem.indexOf(u8, node.node_type, "class") != null or
                       std.mem.indexOf(u8, node.node_type, "interface") != null) {
                try extractType(context, node);
            } else if (std.mem.indexOf(u8, node.node_type, "comment") != null or
                       std.mem.indexOf(u8, node.node_type, "doc") != null) {
                try extractDoc(context, node);
            } else if (std.mem.indexOf(u8, node.node_type, "import") != null or
                       std.mem.indexOf(u8, node.node_type, "use") != null) {
                try extractImport(context, node);
            }
        }
    };
    
    /// Replacement for the common walkNode signature used across parsers
    pub fn walkNode(
        allocator: std.mem.Allocator,
        root: *const AstNode,
        source: []const u8,
        flags: ExtractionFlags,
        result: *std.ArrayList(u8)
    ) !void {
        try walkNodeWithVisitor(allocator, root, source, flags, result, GenericVisitor.visitNode);
    }
};

/// Language-specific visitor implementations can use this pattern
pub const LanguageVisitor = struct {
    pub fn createZigVisitor(context: *AstWalker.WalkContext, node: *const AstNode) !void {
        // Zig-specific extraction logic
        if (std.mem.eql(u8, node.node_type, "FnDecl")) {
            if (context.shouldExtract("function")) {
                try context.appendText("pub fn ");
                try context.appendText(node.text);
                try context.appendText("\n");
            }
        }
    }
    
    pub fn createTypescriptVisitor(context: *AstWalker.WalkContext, node: *const AstNode) !void {
        // TypeScript-specific extraction logic
        if (std.mem.eql(u8, node.node_type, "function_declaration")) {
            if (context.shouldExtract("function")) {
                try context.appendText("function ");
                try context.appendText(node.text);
                try context.appendText("\n");
            }
        }
    }
    
    pub fn createCssVisitor(context: *AstWalker.WalkContext, node: *const AstNode) !void {
        // CSS-specific extraction logic
        if (std.mem.eql(u8, node.node_type, "rule_set")) {
            try context.appendText(node.text);
            try context.appendText("\n");
        }
    }
};

test "AstWalker WalkContext basic functionality" {
    const testing = std.testing;
    
    var managed_result = collection_helpers.CollectionHelpers.ManagedArrayList(u8).init(testing.allocator);
    defer managed_result.deinit();
    
    var context = AstWalker.WalkContext.init(
        testing.allocator,
        "test source", 
        ExtractionFlags{},
        &managed_result
    );
    
    try context.appendText("Hello ");
    try context.appendText("World");
    
    try testing.expectEqualStrings("Hello World", managed_result.items());
}

test "AstWalker shouldExtract functionality" {
    const testing = std.testing;
    
    var managed_result = collection_helpers.CollectionHelpers.ManagedArrayList(u8).init(testing.allocator);
    defer managed_result.deinit();
    
    var context = AstWalker.WalkContext.init(
        testing.allocator,
        "test source",
        ExtractionFlags{ .signatures = true, .types = false },
        &managed_result
    );
    
    try testing.expect(context.shouldExtract("function_definition"));
    try testing.expect(!context.shouldExtract("struct"));
    try testing.expect(!context.shouldExtract("unknown_type"));
}

test "GenericVisitor node classification" {
    const testing = std.testing;
    
    var managed_result = collection_helpers.CollectionHelpers.ManagedArrayList(u8).init(testing.allocator);
    defer managed_result.deinit();
    
    var context = AstWalker.WalkContext.init(
        testing.allocator,
        "pub fn test() {}",
        ExtractionFlags{ .signatures = true },
        &managed_result
    );
    
    const node = AstNode.init("function_definition", 0, 15, "pub fn test() {}");
    try AstWalker.GenericVisitor.visitNode(&context, &node);
    
    const result = managed_result.items();
    try testing.expect(std.mem.indexOf(u8, result, "Function:") != null);
    try testing.expect(std.mem.indexOf(u8, result, "pub fn test() {") != null);
}