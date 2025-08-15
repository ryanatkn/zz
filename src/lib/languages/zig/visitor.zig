const std = @import("std");
const Node = @import("../../tree_sitter/node.zig").Node;
const ExtractionContext = @import("../../tree_sitter/visitor.zig").ExtractionContext;

/// AST-based extraction visitor for Zig
/// Returns true to continue recursion, false to skip children
pub fn visitor(context: *ExtractionContext, node: *const Node) !bool {
    // Extract based on node type and flags
    if (context.flags.signatures and !context.flags.structure and !context.flags.types) {
        // For signatures only, extract only function definitions
        if (isFunctionNode(node.kind, node.text)) {
            try context.appendSignature(node);
        }
        // Don't extract type nodes when only signatures are requested
        // Always continue recursion to find functions inside structs/types
        return true;
    } else if (context.flags.types and !context.flags.structure and !context.flags.signatures) {
        // For types only, extract type definitions without method implementations
        if (isTypeNode(node.kind)) {
            try extractTypeDefinition(context, node);
            return false; // Skip children to avoid method implementations
        }
    } else if (context.flags.structure) {
        // For structure, extract both functions and types
        if (isFunctionNode(node.kind, node.text) or isTypeNode(node.kind)) {
            try context.appendNode(node);
        }
    } else if (context.flags.imports) {
        // Extract @import statements - look for VarDecl containing @import
        if (isImportNode(node.kind, node.text)) {
            try context.appendNode(node);
        }
    } else if (context.flags.docs) {
        // Extract documentation comments
        if (isDocNode(node.kind)) {
            try context.appendNode(node);
        }
    } else if (context.flags.tests) {
        // Extract test blocks
        if (isTestNode(node.kind)) {
            try context.appendNode(node);
        }
    } else if (context.flags.errors) {
        // Extract error definitions and error handling
        if (isErrorNode(node.kind)) {
            try context.appendNode(node);
        }
    } else if (context.flags.full) {
        // For full extraction, only append the root source_file node to avoid duplication
        if (std.mem.eql(u8, node.kind, "source_file")) {
            try context.result.appendSlice(node.text);
            return false; // Skip children - we already have full content
        }
    }

    return true; // Continue recursion by default
}

/// Check if node represents a function
fn isFunctionNode(kind: []const u8, text: []const u8) bool {
    // Look for Decl nodes that contain function declarations (includes pub)
    if (std.mem.eql(u8, kind, "Decl")) {
        // Only match if it contains "fn " and doesn't start with "const" (to avoid structs)
        const contains_fn = std.mem.indexOf(u8, text, "fn ") != null;
        const not_const_decl = !std.mem.startsWith(u8, std.mem.trim(u8, text, " \t\n\r"), "const");
        
        // TODO: Missing 'pub' keyword in extracted signatures - 
        // the Decl nodes might not include visibility modifiers.
        // Need to check if pub is in a parent node or different AST structure.
        
        return contains_fn and not_const_decl;
    }
    return false;
}

/// Check if node represents a type definition
fn isTypeNode(kind: []const u8) bool {
    // Be more specific about type nodes to avoid extracting variable declarations
    return std.mem.eql(u8, kind, "struct") or
        std.mem.eql(u8, kind, "enum") or
        std.mem.eql(u8, kind, "union") or
        std.mem.eql(u8, kind, "ErrorSetDecl");
    // TODO: VarDecl was causing issues - need to be more specific about when to include it
}

/// Check if node represents an import
fn isImportNode(kind: []const u8, text: []const u8) bool {
    // Look for BUILTINIDENTIFIER that is @import
    if (std.mem.eql(u8, kind, "BUILTINIDENTIFIER")) {
        return std.mem.indexOf(u8, text, "@import") != null;
    }
    // Look for VarDecl containing @import
    if (std.mem.eql(u8, kind, "VarDecl")) {
        return std.mem.indexOf(u8, text, "@import") != null;
    }
    return false;
}

/// Check if node represents documentation
fn isDocNode(kind: []const u8) bool {
    return std.mem.eql(u8, kind, "doc_comment") or
        std.mem.eql(u8, kind, "container_doc_comment") or
        std.mem.eql(u8, kind, "line_comment");
}

/// Check if node represents a test
fn isTestNode(kind: []const u8) bool {
    return std.mem.eql(u8, kind, "TestDecl");
}

/// Check if node represents an error-related construct
fn isErrorNode(kind: []const u8) bool {
    return std.mem.eql(u8, kind, "ErrorSetDecl") or
        std.mem.eql(u8, kind, "ErrorUnionExpr");
}

/// Extract type definition without method implementations
fn extractTypeDefinition(context: *ExtractionContext, node: *const Node) !void {
    // TODO: Implement proper type extraction that excludes method bodies
    // For now, fall back to full node extraction until we can analyze the AST structure
    // to separate type fields from method implementations
    try context.appendNode(node);
}
