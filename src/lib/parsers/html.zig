const std = @import("std");
const ExtractionFlags = @import("../language/flags.zig").ExtractionFlags;
const AstNode = @import("../ast.zig").AstNode;
const NodeVisitor = @import("../ast.zig").NodeVisitor;
const VisitResult = @import("../ast.zig").VisitResult;
const AstWalker = @import("../ast.zig").AstWalker;
const html_extractor = @import("../extractors/html.zig");

pub fn extractSimple(source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) !void {
    // Delegate to the extractor for simple extraction
    try html_extractor.extract(source, flags, result);
}

/// AST-based extraction using shared AST walker
pub fn walkNode(allocator: std.mem.Allocator, root: *const AstNode, source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) !void {
    try AstWalker.walkNodeWithVisitor(allocator, root, source, flags, result, htmlExtractionVisitorNew);
}

/// HTML-specific visitor function adapted for the shared AST walker
fn htmlExtractionVisitorNew(context: *AstWalker.WalkContext, node: *const AstNode) !void {
    // HTML-specific extraction logic using generic visitor
    try AstWalker.GenericVisitor.visitNode(context, node);
}

const ExtractionContext = struct {
    allocator: std.mem.Allocator,
    result: *std.ArrayList(u8),
    flags: ExtractionFlags,
    source: []const u8,
};

/// Visitor function for HTML extraction
fn htmlExtractionVisitor(visitor: *NodeVisitor, node: *const AstNode, context: ?*anyopaque) !VisitResult {
    _ = visitor;

    if (context) |ctx| {
        const extraction_ctx: *ExtractionContext = @ptrCast(@alignCast(ctx));

        // Extract based on node type and flags
        if (extraction_ctx.flags.structure or extraction_ctx.flags.types) {
            // Extract HTML elements and structure
            if (isElement(node.node_type) or isStructuralNode(node.node_type)) {
                try extraction_ctx.result.appendSlice(node.text);
                try extraction_ctx.result.append('\n');
                return VisitResult.skip_children; // Don't traverse into element details for structure
            }
        }

        if (extraction_ctx.flags.signatures) {
            // Extract script elements and event handlers
            if (isScriptElement(node.node_type) or hasEventHandler(node.node_type, node.text)) {
                try extraction_ctx.result.appendSlice(node.text);
                try extraction_ctx.result.append('\n');
                return VisitResult.skip_children;
            }
        }

        if (extraction_ctx.flags.docs) {
            // Extract HTML comments
            if (isComment(node.node_type)) {
                try extraction_ctx.result.appendSlice(node.text);
                try extraction_ctx.result.append('\n');
            }
        }

        if (extraction_ctx.flags.imports) {
            // Extract link and script imports
            if (isLinkElement(node.node_type) or isScriptImport(node.node_type, node.text)) {
                try extraction_ctx.result.appendSlice(node.text);
                try extraction_ctx.result.append('\n');
            }
        }
    }

    return VisitResult.continue_traversal;
}

/// Check if node represents an HTML element
pub fn isElement(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "element") or
        std.mem.eql(u8, node_type, "start_tag") or
        std.mem.eql(u8, node_type, "end_tag") or
        std.mem.eql(u8, node_type, "self_closing_tag");
}

/// Check if node represents structural HTML
pub fn isStructuralNode(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "doctype") or
        std.mem.eql(u8, node_type, "document") or
        std.mem.eql(u8, node_type, "fragment");
}

/// Check if node represents a script element
pub fn isScriptElement(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "script_element") or
        (std.mem.eql(u8, node_type, "element") and
            std.mem.indexOf(u8, node_type, "script") != null);
}

/// Check if node has event handlers
pub fn hasEventHandler(node_type: []const u8, text: []const u8) bool {
    _ = node_type;
    return std.mem.indexOf(u8, text, "onclick") != null or
        std.mem.indexOf(u8, text, "onload") != null or
        std.mem.indexOf(u8, text, "onchange") != null or
        std.mem.indexOf(u8, text, "onsubmit") != null or
        std.mem.indexOf(u8, text, "function") != null;
}

/// Check if node represents a link element
pub fn isLinkElement(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "link_element") or
        (std.mem.eql(u8, node_type, "element") and
            std.mem.indexOf(u8, node_type, "link") != null);
}

/// Check if node represents a script import
pub fn isScriptImport(node_type: []const u8, text: []const u8) bool {
    _ = node_type;
    return std.mem.indexOf(u8, text, "src=") != null and
        std.mem.indexOf(u8, text, "<script") != null;
}

/// Check if node represents an HTML comment
pub fn isComment(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "comment");
}

/// Extract HTML attributes from elements
pub fn extractAttributes(allocator: std.mem.Allocator, root: *const AstNode, source: []const u8, result: *std.ArrayList(u8)) !void {
    var context = AttributeContext{
        .allocator = allocator,
        .result = result,
        .source = source,
    };

    var visitor = NodeVisitor.init(allocator, extractAttributesVisitor, &context);
    try visitor.traverse(root, source);
}

const AttributeContext = struct {
    allocator: std.mem.Allocator,
    result: *std.ArrayList(u8),
    source: []const u8,
};

/// Visitor function for extracting HTML attributes
fn extractAttributesVisitor(visitor: *NodeVisitor, node: *const AstNode, context: ?*anyopaque) !VisitResult {
    _ = visitor;

    if (context) |ctx| {
        const attr_ctx: *AttributeContext = @ptrCast(@alignCast(ctx));

        // Look for attribute nodes
        if (std.mem.eql(u8, node.node_type, "attribute") or
            std.mem.eql(u8, node.node_type, "attribute_name") or
            std.mem.eql(u8, node.node_type, "attribute_value"))
        {
            try attr_ctx.result.appendSlice(node.text);
            try attr_ctx.result.append('\n');
        }
    }

    return VisitResult.continue_traversal;
}

test "html element detection" {
    const testing = std.testing;

    try testing.expect(isElement("element"));
    try testing.expect(isElement("start_tag"));
    try testing.expect(isElement("end_tag"));
    try testing.expect(!isElement("comment"));
}

test "html structural node detection" {
    const testing = std.testing;

    try testing.expect(isStructuralNode("doctype"));
    try testing.expect(isStructuralNode("document"));
    try testing.expect(!isStructuralNode("element"));
}

test "html script element detection" {
    const testing = std.testing;

    try testing.expect(isScriptElement("script_element"));
    try testing.expect(!isScriptElement("div_element"));
}

test "html comment detection" {
    const testing = std.testing;

    try testing.expect(isComment("comment"));
    try testing.expect(!isComment("element"));
}
