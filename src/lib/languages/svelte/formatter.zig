const std = @import("std");
const ts = @import("tree-sitter");
const LineBuilder = @import("../../parsing/formatter.zig").LineBuilder;
const FormatterOptions = @import("../../parsing/formatter.zig").FormatterOptions;

/// Format Svelte using AST-based approach
pub fn formatAst(
    allocator: std.mem.Allocator,
    node: ts.Node,
    source: []const u8,
    builder: *LineBuilder,
    options: FormatterOptions
) !void {
    _ = allocator;
    try formatSvelteNode(node, source, builder, 0, options);
}

/// Svelte node formatting with section-aware handling
fn formatSvelteNode(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) std.mem.Allocator.Error!void {
    const node_type = node.kind();

    if (std.mem.eql(u8, node_type, "script_element")) {
        try formatSvelteScript(node, source, builder, depth, options);
    } else if (std.mem.eql(u8, node_type, "style_element")) {
        try formatSvelteStyle(node, source, builder, depth, options);
    } else if (std.mem.eql(u8, node_type, "reactive_statement")) {
        try formatSvelteReactive(node, source, builder, depth, options);
    } else if (std.mem.eql(u8, node_type, "document") or std.mem.eql(u8, node_type, "fragment")) {
        // For container nodes, recurse into children
        const child_count = node.childCount();
        var i: u32 = 0;
        while (i < child_count) : (i += 1) {
            if (node.child(i)) |child| {
                try formatSvelteNode(child, source, builder, depth, options);
            }
        }
    } else if (std.mem.eql(u8, node_type, "element") or std.mem.eql(u8, node_type, "start_tag") or std.mem.eql(u8, node_type, "end_tag")) {
        // Handle HTML elements - for structure extraction, we want to preserve these
        const element_text = getNodeText(node, source);
        var lines = std.mem.splitScalar(u8, element_text, '\n');
        while (lines.next()) |line| {
            const trimmed_line = std.mem.trim(u8, line, " \t\r");
            if (trimmed_line.len > 0) {
                try builder.append(trimmed_line);
                try builder.newline();
            }
        }
    } else {
        // For unknown nodes, just append text without recursion
        try appendNodeText(node, source, builder);
        // Add newline if the text doesn't end with one
        const text = getNodeText(node, source);
        if (text.len > 0 and text[text.len - 1] != '\n') {
            try builder.newline();
        }
    }
}

/// Format Svelte script section
fn formatSvelteScript(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) std.mem.Allocator.Error!void {
    _ = depth;
    _ = options;

    try builder.append("<script>");
    try builder.newline();

    // Extract script content and format it line by line
    const script_text = getNodeText(node, source);
    if (std.mem.indexOf(u8, script_text, ">")) |start_tag_end| {
        if (std.mem.lastIndexOf(u8, script_text, "</script>")) |end_tag_start| {
            const content = script_text[start_tag_end + 1 .. end_tag_start];
            const trimmed_content = std.mem.trim(u8, content, " \t\n\r");
            
            if (trimmed_content.len > 0) {
                // Split content into lines and indent each line
                var lines = std.mem.splitScalar(u8, trimmed_content, '\n');
                while (lines.next()) |line| {
                    const trimmed_line = std.mem.trimRight(u8, line, " \t\r");
                    if (trimmed_line.len > 0) {
                        try builder.append("    "); // 4-space indent
                        try builder.append(trimmed_line);
                    }
                    try builder.newline();
                }
            }
        }
    }

    try builder.append("</script>");
    try builder.newline();
}

/// Format Svelte style section
fn formatSvelteStyle(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) std.mem.Allocator.Error!void {
    _ = depth;
    _ = options;

    try builder.append("<style>");
    try builder.newline();

    // Extract style content and format it line by line
    const style_text = getNodeText(node, source);
    if (std.mem.indexOf(u8, style_text, ">")) |start_tag_end| {
        if (std.mem.lastIndexOf(u8, style_text, "</style>")) |end_tag_start| {
            const content = style_text[start_tag_end + 1 .. end_tag_start];
            const trimmed_content = std.mem.trim(u8, content, " \t\n\r");
            
            if (trimmed_content.len > 0) {
                // Split content into lines and indent each line
                var lines = std.mem.splitScalar(u8, trimmed_content, '\n');
                while (lines.next()) |line| {
                    const trimmed_line = std.mem.trimRight(u8, line, " \t\r");
                    if (trimmed_line.len > 0) {
                        try builder.append("    "); // 4-space indent
                        try builder.append(trimmed_line);
                    }
                    try builder.newline();
                }
            }
        }
    }

    try builder.append("</style>");
    try builder.newline();
}

/// Format Svelte reactive statement
fn formatSvelteReactive(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
    _ = depth;
    _ = options;

    try builder.appendIndent();
    try builder.append("$: ");
    try appendNodeText(node, source, builder);
    try builder.newline();
}

/// Helper function to get node text from source
fn getNodeText(node: ts.Node, source: []const u8) []const u8 {
    const start = node.startByte();
    const end = node.endByte();
    if (end <= source.len and start <= end) {
        return source[start..end];
    }
    return "";
}

/// Helper function to append node text to builder
fn appendNodeText(node: ts.Node, source: []const u8, builder: *LineBuilder) !void {
    const text = getNodeText(node, source);
    try builder.append(text);
}

/// Check if a node represents a Svelte section
pub fn isSvelteSection(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "script_element") or
        std.mem.eql(u8, node_type, "style_element") or
        std.mem.eql(u8, node_type, "template_element");
}

/// Check if a node represents a Svelte reactive statement
pub fn isSvelteReactive(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "reactive_statement") or
        std.mem.eql(u8, node_type, "labeled_statement"); // $: statements
}

// Legacy format function for backwards compatibility - delegates to AST formatter
pub fn format(allocator: std.mem.Allocator, source: []const u8, options: FormatterOptions) ![]const u8 {
    // TODO: This will be removed once we fully transition to AST-only formatting
    // For now, return error to force use of AST formatter
    _ = allocator;
    _ = source;
    _ = options;
    return error.UnsupportedOperation;
}
