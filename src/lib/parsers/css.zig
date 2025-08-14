const std = @import("std");
const ts = @import("tree-sitter");
const ExtractionFlags = @import("../ast.zig").ExtractionFlags;
const AstNode = @import("../ast.zig").AstNode;
const NodeVisitor = @import("../ast.zig").NodeVisitor;
const VisitResult = @import("../ast.zig").VisitResult;
const AstWalker = @import("../ast.zig").AstWalker;

pub fn extractSimple(source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) !void {
    // If no specific flags are set or full flag is set, return complete source
    if (flags.isDefault() or flags.full) {
        try result.appendSlice(source);
        return;
    }
    
    var lines = std.mem.tokenizeScalar(u8, source, '\n');
    
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        
        // Skip empty lines
        if (trimmed.len == 0) continue;
        
        var should_include = false;
        
        // Check each flag and include relevant content
        if (flags.types or flags.structure) {
            // Include CSS rules, declarations, and at-rules
            if (std.mem.indexOf(u8, line, "{") != null or
                std.mem.indexOf(u8, line, "}") != null or
                std.mem.indexOf(u8, line, ":") != null or
                std.mem.startsWith(u8, trimmed, "@")) {
                should_include = true;
            }
        }
        
        if (flags.signatures) {
            // CSS selectors only (class names, IDs, elements before opening brace)
            if ((std.mem.startsWith(u8, trimmed, ".") or
                 std.mem.startsWith(u8, trimmed, "#") or
                 std.mem.indexOf(u8, line, "{") != null) and
                !std.mem.startsWith(u8, trimmed, "/*")) {
                should_include = true;
            }
        }
        
        if (flags.imports) {
            if (std.mem.startsWith(u8, trimmed, "@import") or 
                std.mem.startsWith(u8, trimmed, "@use")) {
                should_include = true;
            }
        }
        
        if (flags.docs) {
            if (std.mem.startsWith(u8, trimmed, "/*") or
                std.mem.startsWith(u8, trimmed, "*") or
                std.mem.indexOf(u8, line, "*/") != null) {
                should_include = true;
            }
        }
        
        if (should_include) {
            try result.appendSlice(line);
            try result.append('\n');
        }
    }
}

/// AST-based extraction using CSS-specific logic
pub fn walkNode(allocator: std.mem.Allocator, root: *const AstNode, source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) !void {
    _ = allocator;
    try walkNodeRecursive(root.ts_node, source, flags, result);
}

/// Recursive tree-sitter node walking for CSS
fn walkNodeRecursive(node: ts.Node, source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) !void {
    const node_type = node.kind();
    
    if (flags.signatures) {
        if (isSelector(node_type)) {
            try appendNodeText(node, source, result);
            return; // Don't traverse into selector details
        }
    }
    
    if (flags.types or flags.structure) {
        if (isRule(node_type) or isAtRule(node_type)) {
            try appendNodeText(node, source, result);
            return;
        }
    }
    
    if (flags.imports) {
        if (isImportRule(node_type)) {
            try appendNodeText(node, source, result);
        }
    }
    
    if (flags.docs) {
        if (isComment(node_type)) {
            try appendNodeText(node, source, result);
        }
    }
    
    // Recurse into children
    const child_count = node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        if (node.child(i)) |child| {
            try walkNodeRecursive(child, source, flags, result);
        }
    }
}

/// Helper to append node text with newline
fn appendNodeText(node: ts.Node, source: []const u8, result: *std.ArrayList(u8)) !void {
    const start = node.startByte();
    const end = node.endByte();
    if (end <= source.len) {
        try result.appendSlice(source[start..end]);
        try result.append('\n');
    }
}

const ExtractionContext = struct {
    allocator: std.mem.Allocator,
    result: *std.ArrayList(u8),
    flags: ExtractionFlags,
    source: []const u8,
};

/// Visitor function for CSS extraction
fn cssExtractionVisitor(visitor: *NodeVisitor, node: *const AstNode, context: ?*anyopaque) !VisitResult {
    _ = visitor;
    
    if (context) |ctx| {
        const extraction_ctx: *ExtractionContext = @ptrCast(@alignCast(ctx));
        
        // Extract based on node type and flags
        if (extraction_ctx.flags.signatures) {
            // Extract selectors
            if (isSelector(node.node_type)) {
                try extraction_ctx.result.appendSlice(node.text);
                try extraction_ctx.result.append('\n');
                return VisitResult.skip_children; // Don't traverse into selector details
            }
        }
        
        if (extraction_ctx.flags.types or extraction_ctx.flags.structure) {
            // Extract rules, at-rules, and declarations
            if (isRule(node.node_type) or isAtRule(node.node_type)) {
                try extraction_ctx.result.appendSlice(node.text);
                try extraction_ctx.result.append('\n');
                return VisitResult.skip_children;
            }
        }
        
        if (extraction_ctx.flags.imports) {
            // Extract import statements
            if (isImportRule(node.node_type)) {
                try extraction_ctx.result.appendSlice(node.text);
                try extraction_ctx.result.append('\n');
            }
        }
        
        if (extraction_ctx.flags.docs) {
            // Extract comments
            if (isComment(node.node_type)) {
                try extraction_ctx.result.appendSlice(node.text);
                try extraction_ctx.result.append('\n');
            }
        }
    }
    
    return VisitResult.continue_traversal;
}

