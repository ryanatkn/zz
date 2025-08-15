const std = @import("std");
const Node = @import("../../tree_sitter/node.zig").Node;
const ExtractionContext = @import("../../tree_sitter/visitor.zig").ExtractionContext;

/// AST-based extraction visitor for Zig
pub fn visitor(context: *ExtractionContext, node: *const Node) !void {
    // Extract based on node type and flags
    if (context.flags.signatures or context.flags.structure) {
        // Extract function definitions
        if (isFunctionNode(node.kind)) {
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
        // Extract @import statements
        if (isImportNode(node.kind)) {
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
        }
    }
}

/// Check if node represents a function
fn isFunctionNode(kind: []const u8) bool {
    return std.mem.eql(u8, kind, "function") or
        std.mem.eql(u8, kind, "fn_decl") or
        std.mem.eql(u8, kind, "function_declaration");
}

/// Check if node represents a type definition
fn isTypeNode(kind: []const u8) bool {
    return std.mem.eql(u8, kind, "struct_decl") or
        std.mem.eql(u8, kind, "enum_decl") or
        std.mem.eql(u8, kind, "union_decl") or
        std.mem.eql(u8, kind, "error_set_decl") or
        std.mem.eql(u8, kind, "var_decl") or
        std.mem.eql(u8, kind, "const_decl");
}

/// Check if node represents an import
fn isImportNode(kind: []const u8) bool {
    return std.mem.eql(u8, kind, "builtin_call") or
        std.mem.eql(u8, kind, "@import") or
        std.mem.eql(u8, kind, "@cImport");
}

/// Check if node represents documentation
fn isDocNode(kind: []const u8) bool {
    return std.mem.eql(u8, kind, "doc_comment") or
        std.mem.eql(u8, kind, "comment");
}

/// Check if node represents a test
fn isTestNode(kind: []const u8) bool {
    return std.mem.eql(u8, kind, "test_decl") or
        std.mem.eql(u8, kind, "test");
}

/// Check if node represents an error-related construct
fn isErrorNode(kind: []const u8) bool {
    return std.mem.eql(u8, kind, "error_set_decl") or
        std.mem.eql(u8, kind, "error_value") or
        std.mem.eql(u8, kind, "try_expression") or
        std.mem.eql(u8, kind, "catch_expression");
}
