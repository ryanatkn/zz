const std = @import("std");
const ts = @import("tree-sitter");

/// AST node type for unified handling across languages
/// Wraps real tree-sitter nodes with convenience methods
pub const AstNode = struct {
    /// The actual tree-sitter node
    ts_node: ts.Node,
    /// Cached source text for this node
    text: []const u8,
    /// Full source for extracting child node text
    source: []const u8,
    
    pub const Point = struct {
        row: u32,
        column: u32,
        
        pub fn fromTsPoint(ts_point: ts.Point) Point {
            return Point{
                .row = ts_point.row,
                .column = ts_point.column,
            };
        }
    };
    
    /// Create AstNode from tree-sitter node and source
    pub fn fromTsNode(ts_node: ts.Node, source: []const u8) AstNode {
        const start_byte = ts_node.startByte();
        const end_byte = ts_node.endByte();
        const text = if (end_byte <= source.len) source[start_byte..end_byte] else "";
        
        return AstNode{
            .ts_node = ts_node,
            .text = text,
            .source = source,
        };
    }
    
    /// Get the node type as a string
    pub fn nodeType(self: *const AstNode) []const u8 {
        return self.ts_node.kind();
    }
    
    /// Get start byte offset
    pub fn startByte(self: *const AstNode) u32 {
        return self.ts_node.startByte();
    }
    
    /// Get end byte offset
    pub fn endByte(self: *const AstNode) u32 {
        return self.ts_node.endByte();
    }
    
    /// Get start point
    pub fn startPoint(self: *const AstNode) Point {
        return Point.fromTsPoint(self.ts_node.startPoint());
    }
    
    /// Get end point
    pub fn endPoint(self: *const AstNode) Point {
        return Point.fromTsPoint(self.ts_node.endPoint());
    }
    
    /// Check if node is named (corresponds to named rules in grammar)
    pub fn isNamed(self: *const AstNode) bool {
        return self.ts_node.isNamed();
    }
    
    /// Check if node has error
    pub fn hasError(self: *const AstNode) bool {
        return self.ts_node.hasError();
    }
    
    /// Get number of children
    pub fn childCount(self: *const AstNode) u32 {
        return self.ts_node.childCount();
    }
    
    /// Get child at index
    pub fn child(self: *const AstNode, index: u32) ?AstNode {
        if (self.ts_node.child(index)) |child_node| {
            return AstNode.fromTsNode(child_node, self.source);
        }
        return null;
    }
    
    /// Check if has child of specific type
    pub fn hasChild(self: *const AstNode, child_type: []const u8) bool {
        const count = self.childCount();
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            if (self.child(i)) |child_node| {
                if (std.mem.eql(u8, child_node.nodeType(), child_type)) {
                    return true;
                }
            }
        }
        return false;
    }
    
    /// Get all children as an allocated array
    pub fn getChildren(self: *const AstNode, allocator: std.mem.Allocator, source: []const u8) ![]AstNode {
        _ = source; // Use the source stored in the node instead
        
        const count = self.childCount();
        const children = try allocator.alloc(AstNode, count);
        
        for (children, 0..) |*child_ast, i| {
            if (self.child(@intCast(i))) |child_node| {
                child_ast.* = child_node;
            }
        }
        
        return children;
    }
    
    /// Get child by field name (useful for structured nodes)
    pub fn childByFieldName(self: *const AstNode, field_name: []const u8) ?AstNode {
        if (self.ts_node.childByFieldName(field_name)) |child_node| {
            return AstNode.fromTsNode(child_node, self.source);
        }
        return null;
    }
    
    /// Create a mock AST node for testing/transitional purposes
    /// This should be removed once full tree-sitter integration is complete
    pub fn createMock(source: []const u8) AstNode {
        // Create a zero-initialized tree-sitter node
        // This is a temporary hack for backward compatibility
        const mock_ts_node = std.mem.zeroes(ts.Node);
        
        return AstNode{
            .ts_node = mock_ts_node,
            .text = source,
            .source = source,
        };
    }
};

/// Visitor result to control traversal
pub const VisitResult = enum {
    continue_traversal,  // Continue visiting children
    skip_children,       // Skip children of current node
    stop_traversal,      // Stop entire traversal
};

