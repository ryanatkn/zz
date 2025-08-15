const std = @import("std");
const Node = @import("../../tree_sitter/node.zig").Node;
const ExtractionContext = @import("../../tree_sitter/visitor.zig").ExtractionContext;

/// AST-based extraction visitor for Svelte with proper section handling
pub fn visitor(context: *ExtractionContext, node: *const Node) !void {
    const node_type = node.kind;

    // Full source - append everything
    if (context.flags.full) {
        // For full extraction, only append the root fragment node to avoid duplication
        if (std.mem.eql(u8, node_type, "fragment")) {
            try context.result.appendSlice(node.text);
        }
        return;
    }

    // Handle script elements - the main container for JavaScript content
    if (std.mem.eql(u8, node_type, "script_element")) {
        try handleScriptElement(context, node);
        return;
    }

    // Handle style elements - the main container for CSS content
    if (std.mem.eql(u8, node_type, "style_element")) {
        try handleStyleElement(context, node);
        return;
    }

    // Handle template/HTML elements for structure
    if (context.flags.structure) {
        if (std.mem.eql(u8, node_type, "element") or
            std.mem.eql(u8, node_type, "start_tag") or
            std.mem.eql(u8, node_type, "end_tag") or
            std.mem.eql(u8, node_type, "text") or
            std.mem.eql(u8, node_type, "if_statement") or
            std.mem.eql(u8, node_type, "each_statement") or
            std.mem.eql(u8, node_type, "await_statement") or
            std.mem.eql(u8, node_type, "snippet_statement"))
        {
            try context.appendNode(node);
            return;
        }
    }

    // Comments for docs
    if (context.flags.docs) {
        if (std.mem.eql(u8, node_type, "comment") or
            std.mem.eql(u8, node_type, "html_comment"))
        {
            try context.appendNode(node);
            return;
        }
    }
}

/// Handle script_element nodes - extract JavaScript content based on flags
fn handleScriptElement(context: *ExtractionContext, node: *const Node) !void {
    // For structure extraction, include the entire script element
    if (context.flags.structure) {
        try context.appendNode(node);
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
    // For structure extraction, include the entire style element
    if (context.flags.structure) {
        try context.appendNode(node);
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
            try context.appendText("\n");
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
            try context.appendText("\n");
            continue;
        }

        // Variable declarations
        if (std.mem.startsWith(u8, trimmed, "const ") or
            std.mem.startsWith(u8, trimmed, "let ") or
            std.mem.startsWith(u8, trimmed, "export let ") or
            std.mem.startsWith(u8, trimmed, "export const "))
        {
            try context.appendText(trimmed);
            try context.appendText("\n");
            continue;
        }

        // Svelte 4 reactive statements
        if (std.mem.startsWith(u8, trimmed, "$:")) {
            try context.appendText(trimmed);
            try context.appendText("\n");
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
            try context.appendText("\n");
            continue;
        }

        // Re-export statements (not variable exports)
        if (std.mem.startsWith(u8, trimmed, "export ") and
            !std.mem.startsWith(u8, trimmed, "export let ") and
            !std.mem.startsWith(u8, trimmed, "export const ") and
            !std.mem.startsWith(u8, trimmed, "export function "))
        {
            try context.appendText(trimmed);
            try context.appendText("\n");
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
