const std = @import("std");
const Node = @import("../../tree_sitter/node.zig").Node;
const ExtractionContext = @import("../../tree_sitter/visitor.zig").ExtractionContext;

/// AST-based extraction visitor for TypeScript
/// Returns true to continue recursion, false to skip children
pub fn visitor(context: *ExtractionContext, node: *const Node) !bool {
    const node_type = node.kind;
    

    // Functions and methods (when signatures flag is set)
    if (context.flags.signatures and !context.flags.structure) {
        if (std.mem.eql(u8, node_type, "function_declaration") or
            std.mem.eql(u8, node_type, "method_definition"))
        {
            // For function declarations, extract just the signature part
            try context.appendSignature(node);
            return false;
        }
        // Arrow functions need special handling - look for variable declarations containing arrow functions
        if (std.mem.eql(u8, node_type, "variable_declaration") or std.mem.eql(u8, node_type, "lexical_declaration")) {
            const text = node.text;
            if (std.mem.indexOf(u8, text, "=>") != null) {
                // This is an arrow function assignment like "const getUserById = async (id: number) => {...}"
                try context.appendSignature(node);
                return false;
            }
        }
    }

    // Types and interfaces (when types flag is set)  
    if (context.flags.types and !context.flags.structure) {
        if (std.mem.eql(u8, node_type, "interface_declaration") or
            std.mem.eql(u8, node_type, "type_alias_declaration") or
            std.mem.eql(u8, node_type, "class_declaration") or
            std.mem.eql(u8, node_type, "enum_declaration"))
        {
            // TODO: Consider extracting only type structure without method implementations
            try context.appendNode(node);
            return false;
        }
    }

    // Structure elements - complete TypeScript structure  
    if (context.flags.structure) {
        // For structure, extract both functions and types
        if (std.mem.eql(u8, node_type, "interface_declaration") or
            std.mem.eql(u8, node_type, "type_alias_declaration") or
            std.mem.eql(u8, node_type, "class_declaration") or
            std.mem.eql(u8, node_type, "enum_declaration") or
            std.mem.eql(u8, node_type, "function_declaration") or
            std.mem.eql(u8, node_type, "method_definition"))
        {
            try context.appendNode(node);
        }
    }

    // Imports and exports
    if (context.flags.imports and !context.flags.structure and !context.flags.signatures and !context.flags.types) {
        if (std.mem.eql(u8, node_type, "import_statement") or
            std.mem.eql(u8, node_type, "export_statement"))
        {
            try context.appendNode(node);
            return false;
        }
    }

    // Tests
    if (context.flags.tests and !context.flags.structure and !context.flags.signatures and !context.flags.types) {
        if (std.mem.eql(u8, node_type, "call_expression")) {
            const text = node.text;
            if (std.mem.startsWith(u8, text, "test(") or
                std.mem.startsWith(u8, text, "it(") or
                std.mem.startsWith(u8, text, "describe("))
            {
                try context.appendNode(node);
                return false;
            }
        }
    }

    // Full source
    if (context.flags.full) {
        // For full extraction, only append the root program node to avoid duplication
        if (std.mem.eql(u8, node_type, "program")) {
            try context.result.appendSlice(node.text);
            return false; // Skip children - we already have full content
        }
    }

    return true; // Continue recursion by default
}