/// Generic node visitor interface for AST traversal
pub const NodeVisitor = struct {
    allocator: std.mem.Allocator,
    visit_fn: *const fn(visitor: *NodeVisitor, node: *const AstNode, context: ?*anyopaque) anyerror!VisitResult,
    context: ?*anyopaque,
    
    pub fn init(
        allocator: std.mem.Allocator,
        visit_fn: *const fn(visitor: *NodeVisitor, node: *const AstNode, context: ?*anyopaque) anyerror!VisitResult,
        context: ?*anyopaque
    ) NodeVisitor {
        return NodeVisitor{
            .allocator = allocator,
            .visit_fn = visit_fn,
            .context = context,
        };
    }
    
    /// Traverse AST starting from root node
    pub fn traverse(self: *NodeVisitor, root: *const AstNode, source: []const u8) !void {
        try self.traverseRecursive(root, source);
    }
    
    fn traverseRecursive(self: *NodeVisitor, node: *const AstNode, source: []const u8) !void {
        const result = try self.visit_fn(self, node, self.context);
        
        switch (result) {
            .continue_traversal => {
                // Visit children
                const children = try node.getChildren(self.allocator, source);
                defer self.allocator.free(children);
                
                for (children) |*child| {
                    try self.traverseRecursive(child, source);
                }
            },
            .skip_children => {
                // Don't visit children but continue traversal
                return;
            },
            .stop_traversal => {
                // Stop entire traversal
                return;
            },
        }
    }
};

/// Extract function signatures from AST
pub const FunctionExtractor = struct {
    allocator: std.mem.Allocator,
    functions: std.ArrayList(ExtractedFunction),
    
    pub const ExtractedFunction = struct {
        name: []const u8,
        signature: []const u8,
        start_line: u32,
        end_line: u32,
        is_public: bool,
        documentation: ?[]const u8,
        
        pub fn deinit(self: *ExtractedFunction, allocator: std.mem.Allocator) void {
            allocator.free(self.name);
            allocator.free(self.signature);
            if (self.documentation) |doc| {
                allocator.free(doc);
            }
        }
    };
    
    pub fn init(allocator: std.mem.Allocator) FunctionExtractor {
        return FunctionExtractor{
            .allocator = allocator,
            .functions = std.ArrayList(ExtractedFunction).init(allocator),
        };
    }
    
    pub fn deinit(self: *FunctionExtractor) void {
        for (self.functions.items) |*func| {
            func.deinit(self.allocator);
        }
        self.functions.deinit();
    }
    
    /// Extract functions from AST based on language
    pub fn extractFunctions(self: *FunctionExtractor, root: *const AstNode, source: []const u8, language: []const u8) !void {
        var visitor = NodeVisitor.init(
            self.allocator,
            extractFunctionVisitor,
            @ptrCast(self)
        );
        
        // Store language in context for language-specific extraction
        var context = ExtractionContext{
            .language = language,
            .extractor = self,
            .source = source,
        };
        visitor.context = @ptrCast(&context);
        
        try visitor.traverse(root, source);
    }
    
    pub fn getFunctions(self: *FunctionExtractor) []ExtractedFunction {
        return self.functions.items;
    }
    
    const ExtractionContext = struct {
        language: []const u8,
        extractor: *FunctionExtractor,
        source: []const u8,
    };
    
    fn extractFunctionVisitor(visitor: *NodeVisitor, node: *const AstNode, ctx: ?*anyopaque) !VisitResult {
        _ = visitor;
        
        if (ctx == null) return VisitResult.continue_traversal;
        const context: *ExtractionContext = @ptrCast(@alignCast(ctx.?));
        
        // Language-specific function detection
        const is_function = if (std.mem.eql(u8, context.language, "zig"))
            isFunctionNode(node, "zig")
        else if (std.mem.eql(u8, context.language, "typescript"))
            isFunctionNode(node, "typescript")
        else if (std.mem.eql(u8, context.language, "css"))
            false // CSS doesn't have functions in traditional sense
        else
            false;
            
        if (is_function) {
            const func = try extractFunctionInfo(
                context.extractor.allocator, 
                node, 
                context.source, 
                context.language
            );
            try context.extractor.functions.append(func);
            return VisitResult.skip_children; // Don't traverse into function body
        }
        
        return VisitResult.continue_traversal;
    }
};

