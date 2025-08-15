const std = @import("std");
const Node = @import("../../tree_sitter/node.zig").Node;
const ExtractionContext = @import("../../tree_sitter/visitor.zig").ExtractionContext;

/// AST-based extraction visitor for Zig
/// Returns true to continue recursion, false to skip children
pub fn visitor(context: *ExtractionContext, node: *const Node) !bool {
    // Extract based on node type and flags
    if (context.flags.signatures or context.flags.structure) {
        // Extract function definitions
        if (isFunctionNode(node.kind, node.text)) {
            try context.appendNode(node);
        }
    }

    if (context.flags.types or context.flags.structure) {
        // Extract type definitions (struct, enum, union, etc.)
        if (isTypeNode(node.kind)) {
            try context.appendNode(node);
        }
    }

    if (context.flags.imports) {
        // Extract @import statements - look for VarDecl containing @import
        if (isImportNode(node.kind, node.text)) {
            try context.appendNode(node);
        }
    }

    if (context.flags.docs) {
        // Extract documentation comments
        if (isDocNode(node.kind)) {
            try context.appendNode(node);
        }
    }

    if (context.flags.tests) {
        // Extract test blocks
        if (isTestNode(node.kind)) {
            try context.appendNode(node);
        }
    }

    if (context.flags.errors) {
        // Extract error definitions and error handling
        if (isErrorNode(node.kind)) {
            try context.appendNode(node);
        }
    }

    if (context.flags.full) {
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
    if (std.mem.eql(u8, kind, "FnProto")) {
        return true;
    }
    // Check if Decl contains a function
    if (std.mem.eql(u8, kind, "Decl")) {
        return std.mem.indexOf(u8, text, "fn ") != null;
    }
    return false;
}

/// Check if node represents a type definition
fn isTypeNode(kind: []const u8) bool {
    return std.mem.eql(u8, kind, "struct") or
        std.mem.eql(u8, kind, "enum") or
        std.mem.eql(u8, kind, "union") or
        std.mem.eql(u8, kind, "ErrorSetDecl") or
        std.mem.eql(u8, kind, "VarDecl");
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
