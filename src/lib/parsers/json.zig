const std = @import("std");
const ExtractionFlags = @import("../extraction_flags.zig").ExtractionFlags;
const AstNode = @import("../ast.zig").AstNode;
const NodeVisitor = @import("../ast.zig").NodeVisitor;
const VisitResult = @import("../ast.zig").VisitResult;
const json_extractor = @import("../extractors/json.zig");

pub fn extractSimple(source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) !void {
    // Delegate to the extractor for simple extraction
    try json_extractor.extract(source, flags, result);
}

/// AST-based extraction using tree-sitter (when available)
pub fn walkNode(allocator: std.mem.Allocator, root: *const AstNode, source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) !void {
    var extraction_context = ExtractionContext{
        .allocator = allocator,
        .result = result,
        .flags = flags,
        .source = source,
    };
    
    // JSON-specific extraction using visitor pattern
    var visitor = NodeVisitor.init(allocator, jsonExtractionVisitor, &extraction_context);
    try visitor.traverse(root, source);
}

const ExtractionContext = struct {
    allocator: std.mem.Allocator,
    result: *std.ArrayList(u8),
    flags: ExtractionFlags,
    source: []const u8,
};

/// Visitor function for JSON extraction
fn jsonExtractionVisitor(visitor: *NodeVisitor, node: *const AstNode, context: ?*anyopaque) !VisitResult {
    _ = visitor;
    
    if (context) |ctx| {
        const extraction_ctx: *ExtractionContext = @ptrCast(@alignCast(ctx));
        
        // Extract based on node type and flags
        if (extraction_ctx.flags.structure or extraction_ctx.flags.types) {
            // Extract JSON structure (objects, arrays, pairs)
            if (isStructuralNode(node.node_type)) {
                try extraction_ctx.result.appendSlice(node.text);
                try extraction_ctx.result.append('\n');
                // Continue traversal to get nested structure
            }
        }
        
        if (extraction_ctx.flags.signatures) {
            // Extract object keys only
            if (isKey(node.node_type)) {
                try extraction_ctx.result.appendSlice(node.text);
                try extraction_ctx.result.append('\n');
            }
        }
        
        if (extraction_ctx.flags.types) {
            // Extract type information (arrays, objects, primitives)
            if (isTypedValue(node.node_type)) {
                try extraction_ctx.result.appendSlice(node.text);
                try extraction_ctx.result.append('\n');
            }
        }
    }
    
    return VisitResult.continue_traversal;
}

/// Check if node represents JSON structural elements
pub fn isStructuralNode(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "object") or
           std.mem.eql(u8, node_type, "array") or
           std.mem.eql(u8, node_type, "pair") or
           std.mem.eql(u8, node_type, "document");
}

/// Check if node represents a JSON key
pub fn isKey(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "string") and 
           // Additional context checking could be added here
           true; // For now, all strings could be keys
}

/// Check if node represents a typed value
pub fn isTypedValue(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "string") or
           std.mem.eql(u8, node_type, "number") or
           std.mem.eql(u8, node_type, "true") or
           std.mem.eql(u8, node_type, "false") or
           std.mem.eql(u8, node_type, "null") or
           std.mem.eql(u8, node_type, "object") or
           std.mem.eql(u8, node_type, "array");
}

/// Check if node represents a JSON value
pub fn isValue(node_type: []const u8) bool {
    return isTypedValue(node_type);
}

/// Extract JSON schema structure
pub fn extractSchema(allocator: std.mem.Allocator, root: *const AstNode, source: []const u8, result: *std.ArrayList(u8)) !void {
    var context = SchemaContext{
        .allocator = allocator,
        .result = result,
        .source = source,
    };
    
    var visitor = NodeVisitor.init(allocator, extractSchemaVisitor, &context);
    try visitor.traverse(root, source);
}

const SchemaContext = struct {
    allocator: std.mem.Allocator,
    result: *std.ArrayList(u8),
    source: []const u8,
};

/// Visitor function for extracting JSON schema information
fn extractSchemaVisitor(visitor: *NodeVisitor, node: *const AstNode, context: ?*anyopaque) !VisitResult {
    _ = visitor;
    
    if (context) |ctx| {
        const schema_ctx: *SchemaContext = @ptrCast(@alignCast(ctx));
        
        // Extract key-type pairs to understand structure
        if (std.mem.eql(u8, node.node_type, "pair")) {
            try schema_ctx.result.appendSlice(node.text);
            try schema_ctx.result.append('\n');
            return VisitResult.skip_children; // We have the full pair
        }
    }
    
    return VisitResult.continue_traversal;
}

/// Extract JSON paths (dot notation)
pub fn extractPaths(allocator: std.mem.Allocator, root: *const AstNode, source: []const u8, result: *std.ArrayList(u8)) !void {
    var context = PathContext{
        .allocator = allocator,
        .result = result,
        .source = source,
        .current_path = std.ArrayList(u8).init(allocator),
    };
    defer context.current_path.deinit();
    
    var visitor = NodeVisitor.init(allocator, extractPathsVisitor, &context);
    try visitor.traverse(root, source);
}

const PathContext = struct {
    allocator: std.mem.Allocator,
    result: *std.ArrayList(u8),
    source: []const u8,
    current_path: std.ArrayList(u8),
};

/// Visitor function for extracting JSON paths
fn extractPathsVisitor(visitor: *NodeVisitor, node: *const AstNode, context: ?*anyopaque) !VisitResult {
    _ = visitor;
    
    if (context) |ctx| {
        const path_ctx: *PathContext = @ptrCast(@alignCast(ctx));
        
        // Build paths for object keys
        if (std.mem.eql(u8, node.node_type, "pair")) {
            // Get the key from the pair and add to current path
            const old_len = path_ctx.current_path.items.len;
            
            // Add current level to path (simplified - real implementation would parse key)
            if (path_ctx.current_path.items.len > 0) {
                try path_ctx.current_path.append('.');
            }
            try path_ctx.current_path.appendSlice("key"); // Placeholder - would extract actual key
            
            // Output current path
            try path_ctx.result.appendSlice(path_ctx.current_path.items);
            try path_ctx.result.append('\n');
            
            // Restore path after processing
            path_ctx.current_path.shrinkRetainingCapacity(old_len);
        }
    }
    
    return VisitResult.continue_traversal;
}

test "json structural node detection" {
    const testing = std.testing;
    
    try testing.expect(isStructuralNode("object"));
    try testing.expect(isStructuralNode("array"));
    try testing.expect(isStructuralNode("pair"));
    try testing.expect(!isStructuralNode("string"));
}

test "json key detection" {
    const testing = std.testing;
    
    try testing.expect(isKey("string"));
    try testing.expect(!isKey("number"));
}

test "json typed value detection" {
    const testing = std.testing;
    
    try testing.expect(isTypedValue("string"));
    try testing.expect(isTypedValue("number"));
    try testing.expect(isTypedValue("true"));
    try testing.expect(isTypedValue("false"));
    try testing.expect(isTypedValue("null"));
    try testing.expect(isTypedValue("object"));
    try testing.expect(isTypedValue("array"));
    try testing.expect(!isTypedValue("pair"));
}

test "json value detection" {
    const testing = std.testing;
    
    try testing.expect(isValue("string"));
    try testing.expect(isValue("object"));
    try testing.expect(!isValue("pair"));
}