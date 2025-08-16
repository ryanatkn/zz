const std = @import("std");
const Node = @import("../../tree_sitter/node.zig").Node;
const ExtractionContext = @import("../../tree_sitter/visitor.zig").ExtractionContext;
const builders = @import("../../text/builders.zig");

/// AST-based extraction visitor for TypeScript
/// Returns true to continue recursion, false to skip children
pub fn visitor(context: *ExtractionContext, node: *const Node) !bool {
    const node_type = node.kind;
    
    // Documentation comments (JSDoc, block comments, line comments)
    if (context.flags.docs) {
        if (std.mem.eql(u8, node_type, "comment") or
            std.mem.eql(u8, node_type, "jsdoc") or
            std.mem.startsWith(u8, node_type, "comment_"))
        {
            try context.appendNode(node);
            return false;
        }
    }

    // Error handling patterns (try/catch, throw, Error types)
    if (context.flags.errors) {
        if (std.mem.eql(u8, node_type, "try_statement") or
            std.mem.eql(u8, node_type, "catch_clause") or
            std.mem.eql(u8, node_type, "throw_statement") or
            std.mem.eql(u8, node_type, "finally_clause"))
        {
            try context.appendNode(node);
            return false;
        }
        // Error types and interfaces
        const text = node.text;
        if (std.mem.indexOf(u8, text, "Error") != null and
            (std.mem.eql(u8, node_type, "type_alias_declaration") or
             std.mem.eql(u8, node_type, "interface_declaration")))
        {
            try context.appendNode(node);
            return false;
        }
    }

    // Functions and methods (when signatures flag is set)
    if (context.flags.signatures) {
        if (std.mem.eql(u8, node_type, "function_declaration") or
            std.mem.eql(u8, node_type, "method_definition"))
        {
            // For function declarations, extract just the signature part
            try context.appendSignature(node);
            return false;
        }
        // Handle classes - extract method signatures only (unless types flag is also set)
        if (std.mem.eql(u8, node_type, "class_declaration") and !context.flags.types) {
            try appendClassSignaturesSimple(context, node);
            return false;
        }
        // Arrow functions need special handling - look for variable declarations containing arrow functions
        if (std.mem.eql(u8, node_type, "variable_declaration") or std.mem.eql(u8, node_type, "lexical_declaration")) {
            const text = node.text;
            if (std.mem.indexOf(u8, text, "=>") != null) {
                // This is an arrow function assignment like "const getUserById = async (id: number) => {...}"
                try appendArrowFunctionSignature(context, node);
                return false;
            }
        }
        // Export statements with arrow functions - extract the signature with export keyword
        if (std.mem.eql(u8, node_type, "export_statement")) {
            const text = node.text;
            // Skip export interface in signatures-only mode (interfaces are not function signatures)
            if (std.mem.indexOf(u8, text, "export interface") != null) {
                return false; // Skip interfaces in signatures-only mode
            }
            if (std.mem.indexOf(u8, text, "=>") != null) {
                // This is an exported arrow function like "export const UserProfile = () => {...}"
                try appendArrowFunctionSignature(context, node);
                return false;
            }
        }
    }

    // Types and interfaces (when types flag is set)  
    if (context.flags.types) {
        if (std.mem.eql(u8, node_type, "interface_declaration") or
            std.mem.eql(u8, node_type, "type_alias_declaration") or
            std.mem.eql(u8, node_type, "enum_declaration"))
        {
            // Extract full interface/type/enum declarations
            try context.appendNode(node);
            return false;
        }
        if (std.mem.eql(u8, node_type, "class_declaration")) {
            if (context.flags.signatures) {
                // When both types and signatures are set, extract full class content
                try context.appendNode(node);
                return false;
            } else {
                // Types only - extract the full class declaration 
                try context.appendNode(node);
                return false;
            }
        }
    }
    
    // Skip interfaces in signatures-only mode (they're not function signatures)
    if (context.flags.signatures and !context.flags.types and !context.flags.structure) {
        if (std.mem.eql(u8, node_type, "interface_declaration")) {
            return false;
        }
    }

    // Structure elements - complete TypeScript structure without duplication
    if (context.flags.structure) {
        // For structure, extract both functions and types but avoid duplication
        if (std.mem.eql(u8, node_type, "interface_declaration") or
            std.mem.eql(u8, node_type, "type_alias_declaration") or
            std.mem.eql(u8, node_type, "class_declaration") or
            std.mem.eql(u8, node_type, "enum_declaration") or
            std.mem.eql(u8, node_type, "function_declaration"))
        {
            try context.appendNode(node);
            return false; // Skip children to avoid duplication
        }
    }

    // Imports only (no exports when imports flag is set)
    if (context.flags.imports and !context.flags.structure and !context.flags.signatures and !context.flags.types) {
        if (std.mem.eql(u8, node_type, "import_statement")) {
            try context.appendNode(node);
            return false;
        }
        // Skip exports in imports-only mode
        if (std.mem.eql(u8, node_type, "export_statement")) {
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
    const text = node.text;
    var lines = std.mem.splitScalar(u8, text, '\n');
    var builder = builders.ResultBuilder.init(context.allocator);
    defer builder.deinit();
    
    var in_constructor = false;
    var constructor_brace_count: i32 = 0;
    var skip_method = false;
    var method_brace_count: i32 = 0;
    
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        
        // Skip empty lines
        if (trimmed.len == 0) {
            continue;
        }
        
        // Check if this is a method declaration (not constructor)
        if (!in_constructor and !skip_method and trimmed.len > 0) {
            const has_params = std.mem.indexOf(u8, trimmed, "(") != null and std.mem.indexOf(u8, trimmed, ")") != null;
            const has_brace = std.mem.indexOf(u8, trimmed, "{") != null;
            const is_constructor = std.mem.indexOf(u8, trimmed, "constructor") != null;
            
            if (has_params and has_brace and !is_constructor) {
                // This is a method, skip it
                skip_method = true;
                method_brace_count = 1; // Count the opening brace
                continue;
            } else if (is_constructor) {
                in_constructor = true;
                if (has_brace) {
                    constructor_brace_count = 1;
                }
                // For constructor, extract just the signature with proper indentation
                if (std.mem.indexOf(u8, trimmed, "{")) |brace_pos| {
                    const signature = std.mem.trim(u8, trimmed[0..brace_pos], " \t");
                    // Preserve the original indentation from the line
                    const indent_end = std.mem.indexOf(u8, line, signature) orelse 0;
                    const indentation = line[0..indent_end];
                    try builder.append(indentation);
                    try builder.append(signature);
                    try builder.append(" {}");
                    try builder.appendChar('\n');
                } else {
                    try builder.append(line);
                    try builder.appendChar('\n');
                }
                continue;
            }
        }
        
        // Handle constructor body (skip it)
        if (in_constructor) {
            // Count braces to know when constructor ends
            var i: usize = 0;
            while (i < trimmed.len) {
                if (trimmed[i] == '{') {
                    constructor_brace_count += 1;
                } else if (trimmed[i] == '}') {
                    constructor_brace_count -= 1;
                    if (constructor_brace_count == 0) {
                        in_constructor = false;
                        break;
                    }
                }
                i += 1;
            }
            continue;
        }
        
        // Handle method body (skip it)
        if (skip_method) {
            // Count braces to know when method ends
            var i: usize = 0;
            while (i < trimmed.len) {
                if (trimmed[i] == '{') {
                    method_brace_count += 1;
                } else if (trimmed[i] == '}') {
                    method_brace_count -= 1;
                    if (method_brace_count == 0) {
                        skip_method = false;
                        break;
                    }
                }
                i += 1;
            }
            continue;
        }
        
        // Include class declaration, field declarations, etc.
        try builder.append(line);
        try builder.appendChar('\n');
    }
    
    // Ensure class ends with closing brace if it doesn't already
    const result_text = builder.items();
    if (result_text.len > 0 and !std.mem.endsWith(u8, result_text, "}") and !std.mem.endsWith(u8, result_text, "}\n")) {
        try builder.append("}");
    }
    
    // Remove trailing newline if present
    if (builder.len() > 0 and builder.items()[builder.len() - 1] == '\n') {
        _ = builder.list().pop();
    }
    
    // Append the result
    try context.result.appendSlice(builder.items());
    if (!std.mem.endsWith(u8, context.result.items, "\n")) {
        try context.result.append('\n');
    }
}

/// Extract method signatures from a class declaration (simple text-based approach)
fn appendClassSignaturesSimple(context: *ExtractionContext, node: *const Node) !void {
    const text = node.text;
    var lines = std.mem.splitScalar(u8, text, '\n');
    
    // Skip class declaration line
    _ = lines.next();
    
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        
        // Skip empty lines, comments, closing braces, and code statements
        // Note: Don't skip constructor signatures
        if (trimmed.len == 0 or 
            std.mem.startsWith(u8, trimmed, "//") or
            std.mem.startsWith(u8, trimmed, "/*") or
            std.mem.startsWith(u8, trimmed, "*") or
            std.mem.eql(u8, trimmed, "}") or
            std.mem.startsWith(u8, trimmed, "this.") or
            std.mem.startsWith(u8, trimmed, "return") or
            std.mem.startsWith(u8, trimmed, "console.") or
            std.mem.startsWith(u8, trimmed, "await") or
            (std.mem.startsWith(u8, trimmed, "const") and !std.mem.startsWith(u8, trimmed, "constructor")) or
            std.mem.startsWith(u8, trimmed, "let") or
            std.mem.startsWith(u8, trimmed, "var") or
            std.mem.startsWith(u8, trimmed, "if") or
            std.mem.startsWith(u8, trimmed, "try") or
            std.mem.startsWith(u8, trimmed, "} catch") or
            std.mem.startsWith(u8, trimmed, "} finally"))
        {
            continue;
        }
        
        // Look for method signatures - must have parentheses and be at the beginning of a line
        if (std.mem.indexOf(u8, trimmed, "(") != null and 
            std.mem.indexOf(u8, trimmed, ")") != null and
            !std.mem.startsWith(u8, trimmed, "}")) 
        {
            // This looks like a method signature if it has an opening brace at the end
            if (std.mem.indexOf(u8, trimmed, "{")) |brace_pos| {
                // Extract signature up to opening brace
                const signature = std.mem.trim(u8, trimmed[0..brace_pos], " \t");
                try context.result.appendSlice(signature);
                try context.result.append('\n');
            }
        }
    }
}

/// Extract arrow function signature including parameters
fn appendArrowFunctionSignature(context: *ExtractionContext, node: *const Node) !void {
    const text = node.text;
    
    // Find the "=>" position
    if (std.mem.indexOf(u8, text, "=>")) |arrow_pos| {
        // Extract everything up to and including "=>"
        const signature_end = arrow_pos + 2;
        const signature = std.mem.trim(u8, text[0..signature_end], " \t\n\r");
        
        try context.result.appendSlice(signature);
        if (!std.mem.endsWith(u8, signature, "\n")) {
            try context.result.append('\n');
        }
    } else {
        // Fallback to regular signature extraction
        try context.appendSignature(node);
    }
}
