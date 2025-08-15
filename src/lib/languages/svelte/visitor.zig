const std = @import("std");
const Node = @import("../../tree_sitter/node.zig").Node;
const ExtractionContext = @import("../../tree_sitter/visitor.zig").ExtractionContext;

/// AST-based extraction visitor for Svelte with proper section handling
/// Returns true to continue recursion, false to skip children  
pub fn visitor(context: *ExtractionContext, node: *const Node) !bool {
    const node_type = node.kind;

    // Full source - append everything
    if (context.flags.full) {
        // For full extraction, only append the root fragment node to avoid duplication
        if (std.mem.eql(u8, node_type, "fragment")) {
            try context.result.appendSlice(node.text);
            return false; // Skip children - we already have full content
        }
        return true; // Continue recursion for other nodes
    }

    // Signatures: Extract JavaScript content from script elements only
    if (context.flags.signatures and !context.flags.structure and !context.flags.types) {
        if (std.mem.eql(u8, node_type, "script_element")) {
            // TODO: Extract only the JavaScript content, not the script tags
            // For now, extract signatures from the script content
            try extractSignaturesFromScript(context, node);
            return false;
        }
        return true;
    }

    // Structure: Extract complete component sections
    if (context.flags.structure) {
        if (std.mem.eql(u8, node_type, "script_element") or
            std.mem.eql(u8, node_type, "style_element"))
        {
            // For script and style, normalize whitespace to remove extra blank lines
            try appendNormalizedSvelteSection(context, node);
            return false; // Skip children to avoid duplication
        }
        
        // For the template section, only extract top-level elements
        if (std.mem.eql(u8, node_type, "element")) {
            // Check if this is a top-level template element by looking at parent depth
            // Only extract elements that are direct children of the fragment
            try context.appendNode(node);
            return false; // Skip children to avoid duplication
        }
        return true;
    }

    // Types: Extract CSS from style elements
    if (context.flags.types and !context.flags.structure and !context.flags.signatures) {
        if (std.mem.eql(u8, node_type, "style_element")) {
            // TODO: Extract only CSS content, not style tags
            try context.appendNode(node);
            return false;
        }
        return true;
    }

    // Imports: Extract import statements from script elements
    if (context.flags.imports and !context.flags.structure and !context.flags.signatures and !context.flags.types) {
        if (std.mem.eql(u8, node_type, "script_element")) {
            // Extract only import statements from the JavaScript content
            try extractImportsFromScript(context, node);
            return false;
        }
        return true;
    }

    // Comments for docs
    if (context.flags.docs and !context.flags.structure and !context.flags.signatures and !context.flags.types) {
        if (std.mem.eql(u8, node_type, "comment") or
            std.mem.eql(u8, node_type, "html_comment"))
        {
            try context.appendNode(node);
            return false; // Skip children
        }
    }
    
    // Default: continue recursion to child nodes
    return true;
}

/// Extract import statements from script element (without script tags)
fn extractImportsFromScript(context: *ExtractionContext, script_node: *const Node) !void {
    // Extract content from raw_text children of script_element
    const child_count = script_node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        if (script_node.child(i, context.source)) |child| {
            if (std.mem.eql(u8, child.kind, "raw_text")) {
                // Extract JavaScript imports from the raw content
                const js_content = child.text;
                try extractJavaScriptImports(context, js_content);
                return;
            }
        }
    }
    
    // Fallback if no raw_text found
    try context.appendNode(script_node);
}

/// Extract function signatures from script element (without script tags)
fn extractSignaturesFromScript(context: *ExtractionContext, script_node: *const Node) !void {
    // Extract content from raw_text children of script_element
    const child_count = script_node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        if (script_node.child(i, context.source)) |child| {
            if (std.mem.eql(u8, child.kind, "raw_text")) {
                // Extract JavaScript signatures from the raw content
                const js_content = child.text;
                try extractJavaScriptSignatures(context, js_content);
                return;
            }
        }
    }
    
    // Fallback if no raw_text found
    try context.appendSignature(script_node);
}


