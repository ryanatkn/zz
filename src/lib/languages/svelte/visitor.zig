const std = @import("std");
const Node = @import("../../tree_sitter/node.zig").Node;
const ExtractionContext = @import("../../tree_sitter/visitor.zig").ExtractionContext;
const builders = @import("../../text/builders.zig");

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

    // Signatures: Extract JS content from script elements only
    if (context.flags.signatures and !context.flags.structure and !context.flags.types) {
        if (std.mem.eql(u8, node_type, "script_element")) {
            // TODO: Extract only the JS content, not the script tags
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

        // Extract snippet blocks as structural elements
        if (isSvelteSnippet(node.text)) {
            try appendNormalizedSvelteSection(context, node);
            return false; // Skip children to avoid duplication
        }

        // For the template section, extract top-level elements
        if (std.mem.eql(u8, node_type, "element")) {
            // Extract all template elements for structure
            try appendNormalizedSvelteSection(context, node);
            return false; // Skip children to avoid duplication
        }
        
        // Also extract text nodes that might contain snippet blocks
        if (std.mem.eql(u8, node_type, "text") and isSvelteSnippet(node.text)) {
            try appendNormalizedSvelteSection(context, node);
            return false;
        }
        
        return true;
    }

    // Types: Extract JavaScript state declarations from script elements
    if (context.flags.types and !context.flags.structure and !context.flags.signatures) {
        if (std.mem.eql(u8, node_type, "script_element")) {
            // Extract JS state variables and type definitions from the script content
            try extractJSTypesFromScript(context, node);
            return false;
        }
        return true;
    }

    // Imports: Extract import statements from script elements
    if (context.flags.imports and !context.flags.structure and !context.flags.signatures and !context.flags.types) {
        if (std.mem.eql(u8, node_type, "script_element")) {
            // Extract only import statements from the JS content
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

/// Extract JavaScript types/state from script element (without script tags)
fn extractJSTypesFromScript(context: *ExtractionContext, script_node: *const Node) !void {
    // Extract content from raw_text children of script_element
    const child_count = script_node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        if (script_node.child(i, context.source)) |child| {
            if (std.mem.eql(u8, child.kind, "raw_text")) {
                // Extract JS state/types from the raw content (exclude function signatures)
                const js_content = child.text;
                try extractJSTypes(context, js_content);
                return;
            }
        }
    }

    // Fallback if no raw_text found
    try context.appendNode(script_node);
}

/// Extract import statements from script element (without script tags)
fn extractImportsFromScript(context: *ExtractionContext, script_node: *const Node) !void {
    // Extract content from raw_text children of script_element
    const child_count = script_node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        if (script_node.child(i, context.source)) |child| {
            if (std.mem.eql(u8, child.kind, "raw_text")) {
                // Extract JS imports from the raw content
                const js_content = child.text;
                try extractJSImports(context, js_content);
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
                // Extract JS signatures from the raw content
                const js_content = child.text;
                try extractJSSignatures(context, js_content);
                return;
            }
        }
    }

    // Fallback if no raw_text found
    try context.appendSignature(script_node);
}

/// Handle script_element nodes - extract JS content based on flags
fn handleScriptElement(context: *ExtractionContext, node: *const Node) !void {
    // For structure extraction, include the entire script element (but only if it has content)
    if (context.flags.structure) {
        // Check if this script element has actual content (raw_text nodes)
        if (hasNonEmptyContent(node, context.source)) {
            try context.appendNode(node);
        }
        return;
    }

    // For signatures/imports/types, we only want the JS content (no script tags)
    if (context.flags.signatures or context.flags.imports or context.flags.types) {
        var found_content = false;

        const child_count = node.childCount();
        var i: u32 = 0;
        while (i < child_count) : (i += 1) {
            if (node.child(i, context.source)) |child| {
                const child_type = child.kind;

                // Extract and parse the raw JS content (no tags)
                if (std.mem.eql(u8, child_type, "raw_text")) {
                    try extractJSContent(context, &child);
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

/// Extract JS content from raw_text node and filter based on flags
fn extractJSContent(context: *ExtractionContext, raw_text_node: *const Node) !void {
    // Get the raw JS source
    const js_source = raw_text_node.text;

    // For signatures extraction, we need to parse the JS and extract relevant parts
    if (context.flags.signatures) {
        try extractJSSignatures(context, js_source);
    }
    // For imports extraction, extract import statements
    else if (context.flags.imports) {
        try extractJSImports(context, js_source);
    }
    // For types extraction, extract type-related declarations
    else if (context.flags.types) {
        try extractJSTypes(context, js_source);
    }
    // Otherwise, include the full content
    else {
        try context.appendNode(raw_text_node);
    }
}

/// Extract JS signatures (functions, variables, runes)
fn extractJSSignatures(context: *ExtractionContext, js_source: []const u8) !void {
    var lines = std.mem.splitScalar(u8, js_source, '\n');
    var inside_multiline_expression = false;
    var brace_count: i32 = 0;
    var current_expression_start: ?[]const u8 = null;
    var expression_lines = std.ArrayList([]const u8).init(context.allocator);
    defer expression_lines.deinit();

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r\n");
        if (trimmed.len == 0 and !inside_multiline_expression) continue;

        // Handle multi-line expressions
        if (inside_multiline_expression) {
            try expression_lines.append(line);

            // Count braces to track when expression ends
            for (trimmed) |char| {
                if (char == '{') brace_count += 1;
                if (char == '}') brace_count -= 1;
            }

            // If we're back to the original brace level, expression is complete
            if (brace_count <= 0) {
                inside_multiline_expression = false;

                // Extract the complete expression (excluding closing braces)
                for (expression_lines.items) |expr_line| {
                    const expr_trimmed = std.mem.trim(u8, expr_line, " \t\r\n");
                    // Skip lines that are just closing braces/parentheses
                    if (expr_trimmed.len > 0 and !isClosingLine(expr_trimmed)) {
                        try context.appendText(expr_trimmed);
                    }
                }

                // Reset for next expression
                current_expression_start = null;
                expression_lines.clearRetainingCapacity();
                brace_count = 0;
            }
            continue;
        }

        // Check for multi-line expressions like $derived.by(() => { or $effect(() => {
        if ((std.mem.indexOf(u8, trimmed, "$derived.by") != null or
            std.mem.indexOf(u8, trimmed, "$effect") != null) and
            std.mem.indexOf(u8, trimmed, "{") != null)
        {
            // Count initial braces in this line
            for (trimmed) |char| {
                if (char == '{') brace_count += 1;
                if (char == '}') brace_count -= 1;
            }

            // If line doesn't close the expression, start multi-line tracking
            if (brace_count > 0) {
                inside_multiline_expression = true;
                current_expression_start = trimmed;
                try expression_lines.append(line);
                continue;
            }
            // If it's a single line expression, handle it normally below
        }

        // Check for single-line Svelte 5 runes
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

/// Extract JS imports
fn extractJSImports(context: *ExtractionContext, js_source: []const u8) !void {
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

/// Extract JS types and state declarations
fn extractJSTypes(context: *ExtractionContext, js_source: []const u8) !void {
    var lines = std.mem.splitScalar(u8, js_source, '\n');
    var inside_multiline_expression = false;
    var brace_count: i32 = 0;
    var expression_lines = std.ArrayList([]const u8).init(context.allocator);
    defer expression_lines.deinit();

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r\n");
        if (trimmed.len == 0 and !inside_multiline_expression) continue;

        // Handle multi-line expressions
        if (inside_multiline_expression) {
            try expression_lines.append(line);

            // Count braces to track when expression ends
            for (trimmed) |char| {
                if (char == '{') brace_count += 1;
                if (char == '}') brace_count -= 1;
            }

            // If we're back to the original brace level, expression is complete
            if (brace_count <= 0) {
                inside_multiline_expression = false;

                // Extract the complete expression (excluding closing braces)
                for (expression_lines.items) |expr_line| {
                    const expr_trimmed = std.mem.trim(u8, expr_line, " \t\r\n");
                    // Skip lines that are just closing braces/parentheses
                    if (expr_trimmed.len > 0 and !isClosingLine(expr_trimmed)) {
                        try context.appendText(expr_trimmed);
                    }
                }

                // Reset for next expression
                expression_lines.clearRetainingCapacity();
                brace_count = 0;
            }
            continue;
        }

        // Skip function declarations (these are signatures, not types)
        if (std.mem.startsWith(u8, trimmed, "function ") or
            std.mem.startsWith(u8, trimmed, "export function "))
        {
            continue;
        }

        // Check for multi-line expressions like $derived.by(() => { or $effect(() => {
        if ((std.mem.indexOf(u8, trimmed, "$derived.by") != null or
            std.mem.indexOf(u8, trimmed, "$effect") != null) and
            std.mem.indexOf(u8, trimmed, "{") != null)
        {
            // Count initial braces in this line
            for (trimmed) |char| {
                if (char == '{') brace_count += 1;
                if (char == '}') brace_count -= 1;
            }

            // If line doesn't close the expression, start multi-line tracking
            if (brace_count > 0) {
                inside_multiline_expression = true;
                try expression_lines.append(line);
                continue;
            }
            // If it's a single line expression, handle it normally below
        }

        // Variable declarations that define types/state
        if (std.mem.startsWith(u8, trimmed, "let ") or
            std.mem.startsWith(u8, trimmed, "const ") or
            std.mem.startsWith(u8, trimmed, "export let ") or
            std.mem.startsWith(u8, trimmed, "export const "))
        {
            try context.appendText(trimmed);
            continue;
        }

        // Check for single-line Svelte 5 state/derived declarations
        if (std.mem.indexOf(u8, trimmed, "$state") != null or
            std.mem.indexOf(u8, trimmed, "$derived") != null or
            std.mem.indexOf(u8, trimmed, "$effect") != null or
            std.mem.indexOf(u8, trimmed, "$props") != null or
            std.mem.indexOf(u8, trimmed, "$bindable") != null)
        {
            try context.appendText(trimmed);
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
    var builder = builders.ResultBuilder.init(context.allocator);
    defer builder.deinit();

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
        try builders.appendLine(builder.list(), line);
    }

    // Remove trailing newline if present
    if (builder.len() > 0 and builder.items()[builder.len() - 1] == '\n') {
        _ = builder.list().pop();
    }

    // Append the normalized content with automatic newline handling
    try builders.appendMaybe(context.result, builder.items(), !std.mem.endsWith(u8, builder.items(), "\n"));
}

/// Check if node text contains a Svelte snippet
fn isSvelteSnippet(text: []const u8) bool {
    return std.mem.indexOf(u8, text, "{#snippet") != null;
}

/// Check if a line contains only closing braces/parentheses (should be excluded from signatures)
fn isClosingLine(line: []const u8) bool {
    // Only exclude lines that are purely closing braces without meaningful context
    // Keep closing lines that complete signatures like "});", "};" etc.
    const pure_closing_patterns = [_][]const u8{ "}" };

    for (pure_closing_patterns) |pattern| {
        if (std.mem.eql(u8, line, pattern)) {
            return true;
        }
    }

    return false;
}