/// Check if node represents a CSS selector
pub fn isSelector(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "selectors") or
           std.mem.eql(u8, node_type, "class_selector") or
           std.mem.eql(u8, node_type, "id_selector") or
           std.mem.eql(u8, node_type, "tag_name") or
           std.mem.eql(u8, node_type, "universal_selector") or
           std.mem.eql(u8, node_type, "attribute_selector") or
           std.mem.eql(u8, node_type, "pseudo_class_selector") or
           std.mem.eql(u8, node_type, "pseudo_element_selector");
}

/// Check if node represents a CSS rule
pub fn isRule(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "rule_set") or
           std.mem.eql(u8, node_type, "declaration") or
           std.mem.eql(u8, node_type, "property_name") or
           std.mem.eql(u8, node_type, "value");
}

/// Check if node represents a CSS at-rule
pub fn isAtRule(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "at_rule") or
           std.mem.eql(u8, node_type, "media_query") or
           std.mem.eql(u8, node_type, "keyframes_statement") or
           std.mem.eql(u8, node_type, "supports_statement");
}

/// Check if node represents a CSS import rule
pub fn isImportRule(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "import_statement") or
           std.mem.eql(u8, node_type, "at_rule") and 
           std.mem.startsWith(u8, node_type, "@import");
}

/// Check if node represents a CSS comment
pub fn isComment(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "comment");
}

/// Extract CSS variables/custom properties
pub fn extractVariables(allocator: std.mem.Allocator, root: *const AstNode, source: []const u8, result: *std.ArrayList(u8)) !void {
    var context = VariableContext{
        .allocator = allocator,
        .result = result,
        .source = source,
    };
    
    var visitor = NodeVisitor.init(allocator, extractVariablesVisitor, &context);
    try visitor.traverse(root, source);
}

const VariableContext = struct {
    allocator: std.mem.Allocator,
    result: *std.ArrayList(u8),
    source: []const u8,
};

/// Visitor function for extracting CSS variables
fn extractVariablesVisitor(visitor: *NodeVisitor, node: *const AstNode, context: ?*anyopaque) !VisitResult {
    _ = visitor;
    
    if (context) |ctx| {
        const var_ctx: *VariableContext = @ptrCast(@alignCast(ctx));
        
        // Look for CSS custom properties (variables)
        if (std.mem.eql(u8, node.node_type, "property_name") and
            std.mem.startsWith(u8, node.text, "--")) {
            try var_ctx.result.appendSlice(node.text);
            try var_ctx.result.append('\n');
        }
    }
    
    return VisitResult.continue_traversal;
}

/// Extract media queries
pub fn extractMediaQueries(allocator: std.mem.Allocator, root: *const AstNode, source: []const u8, result: *std.ArrayList(u8)) !void {
    var context = MediaQueryContext{
        .allocator = allocator,
        .result = result,
        .source = source,
    };
    
    var visitor = NodeVisitor.init(allocator, extractMediaQueriesVisitor, &context);
    try visitor.traverse(root, source);
}

const MediaQueryContext = struct {
    allocator: std.mem.Allocator,
    result: *std.ArrayList(u8),
    source: []const u8,
};

/// Visitor function for extracting media queries
fn extractMediaQueriesVisitor(visitor: *NodeVisitor, node: *const AstNode, context: ?*anyopaque) !VisitResult {
    _ = visitor;
    
    if (context) |ctx| {
        const media_ctx: *MediaQueryContext = @ptrCast(@alignCast(ctx));
        
        // Look for media query nodes
        if (std.mem.eql(u8, node.node_type, "media_query") or
            (std.mem.eql(u8, node.node_type, "at_rule") and
             std.mem.startsWith(u8, node.text, "@media"))) {
            try media_ctx.result.appendSlice(node.text);
            try media_ctx.result.append('\n');
            return VisitResult.skip_children;
        }
    }
    
    return VisitResult.continue_traversal;
}

test "css selector detection" {
    const testing = std.testing;
    
    try testing.expect(isSelector("class_selector"));
    try testing.expect(isSelector("id_selector"));
    try testing.expect(isSelector("tag_name"));
    try testing.expect(!isSelector("declaration"));
}

test "css rule detection" {
    const testing = std.testing;
    
    try testing.expect(isRule("rule_set"));
    try testing.expect(isRule("declaration"));
    try testing.expect(!isRule("class_selector"));
}

test "css at-rule detection" {
    const testing = std.testing;
    
    try testing.expect(isAtRule("at_rule"));
    try testing.expect(isAtRule("media_query"));
    try testing.expect(!isAtRule("rule_set"));
}

test "css comment detection" {
    const testing = std.testing;
    
    try testing.expect(isComment("comment"));
    try testing.expect(!isComment("declaration"));
}