/// Handle script_element nodes - extract JavaScript content based on flags
fn handleScriptElement(context: *ExtractionContext, node: *const Node) !void {
    // For structure extraction, include the entire script element (but only if it has content)
    if (context.flags.structure) {
        // Check if this script element has actual content (raw_text nodes)
        if (hasNonEmptyContent(node, context.source)) {
            try context.appendNode(node);
        }
        return;
    }

    // For signatures/imports/types, we only want the JavaScript content (no script tags)
    if (context.flags.signatures or context.flags.imports or context.flags.types) {
        var found_content = false;

        const child_count = node.childCount();
        var i: u32 = 0;
        while (i < child_count) : (i += 1) {
            if (node.child(i, context.source)) |child| {
                const child_type = child.kind;

                // Extract and parse the raw JavaScript content (no tags)
                if (std.mem.eql(u8, child_type, "raw_text")) {
                    try extractJavaScriptContent(context, &child);
                    found_content = true;
                }
            }
        }

        // If we didn't find expected content, fall back to full node
        if (!found_content) {
            try context.appendNode(node);
        }
    }
}

/// Handle style_element nodes - extract CSS content based on flags
fn handleStyleElement(context: *ExtractionContext, node: *const Node) !void {
    // For structure extraction, include the entire style element (but only if it has content)
    if (context.flags.structure) {
        // Check if this style element has actual content (raw_text nodes)
        if (hasNonEmptyContent(node, context.source)) {
            try context.appendNode(node);
        }
        return;
    }

    // For types flag, we want CSS content (no style tags for consistency with signatures)
    if (context.flags.types) {
        var found_content = false;

        const child_count = node.childCount();
        var i: u32 = 0;
        while (i < child_count) : (i += 1) {
            if (node.child(i, context.source)) |child| {
                const child_type = child.kind;

                // Extract the raw CSS content (no tags)
                if (std.mem.eql(u8, child_type, "raw_text")) {
                    try context.appendNode(&child);
                    found_content = true;
                }
            }
        }

        // If we didn't find expected content, fall back to full node
        if (!found_content) {
            try context.appendNode(node);
        }
    }
}

/// Extract JavaScript content from raw_text node and filter based on flags
fn extractJavaScriptContent(context: *ExtractionContext, raw_text_node: *const Node) !void {
    // Get the raw JavaScript source
    const js_source = raw_text_node.text;

    // For signatures extraction, we need to parse the JavaScript and extract relevant parts
    if (context.flags.signatures) {
        try extractJavaScriptSignatures(context, js_source);
    }
    // For imports extraction, extract import statements
    else if (context.flags.imports) {
        try extractJavaScriptImports(context, js_source);
    }
    // For types extraction, extract type-related declarations
    else if (context.flags.types) {
        try extractJavaScriptTypes(context, js_source);
    }
    // Otherwise, include the full content
    else {
        try context.appendNode(raw_text_node);
    }
}

/// Extract JavaScript signatures (functions, variables, runes)
fn extractJavaScriptSignatures(context: *ExtractionContext, js_source: []const u8) !void {
    var lines = std.mem.splitScalar(u8, js_source, '\n');

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r\n");
        if (trimmed.len == 0) continue;

        // Check for Svelte 5 runes
        if (std.mem.indexOf(u8, trimmed, "$state") != null or
            std.mem.indexOf(u8, trimmed, "$derived") != null or
            std.mem.indexOf(u8, trimmed, "$effect") != null or
            std.mem.indexOf(u8, trimmed, "$props") != null or
            std.mem.indexOf(u8, trimmed, "$bindable") != null)
        {
            try context.appendText(trimmed);
            continue;
        }

        // Function signatures
        if (std.mem.startsWith(u8, trimmed, "function ") or
            std.mem.startsWith(u8, trimmed, "export function "))
        {
            // Extract just the signature part (remove opening brace)
            var signature = trimmed;
            if (std.mem.endsWith(u8, signature, " {")) {
                signature = signature[0 .. signature.len - 2];
            } else if (std.mem.endsWith(u8, signature, "{")) {
                signature = std.mem.trimRight(u8, signature[0 .. signature.len - 1], " \t");
            }
            try context.appendText(signature);
            continue;
        }

        // Variable declarations
        if (std.mem.startsWith(u8, trimmed, "const ") or
            std.mem.startsWith(u8, trimmed, "let ") or
            std.mem.startsWith(u8, trimmed, "export let ") or
            std.mem.startsWith(u8, trimmed, "export const "))
        {
            try context.appendText(trimmed);
            continue;
        }

        // Svelte 4 reactive statements
        if (std.mem.startsWith(u8, trimmed, "$:")) {
            try context.appendText(trimmed);
            continue;
        }
    }
}

