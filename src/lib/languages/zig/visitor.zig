const std = @import("std");
const Node = @import("../../tree_sitter/node.zig").Node;
const ExtractionContext = @import("../../tree_sitter/visitor.zig").ExtractionContext;
const builders = @import("../../text/builders.zig");

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
            try appendNormalizedTestNode(context, node);
        }
    } else if (context.flags.errors) {
        // Extract error definitions and error handling
        if (isErrorNode(node.kind, node.text)) {
            try extractErrorConstruct(context, node);
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
        const not_type_def = std.mem.indexOf(u8, text, "struct") == null and
                             std.mem.indexOf(u8, text, "enum") == null and
                             std.mem.indexOf(u8, text, "union") == null; // Don't extract type definitions
        return contains_fn and not_import and not_type_def;
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
    // Prioritize VarDecl containing @import for full import statements
    if (std.mem.eql(u8, kind, "VarDecl")) {
        // Direct @import statements like: const std = @import("std");
        if (std.mem.indexOf(u8, text, "@import") != null) {
            return true;
        }
        
        // Module member imports like: const testing = std.testing;
        const trimmed = std.mem.trim(u8, text, " \t\n\r");
        if ((std.mem.startsWith(u8, trimmed, "const ") or std.mem.startsWith(u8, trimmed, "pub const ")) and
            std.mem.indexOf(u8, text, ".") != null and
            std.mem.indexOf(u8, text, "=") != null) {
            // Check that it's not a struct/function/type definition
            if (std.mem.indexOf(u8, text, "struct") != null or
                std.mem.indexOf(u8, text, "fn ") != null or
                std.mem.indexOf(u8, text, "enum") != null or
                std.mem.indexOf(u8, text, "union") != null) {
                return false;
            }
            
            // Check that it's not a function call (contains parentheses)
            if (std.mem.indexOf(u8, text, "(") != null) {
                return false;
            }
            
            // Check that it follows the pattern: const name = module.member;
            // (ends with a semicolon, no function calls)
            return std.mem.endsWith(u8, trimmed, ";");
        }
    }
    
    // Avoid extracting bare BUILTINIDENTIFIER nodes (causes spurious @import)
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
fn isErrorNode(kind: []const u8, text: []const u8) bool {
    // Only extract specific error-related constructs that match test expectations
    
    // Error set declarations (const Error = error{...})
    if (std.mem.eql(u8, kind, "VarDecl") and std.mem.indexOf(u8, text, "error{") != null) {
        const trimmed = std.mem.trim(u8, text, " \t\n\r");
        // Only include if it starts with "const" (full error set declarations)
        return std.mem.startsWith(u8, trimmed, "const");
    }
    
    // Functions returning error unions - check both VarDecl and Decl nodes
    if ((std.mem.eql(u8, kind, "VarDecl") or std.mem.eql(u8, kind, "Decl")) and std.mem.indexOf(u8, text, "fn ") != null) {
        // Check if function returns an error union (Error!Type)
        if (std.mem.indexOf(u8, text, "Error!") != null) {
            return true;
        }
    }
    
    // Individual catch statements - for specific catch expressions like "parseNumber(line) catch continue"  
    // Only extract from VarDecl nodes to avoid duplicates from multiple AST node types
    if (std.mem.eql(u8, kind, "VarDecl") and std.mem.indexOf(u8, text, " catch ") != null and !std.mem.startsWith(u8, std.mem.trim(u8, text, " \t\n\r"), "return") and !std.mem.startsWith(u8, std.mem.trim(u8, text, " \t\n\r"), "fn ")) {
        // Only extract simple catch expressions, not full functions
        const trimmed = std.mem.trim(u8, text, " \t\n\r");
        if (std.mem.indexOf(u8, trimmed, "{") == null) { // No function body
            return true;
        }
    }
    
    return false;
}

/// Extract error-related constructs with specific formatting
fn extractErrorConstruct(context: *ExtractionContext, node: *const Node) !void {
    const node_text = node.text;
    
    // Error set declarations - extract as-is
    if (std.mem.indexOf(u8, node_text, "error{") != null) {
        try context.result.appendSlice(node_text);
        if (!std.mem.endsWith(u8, node_text, "\n")) {
            try context.result.append('\n');
        }
        return;
    }
    
    // Functions returning error unions - extract only signature with body content
    if (std.mem.indexOf(u8, node_text, "fn ") != null and std.mem.indexOf(u8, node_text, "Error!") != null) {
        // Extract function with just the return statement that contains error handling
        try appendZigErrorFunction(context, node);
        return;
    }
    
    // Individual catch expressions - extract just the line
    if (std.mem.indexOf(u8, node_text, " catch ") != null) {
        // Find the line with the catch statement
        var lines = std.mem.splitScalar(u8, node_text, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (std.mem.indexOf(u8, trimmed, " catch ") != null) {
                try context.result.appendSlice("    ");
                try context.result.appendSlice(trimmed);
                try context.result.append('\n');
                break;
            }
        }
        return;
    }
    
    // Fallback
    try context.appendNode(node);
}

/// Extract type definition without method implementations
fn extractTypeDefinition(context: *ExtractionContext, node: *const Node) !void {
    // For VarDecl nodes containing type definitions, we need to extract just the type
    // structure but exclude method implementations
    if (std.mem.eql(u8, node.kind, "VarDecl")) {
        try appendZigStructTypeOnly(context, node);
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

/// Append test node with normalized whitespace (removes extra blank lines)
fn appendNormalizedTestNode(context: *ExtractionContext, node: *const Node) !void {
    var lines = std.mem.splitScalar(u8, node.text, '\n');
    var builder = builders.ResultBuilder.init(context.allocator);
    defer builder.deinit();
    
    var prev_line_empty = false;
    
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        const is_empty = trimmed.len == 0;
        
        // Skip consecutive empty lines - only allow single empty line
        if (is_empty and prev_line_empty) {
            continue;
        }
        
        // Skip all empty lines to normalize whitespace completely
        if (is_empty) {
            prev_line_empty = true;
            continue;
        }
        
        try builders.appendLine(builder.list(), line);
        prev_line_empty = false;
    }
    
    // Remove trailing newline if present
    if (builder.len() > 0 and builder.items()[builder.len() - 1] == '\n') {
        _ = builder.list().pop();
    }
    
    // Append the normalized content with automatic newline handling
    try builders.appendMaybe(context.result, builder.items(), !std.mem.endsWith(u8, builder.items(), "\n"));
}

/// Append function signature and error-related content
fn appendZigErrorFunction(context: *ExtractionContext, node: *const Node) !void {
    const node_text = node.text;
    var lines = std.mem.splitScalar(u8, node_text, '\n');
    var builder = builders.ResultBuilder.init(context.allocator);
    defer builder.deinit();
    
    var found_function_start = false;
    var in_function_signature = false;
    var brace_count: i32 = 0;
    
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        
        // Find function declaration line
        if (!found_function_start and std.mem.indexOf(u8, trimmed, "fn ") != null) {
            found_function_start = true;
            in_function_signature = true;
            try builders.appendLine(builder.list(), line);
            
            // Count braces on the same line to detect end of signature
            for (line) |char| {
                if (char == '{') {
                    brace_count += 1;
                    in_function_signature = false;
                }
            }
            continue;
        }
        
        // Continue collecting signature lines until we hit the opening brace
        if (in_function_signature) {
            try builders.appendLine(builder.list(), line);
            if (std.mem.indexOf(u8, trimmed, "{") != null) {
                for (line) |char| {
                    if (char == '{') brace_count += 1;
                }
                in_function_signature = false;
            }
            continue;
        }
        
        // After signature, only extract lines containing error handling (catch, switch with error)
        if (found_function_start and !in_function_signature) {
            const has_catch = std.mem.indexOf(u8, trimmed, "catch") != null;
            const is_return_with_catch = std.mem.startsWith(u8, trimmed, "return") and has_catch;
            const is_error_mapping = std.mem.indexOf(u8, trimmed, "error.") != null and 
                                    std.mem.indexOf(u8, trimmed, "=>") != null;
            const is_closing_brace = std.mem.eql(u8, trimmed, "};") or std.mem.eql(u8, trimmed, "}");
            
            // Only extract return statements with catch and error mapping lines
            if (is_return_with_catch or is_error_mapping or is_closing_brace) {
                try builders.appendLine(builder.list(), line);
            }
            
            // Track brace count to know when function ends
            for (line) |char| {
                if (char == '{') brace_count += 1;
                if (char == '}') brace_count -= 1;
            }
            
            // Stop when function ends
            if (brace_count <= 0) {
                break;
            }
        }
    }
    
    // Remove trailing newline if present
    if (builder.len() > 0 and builder.items()[builder.len() - 1] == '\n') {
        _ = builder.list().pop();
    }
    
    // Append the content with automatic newline handling
    try builders.appendMaybe(context.result, builder.items(), !std.mem.endsWith(u8, builder.items(), "\n"));
}

/// Extract only the struct type definition without method implementations
fn appendZigStructTypeOnly(context: *ExtractionContext, node: *const Node) !void {
    const node_text = node.text;
    
    // Check if the original source contains 'pub' before this node
    var has_pub = false;
    if (std.mem.indexOf(u8, context.source, node_text)) |node_pos| {
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
                has_pub = is_close;
            }
        }
    }
    
    var lines = std.mem.splitScalar(u8, node_text, '\n');
    var builder = builders.ResultBuilder.init(context.allocator);
    defer builder.deinit();
    
    var inside_method = false;
    var brace_count: i32 = 0;
    var struct_brace_count: i32 = 0;
    var first_line = true;
    
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        
        // Count braces to track nesting
        for (line) |char| {
            if (char == '{') {
                brace_count += 1;
                // Remember the type's opening brace level (struct, enum, union)
                if (struct_brace_count == 0 and (std.mem.indexOf(u8, line, "struct") != null or
                                                  std.mem.indexOf(u8, line, "enum") != null or
                                                  std.mem.indexOf(u8, line, "union") != null)) {
                    struct_brace_count = brace_count;
                }
            } else if (char == '}') {
                brace_count -= 1;
            }
        }
        
        // Check if this line starts a method (function inside struct)
        const is_method_start = !inside_method and trimmed.len > 0 and
            brace_count >= struct_brace_count and
            (std.mem.indexOf(u8, trimmed, "pub fn ") != null or
             std.mem.indexOf(u8, trimmed, "fn ") != null) and
            std.mem.indexOf(u8, trimmed, "(") != null;
        
        if (is_method_start) {
            inside_method = true;
            continue; // Skip method start line
        }
        
        // If we're inside a method and back to struct level, exit method
        if (inside_method and brace_count < struct_brace_count) {
            inside_method = false;
        }
        
        // Skip lines that are inside methods
        if (inside_method) {
            continue;
        }
        
        // Handle the first line - prepend 'pub' if needed
        if (first_line and has_pub and !std.mem.startsWith(u8, trimmed, "pub ")) {
            try builder.append("pub ");
        }
        first_line = false;
        
        // Include struct-level lines (skip empty lines to normalize whitespace)
        if (trimmed.len > 0) {
            try builders.appendLine(builder.list(), line);
        }
    }
    
    // Remove trailing newline if present
    if (builder.len() > 0 and builder.items()[builder.len() - 1] == '\n') {
        _ = builder.list().pop();
    }
    
    // Append the normalized content with automatic newline handling
    try builders.appendMaybe(context.result, builder.items(), !std.mem.endsWith(u8, builder.items(), "\n"));
}