/// Check if node represents a function in the given language
fn isFunctionNode(node: *const AstNode, language: []const u8) bool {
    if (std.mem.eql(u8, language, "zig")) {
        return std.mem.eql(u8, node.nodeType(), "FunctionDeclaration") or
               std.mem.eql(u8, node.nodeType(), "TestDeclaration");
    } else if (std.mem.eql(u8, language, "typescript")) {
        return std.mem.eql(u8, node.nodeType(), "function_declaration") or
               std.mem.eql(u8, node.nodeType(), "method_definition") or
               std.mem.eql(u8, node.nodeType(), "arrow_function");
    }
    return false;
}

/// Extract function information from AST node
fn extractFunctionInfo(allocator: std.mem.Allocator, node: *const AstNode, source: []const u8, language: []const u8) !FunctionExtractor.ExtractedFunction {
    _ = source;
    _ = language;
    
    // Simplified extraction for tree-sitter integration compatibility
    // Future: Add language-specific AST analysis for precise extraction
    
    const name = try allocator.dupe(u8, "extracted_function");
    const signature = try allocator.dupe(u8, node.text);
    
    return FunctionExtractor.ExtractedFunction{
        .name = name,
        .signature = signature,
        .start_line = node.start_point.row,
        .end_line = node.end_point.row,
        .is_public = true, // Future: Parse visibility modifiers via AST
        .documentation = null, // Future: Extract documentation comments
    };
}

/// Type extractor for interfaces, structs, classes, enums
pub const TypeExtractor = struct {
    allocator: std.mem.Allocator,
    types: std.ArrayList(ExtractedType),
    
    pub const ExtractedType = struct {
        name: []const u8,
        kind: TypeKind,
        definition: []const u8,
        start_line: u32,
        end_line: u32,
        is_public: bool,
        documentation: ?[]const u8,
        
        pub const TypeKind = enum {
            struct_type,
            enum_type,
            union_type,
            interface_type,
            class_type,
            type_alias,
        };
        
        pub fn deinit(self: *ExtractedType, allocator: std.mem.Allocator) void {
            allocator.free(self.name);
            allocator.free(self.definition);
            if (self.documentation) |doc| {
                allocator.free(doc);
            }
        }
    };
    
    pub fn init(allocator: std.mem.Allocator) TypeExtractor {
        return TypeExtractor{
            .allocator = allocator,
            .types = std.ArrayList(ExtractedType).init(allocator),
        };
    }
    
    pub fn deinit(self: *TypeExtractor) void {
        for (self.types.items) |*type_def| {
            type_def.deinit(self.allocator);
        }
        self.types.deinit();
    }
    
    pub fn extractTypes(self: *TypeExtractor, root: *const AstNode, source: []const u8, language: []const u8) !void {
        var visitor = NodeVisitor.init(
            self.allocator,
            extractTypeVisitor,
            @ptrCast(self)
        );
        
        var context = TypeExtractionContext{
            .language = language,
            .extractor = self,
            .source = source,
        };
        visitor.context = @ptrCast(&context);
        
        try visitor.traverse(root, source);
    }
    
    pub fn getTypes(self: *TypeExtractor) []ExtractedType {
        return self.types.items;
    }
    
    const TypeExtractionContext = struct {
        language: []const u8,
        extractor: *TypeExtractor,
        source: []const u8,
    };
    
    fn extractTypeVisitor(visitor: *NodeVisitor, node: *const AstNode, ctx: ?*anyopaque) !VisitResult {
        _ = visitor;
        
        if (ctx == null) return VisitResult.continue_traversal;
        const context: *TypeExtractionContext = @ptrCast(@alignCast(ctx.?));
        
        const type_info = getTypeInfo(node, context.language);
        if (type_info) |info| {
            const extracted_type = try extractTypeInfo(
                context.extractor.allocator,
                node,
                context.source,
                info.kind,
                context.language
            );
            try context.extractor.types.append(extracted_type);
            return VisitResult.skip_children;
        }
        
        return VisitResult.continue_traversal;
    }
};

