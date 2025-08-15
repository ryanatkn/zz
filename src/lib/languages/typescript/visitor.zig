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
            std.mem.eql(u8, node_type, "enum_declaration"))
        {
            // Extract full interface/type/enum declarations
            try context.appendNode(node);
            return false;
        }
        if (std.mem.eql(u8, node_type, "class_declaration")) {
            // For classes, extract only type structure without method implementations
            try appendClassTypeStructure(context, node);
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
        if (std.mem.eql(u8, node_type, "import_statement")) {
            try context.appendNode(node);
            return false;
        }
        if (std.mem.eql(u8, node_type, "export_statement")) {
            // For exports, extract only the signature/declaration part
            try appendExportSignature(context, node);
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

/// Extract signature from TypeScript export statement
fn appendExportSignature(context: *ExtractionContext, node: *const Node) !void {
    const text = node.text;
    
    // Handle different export patterns
    if (std.mem.indexOf(u8, text, "export interface") != null) {
        // For interfaces, include "export interface Name {" but stop there
        if (std.mem.indexOf(u8, text, "{")) |brace_pos| {
            const signature = std.mem.trim(u8, text[0..brace_pos + 1], " \t\n\r");
            try context.result.appendSlice(signature);
        } else {
            try context.result.appendSlice(std.mem.trim(u8, text, " \t\n\r"));
        }
    } else if (std.mem.indexOf(u8, text, "export const") != null or 
               std.mem.indexOf(u8, text, "export let") != null or
               std.mem.indexOf(u8, text, "export var") != null) {
        // For variable exports, include up to "="
        if (std.mem.indexOf(u8, text, "=")) |eq_pos| {
            const signature = std.mem.trim(u8, text[0..eq_pos + 1], " \t\n\r");
            try context.result.appendSlice(signature);
        } else {
            try context.result.appendSlice(std.mem.trim(u8, text, " \t\n\r"));
        }
    } else if (std.mem.indexOf(u8, text, "export default") != null) {
        // For default exports, include the full statement (usually just one line)
        var lines = std.mem.splitScalar(u8, text, '\n');
        if (lines.next()) |first_line| {
            try context.result.appendSlice(std.mem.trim(u8, first_line, " \t\n\r"));
        }
    } else {
        // For other export types, use the regular signature extraction
        const signature = @import("../../tree_sitter/visitor.zig").extractSignatureFromText(text);
        try context.result.appendSlice(signature);
    }
    
    // Add newline if not present
    if (!std.mem.endsWith(u8, context.result.items, "\n")) {
        try context.result.append('\n');
    }
}

/// Helper function to extract only the type structure of a class
/// Includes field declarations and constructor signature, but excludes method implementations
fn appendClassTypeStructure(context: *ExtractionContext, node: *const Node) !void {
    var lines = std.mem.splitScalar(u8, node.text, '\n');
    var normalized = std.ArrayList(u8).init(context.allocator);
    defer normalized.deinit();
    
    var prev_line_was_blank = false;
    
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        
        // Check if this line starts a method (but not constructor)
        const is_method_start = trimmed.len > 0 and
            (std.mem.indexOf(u8, trimmed, "(") != null and 
             std.mem.indexOf(u8, trimmed, ")") != null and
             std.mem.endsWith(u8, trimmed, "{")) and
            std.mem.indexOf(u8, trimmed, "constructor") == null;
        
        // If this is a method start, stop processing here
        if (is_method_start) {
            break;
        }
        
        // Skip blank lines to normalize whitespace
        if (trimmed.len == 0) {
            if (!prev_line_was_blank) {
                // Skip this blank line
                prev_line_was_blank = true;
            }
            continue;
        }
        
        // Include non-blank line
        try normalized.appendSlice(line);
        try normalized.append('\n');
        prev_line_was_blank = false;
    }
    
    // Ensure we end with the class closing brace
    const result = normalized.items;
    if (result.len > 0 and !std.mem.endsWith(u8, result, "}")) {
        try normalized.append('}');
        try normalized.append('\n');
    }
    
    // Remove trailing newline if present
    if (normalized.items.len > 0 and normalized.items[normalized.items.len - 1] == '\n') {
        _ = normalized.pop();
    }
    
    // Append the normalized content
    try context.result.appendSlice(normalized.items);
    if (!std.mem.endsWith(u8, normalized.items, "\n")) {
        try context.result.append('\n');
    }
}