/// Extract JavaScript imports
fn extractJavaScriptImports(context: *ExtractionContext, js_source: []const u8) !void {
    var lines = std.mem.splitScalar(u8, js_source, '\n');

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r\n");
        if (trimmed.len == 0) continue;

        // Import statements
        if (std.mem.startsWith(u8, trimmed, "import ")) {
            try context.appendText(trimmed);
            continue;
        }

        // Re-export statements (not variable exports)
        if (std.mem.startsWith(u8, trimmed, "export ") and
            !std.mem.startsWith(u8, trimmed, "export let ") and
            !std.mem.startsWith(u8, trimmed, "export const ") and
            !std.mem.startsWith(u8, trimmed, "export function "))
        {
            try context.appendText(trimmed);
            continue;
        }
    }
}

/// Extract JavaScript types and state declarations
fn extractJavaScriptTypes(context: *ExtractionContext, js_source: []const u8) !void {
    var lines = std.mem.splitScalar(u8, js_source, '\n');

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r\n");
        if (trimmed.len == 0) continue;

        // Variable declarations that define types/state
        if (std.mem.startsWith(u8, trimmed, "let ") or
            std.mem.startsWith(u8, trimmed, "const ") or
            std.mem.startsWith(u8, trimmed, "export let ") or
            std.mem.startsWith(u8, trimmed, "export const "))
        {
            try context.appendText(trimmed);
            try context.appendText("\n");
            continue;
        }

        // Svelte 5 state declarations
        if (std.mem.indexOf(u8, trimmed, "$state") != null or
            std.mem.indexOf(u8, trimmed, "$derived") != null)
        {
            try context.appendText(trimmed);
            try context.appendText("\n");
            continue;
        }
    }
}

/// Check if a script or style element has non-empty content
fn hasNonEmptyContent(node: *const Node, source: []const u8) bool {
    const child_count = node.childCount();
    var i: u32 = 0;
    
    while (i < child_count) : (i += 1) {
        if (node.child(i, source)) |child| {
            const child_type = child.kind;
            
            // Look for raw_text nodes with actual content
            if (std.mem.eql(u8, child_type, "raw_text")) {
                const content = std.mem.trim(u8, child.text, " \t\r\n");
                if (content.len > 0) {
                    return true;
                }
            }
        }
    }
    
    return false;
}

/// Helper function to normalize Svelte section whitespace for structure extraction
/// Removes blank lines within script and style sections to match test expectations
fn appendNormalizedSvelteSection(context: *ExtractionContext, node: *const Node) !void {
    var lines = std.mem.splitScalar(u8, node.text, '\n');
    var normalized = std.ArrayList(u8).init(context.allocator);
    defer normalized.deinit();
    
    var inside_content_block = false;
    
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        
        // Detect when we're inside the content block (after opening tag)
        if (std.mem.indexOf(u8, trimmed, ">") != null and !inside_content_block) {
            inside_content_block = true;
        }
        if (std.mem.indexOf(u8, trimmed, "</") != null and inside_content_block) {
            inside_content_block = false;
        }
        
        // Skip all blank lines inside content blocks for structure extraction
        if (trimmed.len == 0 and inside_content_block) {
            // Skip blank lines inside script/style content
            continue;
        }
        
        // Append all other lines
        try normalized.appendSlice(line);
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