/// Get type information if node represents a type
fn getTypeInfo(node: *const AstNode, language: []const u8) ?struct { kind: TypeExtractor.ExtractedType.TypeKind } {
    if (std.mem.eql(u8, language, "zig")) {
        if (std.mem.eql(u8, node.nodeType(), "StructDeclaration")) {
            return .{ .kind = .struct_type };
        } else if (std.mem.eql(u8, node.nodeType(), "EnumDeclaration")) {
            return .{ .kind = .enum_type };
        } else if (std.mem.eql(u8, node.nodeType(), "UnionDeclaration")) {
            return .{ .kind = .union_type };
        }
    } else if (std.mem.eql(u8, language, "typescript")) {
        if (std.mem.eql(u8, node.nodeType(), "interface_declaration")) {
            return .{ .kind = .interface_type };
        } else if (std.mem.eql(u8, node.nodeType(), "class_declaration")) {
            return .{ .kind = .class_type };
        } else if (std.mem.eql(u8, node.nodeType(), "type_alias_declaration")) {
            return .{ .kind = .type_alias };
        } else if (std.mem.eql(u8, node.nodeType(), "enum_declaration")) {
            return .{ .kind = .enum_type };
        }
    }
    return null;
}

/// Extract type definition from AST node
fn extractTypeInfo(allocator: std.mem.Allocator, node: *const AstNode, source: []const u8, kind: TypeExtractor.ExtractedType.TypeKind, language: []const u8) !TypeExtractor.ExtractedType {
    _ = source;
    _ = language;
    
    // For now, use simplified extraction
    // TODO: Add proper AST-based extraction for each language
    
    const name = try allocator.dupe(u8, "extracted_type");
    const definition = try allocator.dupe(u8, node.text);
    
    return TypeExtractor.ExtractedType{
        .name = name,
        .kind = kind,
        .definition = definition,
        .start_line = node.start_point.row,
        .end_line = node.end_point.row,
        .is_public = true, // Future: Parse visibility modifiers via AST
        .documentation = null, // Future: Extract documentation comments
    };
}

/// Dependency analyzer for import/export tracking
pub const DependencyAnalyzer = struct {
    allocator: std.mem.Allocator,
    imports: std.ArrayList(ImportStatement),
    exports: std.ArrayList(ExportStatement),
    
    pub const ImportStatement = struct {
        module_path: []const u8,
        imports: [][]const u8, // What is imported (empty for * imports)
        is_default: bool,
        start_line: u32,
        
        pub fn deinit(self: *ImportStatement, allocator: std.mem.Allocator) void {
            allocator.free(self.module_path);
            for (self.imports) |import| {
                allocator.free(import);
            }
            allocator.free(self.imports);
        }
    };
    
    pub const ExportStatement = struct {
        name: []const u8,
        is_default: bool,
        start_line: u32,
        
        pub fn deinit(self: *ExportStatement, allocator: std.mem.Allocator) void {
            allocator.free(self.name);
        }
    };
    
    pub fn init(allocator: std.mem.Allocator) DependencyAnalyzer {
        return DependencyAnalyzer{
            .allocator = allocator,
            .imports = std.ArrayList(ImportStatement).init(allocator),
            .exports = std.ArrayList(ExportStatement).init(allocator),
        };
    }
    
    pub fn deinit(self: *DependencyAnalyzer) void {
        for (self.imports.items) |*import| {
            import.deinit(self.allocator);
        }
        self.imports.deinit();
        
        for (self.exports.items) |*export_stmt| {
            export_stmt.deinit(self.allocator);
        }
        self.exports.deinit();
    }
    
    pub fn analyzeDependencies(self: *DependencyAnalyzer, root: *const AstNode, source: []const u8, language: []const u8) !void {
        var visitor = NodeVisitor.init(
            self.allocator,
            analyzeDependencyVisitor,
            @ptrCast(self)
        );
        
        var context = DependencyAnalysisContext{
            .language = language,
            .analyzer = self,
            .source = source,
        };
        visitor.context = @ptrCast(&context);
        
        try visitor.traverse(root, source);
    }
    
    pub fn getImports(self: *DependencyAnalyzer) []ImportStatement {
        return self.imports.items;
    }
    
    pub fn getExports(self: *DependencyAnalyzer) []ExportStatement {
        return self.exports.items;
    }
    
    const DependencyAnalysisContext = struct {
        language: []const u8,
        analyzer: *DependencyAnalyzer,
        source: []const u8,
    };
    
    fn analyzeDependencyVisitor(visitor: *NodeVisitor, node: *const AstNode, ctx: ?*anyopaque) !VisitResult {
        _ = visitor;
        
        if (ctx == null) return VisitResult.continue_traversal;
        const context: *DependencyAnalysisContext = @ptrCast(@alignCast(ctx.?));
        
        // Detect imports and exports based on language
        if (isImportNode(node, context.language)) {
            const import_stmt = try extractImportInfo(
                context.analyzer.allocator,
                node,
                context.source,
                context.language
            );
            try context.analyzer.imports.append(import_stmt);
        } else if (isExportNode(node, context.language)) {
            const export_stmt = try extractExportInfo(
                context.analyzer.allocator,
                node,
                context.source,
                context.language
            );
            try context.analyzer.exports.append(export_stmt);
        }
        
        return VisitResult.continue_traversal;
    }
};

