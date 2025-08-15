const std = @import("std");
const Node = @import("../../tree_sitter/node.zig").Node;
const ExtractionContext = @import("../../tree_sitter/visitor.zig").ExtractionContext;
const builders = @import("../../text/builders.zig");

/// AST-based extraction visitor for CSS
/// Returns true to continue recursion, false to skip children
pub fn visitor(context: *ExtractionContext, node: *const Node) !bool {
    const node_type = node.kind;
    

    // Selectors (for signatures flag)
    if (context.flags.signatures and !context.flags.structure and !context.flags.types) {
        // Extract complete selectors from rule_set nodes
        if (std.mem.eql(u8, node_type, "rule_set")) {
            // Extract the selector part (everything before the opening brace)
            try context.appendSignature(node);
            return false; // Skip children - we've captured the selector
        }
        // Also extract @media rules for signatures
        if (std.mem.eql(u8, node_type, "media_statement")) {
            // Extract only the @media query part, not the content
            try context.appendSignature(node);
            return true; // Continue recursion to find selectors inside the media query
        }
    }

    // At-rules and imports
    if (context.flags.imports and !context.flags.structure and !context.flags.signatures and !context.flags.types) {
        if (std.mem.eql(u8, node_type, "import_statement") or
            std.mem.eql(u8, node_type, "at_rule") or
            std.mem.eql(u8, node_type, "namespace_statement") or
            std.mem.startsWith(u8, node_type, "import_"))
        {
            try context.appendNode(node);
            return false; // Skip children - we've captured the import
        }
    }

    // Structure elements - complete CSS structure
    if (context.flags.structure) {
        if (std.mem.eql(u8, node_type, "rule_set") or
            std.mem.eql(u8, node_type, "media_statement") or
            std.mem.eql(u8, node_type, "keyframes_statement") or
            std.mem.eql(u8, node_type, "supports_statement") or
            std.mem.eql(u8, node_type, "import_statement"))
        {
            // For media statements, normalize whitespace by removing extra blank lines
            if (std.mem.eql(u8, node_type, "media_statement")) {
                try appendNormalizedMediaStatement(context, node);
            } else {
                try context.appendNode(node);
            }
            // If this is a container element (media, keyframes, etc.), skip children
            // because we've already captured the complete structure including nested rules
            if (std.mem.eql(u8, node_type, "media_statement") or
                std.mem.eql(u8, node_type, "keyframes_statement") or
                std.mem.eql(u8, node_type, "supports_statement"))
            {
                return false; // Skip children to avoid double extraction
            }
        }
    }

    // Types - CSS rule sets, selectors, and imports 
    if (context.flags.types and !context.flags.structure and !context.flags.signatures) {
        if (std.mem.eql(u8, node_type, "rule_set") or
            std.mem.eql(u8, node_type, "import_statement") or
            std.mem.eql(u8, node_type, "media_statement") or
            std.mem.eql(u8, node_type, "keyframes_statement"))
        {
            try context.appendNode(node);
            return false; // Skip children for types
        }
    }

    // Comments for docs
    if (context.flags.docs) {
        if (std.mem.eql(u8, node_type, "comment")) {
            try context.appendNode(node);
            return false; // Skip children
        }
    }

    // Full source
    if (context.flags.full) {
        // For full extraction, only append the root stylesheet node to avoid duplication
        if (std.mem.eql(u8, node_type, "stylesheet")) {
            try context.result.appendSlice(node.text);
            return false; // Skip children - we already have full content
        }
    }
    
    // Default: continue recursion to child nodes
    return true;
}

/// Helper function to normalize media statement whitespace for structure extraction
fn appendNormalizedMediaStatement(context: *ExtractionContext, node: *const Node) !void {
    var lines = std.mem.splitScalar(u8, node.text, '\n');
    var builder = builders.ResultBuilder.init(context.allocator);
    defer builder.deinit();
    
    var inside_media_block = false;
    var brace_count: i32 = 0;
    
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        
        // Count braces to track nesting level
        for (line) |char| {
            if (char == '{') {
                brace_count += 1;
                if (brace_count == 1) {
                    inside_media_block = true;
                }
            } else if (char == '}') {
                brace_count -= 1;
                if (brace_count == 0) {
                    inside_media_block = false;
                }
            }
        }
        
        // Skip blank lines inside media block for structure extraction
        if (trimmed.len == 0 and inside_media_block) {
            // Skip this blank line to normalize media query structure
            continue;
        }
        
        // Append non-blank lines or blank lines outside media block
        try builders.appendLine(builder.list(), line);
    }
    
    // Remove trailing newline if present  
    if (builder.len() > 0 and builder.items()[builder.len() - 1] == '\n') {
        _ = builder.list().pop();
    }
    
    // Append the normalized content with automatic newline handling
    try builders.appendMaybe(context.result, builder.items(), !std.mem.endsWith(u8, builder.items(), "\n"));
}
