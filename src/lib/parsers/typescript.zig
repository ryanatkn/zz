const std = @import("std");
const ExtractionFlags = @import("../parser.zig").ExtractionFlags;
const AstNode = @import("../ast.zig").AstNode;
const NodeVisitor = @import("../ast.zig").NodeVisitor;
const VisitResult = @import("../ast.zig").VisitResult;
const FunctionExtractor = @import("../ast.zig").FunctionExtractor;
const TypeExtractor = @import("../ast.zig").TypeExtractor;
const DependencyAnalyzer = @import("../ast.zig").DependencyAnalyzer;

pub fn extractSimple(source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) !void {
    var lines = std.mem.tokenizeScalar(u8, source, '\n');
    var in_type = false;
    var brace_count: u32 = 0;
    
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        var line_extracted = false;
        
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
        
        // Check types first (highest priority)
        if (flags.types and !line_extracted) {
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
                line_extracted = true;
            }
        }
        
        // Check signatures second (avoid overlap with types)
        if (flags.signatures and !line_extracted) {
            if (std.mem.startsWith(u8, trimmed, "function ") or
                std.mem.startsWith(u8, trimmed, "export function ") or
                std.mem.startsWith(u8, trimmed, "async function ") or
                std.mem.startsWith(u8, trimmed, "export async function ") or
                std.mem.startsWith(u8, trimmed, "const ") or
                std.mem.startsWith(u8, trimmed, "export const ") or
                std.mem.startsWith(u8, trimmed, "constructor(") or
                std.mem.startsWith(u8, trimmed, "async ") or  // class methods like "async getUser("
                std.mem.indexOf(u8, trimmed, " => ") != null or
                // Method signatures: look for pattern like "methodName(" or "async methodName("
                (std.mem.indexOf(u8, trimmed, "(") != null and 
                 std.mem.indexOf(u8, trimmed, ":") != null and 
                 std.mem.indexOf(u8, trimmed, "{") != null and
                 !std.mem.startsWith(u8, trimmed, "if") and
                 !std.mem.startsWith(u8, trimmed, "for") and
                 !std.mem.startsWith(u8, trimmed, "while"))) {
                // For signatures, always include the full line to preserve readability
                try result.appendSlice(line);
                try result.append('\n');
                line_extracted = true;
            }
        }
        
        // Check docs
        if (flags.docs and !line_extracted) {
            if (std.mem.startsWith(u8, trimmed, "/**") or
                std.mem.startsWith(u8, trimmed, "*") or
                std.mem.startsWith(u8, trimmed, "//")) {
                try result.appendSlice(line);
                try result.append('\n');
                line_extracted = true;
            }
        }
        
        // Check imports (usually mutually exclusive but check anyway)
        if (flags.imports and !line_extracted) {
            if (std.mem.startsWith(u8, trimmed, "import ") or
                std.mem.startsWith(u8, trimmed, "export ") or
                std.mem.startsWith(u8, trimmed, "require(")) {
                try result.appendSlice(line);
                try result.append('\n');
                line_extracted = true;
            }
        }
    }
}

/// AST-based extraction using tree-sitter (when available)
pub fn walkNode(allocator: std.mem.Allocator, root: *const AstNode, source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) !void {
    var extraction_context = ExtractionContext{
        .allocator = allocator,
        .result = result,
        .flags = flags,
        .source = source,
    };
    
    // Use AST-based extraction for more accurate results
    if (flags.signatures) {
        var func_extractor = FunctionExtractor.init(allocator);
        defer func_extractor.deinit();
        
        try func_extractor.extractFunctions(root, source, "typescript");
        const functions = func_extractor.getFunctions();
        
        for (functions) |func| {
            try result.appendSlice(func.signature);
            try result.append('\n');
        }
    }
    
    if (flags.types) {
        var type_extractor = TypeExtractor.init(allocator);
        defer type_extractor.deinit();
        
        try type_extractor.extractTypes(root, source, "typescript");
        const types = type_extractor.getTypes();
        
        for (types) |type_def| {
            try result.appendSlice(type_def.definition);
            try result.append('\n');
        }
    }
    
    if (flags.imports) {
        var dep_analyzer = DependencyAnalyzer.init(allocator);
        defer dep_analyzer.deinit();
        
        try dep_analyzer.analyzeDependencies(root, source, "typescript");
        const imports = dep_analyzer.getImports();
        
        for (imports) |import| {
            try result.writer().print("import {s} from '{s}';\n", .{import.imports, import.module_path});
        }
    }
    
    if (flags.docs) {
        // Extract documentation comments using visitor pattern
        var visitor = NodeVisitor.init(allocator, extractDocsVisitor, &extraction_context);
        try visitor.traverse(root, source);
    }
}

const ExtractionContext = struct {
    allocator: std.mem.Allocator,
    result: *std.ArrayList(u8),
    flags: ExtractionFlags,
    source: []const u8,
};

/// Visitor function for extracting documentation comments
fn extractDocsVisitor(visitor: *NodeVisitor, node: *const AstNode, context: ?*anyopaque) !VisitResult {
    _ = visitor;
    
    if (context) |ctx| {
        const extraction_ctx: *ExtractionContext = @ptrCast(@alignCast(ctx));
        
        // Look for comment nodes
        if (std.mem.eql(u8, node.node_type, "comment") or
            std.mem.startsWith(u8, node.text, "//") or
            std.mem.startsWith(u8, node.text, "/**")) {
            try extraction_ctx.result.appendSlice(node.text);
            try extraction_ctx.result.append('\n');
        }
    }
    
    return VisitResult.continue_traversal;
}

/// Get TypeScript-specific node types for function detection
pub fn isFunction(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "function_declaration") or
           std.mem.eql(u8, node_type, "method_definition") or
           std.mem.eql(u8, node_type, "arrow_function") or
           std.mem.eql(u8, node_type, "function_expression");
}

/// Get TypeScript-specific node types for type detection
pub fn isType(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "interface_declaration") or
           std.mem.eql(u8, node_type, "class_declaration") or
           std.mem.eql(u8, node_type, "type_alias_declaration") or
           std.mem.eql(u8, node_type, "enum_declaration");
}

/// Get TypeScript-specific node types for import detection
pub fn isImport(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "import_statement") or
           std.mem.eql(u8, node_type, "import_clause") or
           std.mem.eql(u8, node_type, "require_call");
}

/// Get TypeScript-specific node types for export detection
pub fn isExport(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "export_statement") or
           std.mem.eql(u8, node_type, "export_declaration");
}

test "typescript function detection" {
    const testing = std.testing;
    
    try testing.expect(isFunction("function_declaration"));
    try testing.expect(isFunction("method_definition"));
    try testing.expect(isFunction("arrow_function"));
    try testing.expect(!isFunction("class_declaration"));
}

test "typescript type detection" {
    const testing = std.testing;
    
    try testing.expect(isType("interface_declaration"));
    try testing.expect(isType("class_declaration"));
    try testing.expect(isType("type_alias_declaration"));
    try testing.expect(!isType("function_declaration"));
}

test "typescript import detection" {
    const testing = std.testing;
    
    try testing.expect(isImport("import_statement"));
    try testing.expect(isImport("require_call"));
    try testing.expect(!isImport("export_statement"));
}