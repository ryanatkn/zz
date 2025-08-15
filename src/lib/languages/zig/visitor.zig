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
            try appendZigSignature(context, node);
        }
        // Don't extract type nodes when only signatures are requested
        // Always continue recursion to find functions inside structs/types
        return true;
    } else if (context.flags.types and !context.flags.structure and !context.flags.signatures) {
        // For types only, extract type definitions without method implementations
        if (isTypeNode(node.kind, node.text)) {
            try extractTypeDefinition(context, node);
            return false; // Skip children to avoid method implementations
        }
    } else if (context.flags.structure) {
        // For structure, extract both functions and types
        if (isFunctionNode(node.kind, node.text) or isTypeNode(node.kind, node.text)) {
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
    // Look for VarDecl nodes that contain full function declarations (includes pub/priv)
    if (std.mem.eql(u8, kind, "VarDecl")) {
        const contains_fn = std.mem.indexOf(u8, text, "fn ") != null;
        const not_import = std.mem.indexOf(u8, text, "@import") == null;
        const not_struct_def = std.mem.indexOf(u8, text, "struct") == null; // Don't extract struct definitions
        return contains_fn and not_import and not_struct_def;
    }
    
    // Look for Decl nodes that contain function declarations (but these miss pub keyword)
    if (std.mem.eql(u8, kind, "Decl")) {
        // Only match if it contains "fn " and doesn't start with "const" (to avoid structs)
        const contains_fn = std.mem.indexOf(u8, text, "fn ") != null;
        const not_const_decl = !std.mem.startsWith(u8, std.mem.trim(u8, text, " \t\n\r"), "const");
        return contains_fn and not_const_decl;
    }
    
    return false;
}

/// Check if node represents a type definition
fn isTypeNode(kind: []const u8, text: []const u8) bool {
    // Look for VarDecl nodes that contain type definitions
    if (std.mem.eql(u8, kind, "VarDecl")) {
        const trimmed = std.mem.trim(u8, text, " \t\n\r");
        // Check if it's a type declaration (const Name = struct/enum/union)
        if (std.mem.startsWith(u8, trimmed, "const ") or std.mem.startsWith(u8, trimmed, "pub const ")) {
            return std.mem.indexOf(u8, text, "struct") != null or
                   std.mem.indexOf(u8, text, "enum") != null or
                   std.mem.indexOf(u8, text, "union") != null;
        }
    }
    
    // Also handle direct struct/enum/union nodes (but these are usually incomplete)
    return std.mem.eql(u8, kind, "struct") or
        std.mem.eql(u8, kind, "enum") or
        std.mem.eql(u8, kind, "union") or
        std.mem.eql(u8, kind, "ErrorSetDecl");
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
    // For VarDecl nodes containing type definitions, we need to extract just the type
    // structure but exclude method implementations
    if (std.mem.eql(u8, node.kind, "VarDecl")) {
        const text = node.text;
        
        // TODO: For now, extract the full VarDecl node text
        // Later we can implement more sophisticated filtering to remove method bodies
        // but keep field definitions
        try context.result.appendSlice(text);
        if (!std.mem.endsWith(u8, text, "\n")) {
            try context.result.append('\n');
        }
        return;
    }
    
    // Fall back to full node extraction for other node types
    try context.appendNode(node);
}

/// Append Zig function signature with proper pub keyword handling
fn appendZigSignature(context: *ExtractionContext, node: *const Node) !void {
    const basic_signature = @import("../../tree_sitter/visitor.zig").extractSignatureFromText(node.text);
    
    // Check if the signature is missing 'pub' but should have it
    if (std.mem.indexOf(u8, basic_signature, "fn ") != null and 
        std.mem.indexOf(u8, basic_signature, "pub ") == null) {
        
        // Look in the original source to see if this function has 'pub'
        if (std.mem.indexOf(u8, context.source, node.text)) |node_pos| {
            // Look backwards from the node position to find 'pub'
            const search_start = if (node_pos >= 20) node_pos - 20 else 0;
            const search_text = context.source[search_start..node_pos];
            
            if (std.mem.lastIndexOf(u8, search_text, "pub")) |pub_relative_pos| {
                const pub_pos = search_start + pub_relative_pos;
                
                // Check that 'pub' is followed by whitespace and is close to our node
                if (pub_pos + 3 < context.source.len and 
                    std.ascii.isWhitespace(context.source[pub_pos + 3])) {
                    
                    const text_between = context.source[pub_pos + 3..node_pos];
                    // Only include 'pub' if there's minimal text between (whitespace/newlines)
                    const is_close = std.mem.trim(u8, text_between, " \t\n\r").len == 0;
                    
                    if (is_close) {
                        // Prepend 'pub ' to the signature
                        try context.result.appendSlice("pub ");
                        try context.result.appendSlice(basic_signature);
                        if (!std.mem.endsWith(u8, basic_signature, "\n")) {
                            try context.result.append('\n');
                        }
                        return;
                    }
                }
            }
        }
    }
    
    // Fall back to basic signature
    try context.result.appendSlice(basic_signature);
    if (!std.mem.endsWith(u8, basic_signature, "\n")) {
        try context.result.append('\n');
    }
}