/// Check if node represents an import statement
fn isImportNode(node: *const AstNode, language: []const u8) bool {
    if (std.mem.eql(u8, language, "zig")) {
        return std.mem.startsWith(u8, node.text, "@import");
    } else if (std.mem.eql(u8, language, "typescript")) {
        return std.mem.eql(u8, node.nodeType(), "import_statement");
    }
    return false;
}

/// Check if node represents an export statement
fn isExportNode(node: *const AstNode, language: []const u8) bool {
    if (std.mem.eql(u8, language, "zig")) {
        return std.mem.startsWith(u8, node.text, "pub ");
    } else if (std.mem.eql(u8, language, "typescript")) {
        return std.mem.eql(u8, node.nodeType(), "export_statement");
    }
    return false;
}

/// Extract import information from AST node
fn extractImportInfo(allocator: std.mem.Allocator, node: *const AstNode, source: []const u8, language: []const u8) !DependencyAnalyzer.ImportStatement {
    _ = source;
    _ = language;
    
    // Simplified extraction - Future: Add proper AST parsing
    const module_path = try allocator.dupe(u8, "unknown_module");
    const imports = try allocator.alloc([]const u8, 0);
    
    return DependencyAnalyzer.ImportStatement{
        .module_path = module_path,
        .imports = imports,
        .is_default = false,
        .start_line = node.start_point.row,
    };
}

/// Extract export information from AST node
fn extractExportInfo(allocator: std.mem.Allocator, node: *const AstNode, source: []const u8, language: []const u8) !DependencyAnalyzer.ExportStatement {
    _ = source;
    _ = language;
    
    // Simplified extraction - Future: Add proper AST parsing
    const name = try allocator.dupe(u8, "unknown_export");
    
    return DependencyAnalyzer.ExportStatement{
        .name = name,
        .is_default = false,
        .start_line = node.start_point.row,
    };
}

// Tests
test "node visitor initialization" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var visited_count: u32 = 0;
    
    const TestVisitorFn = struct {
        fn visit(visitor: *NodeVisitor, node: *const AstNode, context: ?*anyopaque) !VisitResult {
            _ = visitor;
            _ = node;
            const count_ptr: *u32 = @ptrCast(@alignCast(context.?));
            count_ptr.* += 1;
            return VisitResult.continue_traversal;
        }
    }.visit;
    
    const visitor = NodeVisitor.init(allocator, TestVisitorFn, &visited_count);
    
    // Just test initialization - traversal requires real tree-sitter nodes
    try testing.expect(visitor.allocator.ptr == allocator.ptr);
    try testing.expect(visited_count == 0);
}

test "function extractor initialization" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var extractor = FunctionExtractor.init(allocator);
    defer extractor.deinit();

    const functions = extractor.getFunctions();
    try testing.expect(functions.len == 0);
}

test "type extractor initialization" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var extractor = TypeExtractor.init(allocator);
    defer extractor.deinit();

    const types = extractor.getTypes();
    try testing.expect(types.len == 0);
}

test "dependency analyzer initialization" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var analyzer = DependencyAnalyzer.init(allocator);
    defer analyzer.deinit();

    const imports = analyzer.getImports();
    const exports = analyzer.getExports();
    try testing.expect(imports.len == 0);
    try testing.expect(exports.len == 0);
}