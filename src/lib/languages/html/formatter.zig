const std = @import("std");
const ts = @import("tree-sitter");
const FormatterOptions = @import("../../parsing/formatter.zig").FormatterOptions;
const LineBuilder = @import("../../parsing/formatter.zig").LineBuilder;
const visitor_mod = @import("visitor.zig");

// Legacy format function for backwards compatibility - delegates to AST formatter
pub fn format(allocator: std.mem.Allocator, source: []const u8, options: FormatterOptions) ![]const u8 {
    // TODO: This will be removed once we fully transition to AST-only formatting
    // For now, return error to force use of AST formatter
    _ = allocator;
    _ = source;
    _ = options;
    return error.UnsupportedOperation;
}

// AST-based HTML formatting

/// Format HTML using AST-based approach
pub fn formatAst(allocator: std.mem.Allocator, node: ts.Node, source: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
    _ = allocator;
    try formatHtmlNode(node, source, builder, 0, options);
}

/// HTML node formatting with controlled recursion
fn formatHtmlNode(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) std.mem.Allocator.Error!void {
    const node_type = node.kind();

    if (std.mem.eql(u8, node_type, "element")) {
        try formatHtmlElement(node, source, builder, depth, options);
    } else if (std.mem.eql(u8, node_type, "comment")) {
        try formatHtmlComment(node, source, builder, depth, options);
    } else if (std.mem.eql(u8, node_type, "doctype")) {
        try formatHtmlDoctype(node, source, builder, depth, options);
    } else if (std.mem.eql(u8, node_type, "text")) {
        try formatHtmlText(node, source, builder, depth, options);
    } else if (std.mem.eql(u8, node_type, "document") or std.mem.eql(u8, node_type, "fragment")) {
        // For container nodes, recurse into children
        const child_count = node.childCount();
        var i: u32 = 0;
        while (i < child_count) : (i += 1) {
            if (node.child(i)) |child| {
                try formatHtmlNode(child, source, builder, depth, options);
            }
        }
    } else {
        // For unknown nodes, just append text without recursion
        try appendNodeText(node, source, builder);
    }
}

/// Format HTML element
fn formatHtmlElement(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) std.mem.Allocator.Error!void {
    const child_count = node.childCount();

    // Find start_tag and end_tag from children
    var start_tag: ?ts.Node = null;
    var end_tag: ?ts.Node = null;

    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        if (node.child(i)) |child| {
            const child_type = child.kind();
            if (std.mem.eql(u8, child_type, "start_tag")) {
                start_tag = child;
            } else if (std.mem.eql(u8, child_type, "end_tag")) {
                end_tag = child;
            }
        }
    }

    // Check content type
    const content_type = getContentType(node, source);

    // Format start tag
    if (start_tag) |start| {
        if (content_type == .text_only) {
            // For text_only, start tag goes on same line as content
            try builder.appendIndent();
            try appendNodeText(start, source, builder);
        } else {
            // For other types, start tag goes on separate line
            try builder.appendIndent();
            try appendNodeText(start, source, builder);
            try builder.newline();
        }
    }

    if (content_type == .text_only) {
        // Format as completely inline: <tag>text</tag>
        var j: u32 = 0;
        while (j < child_count) : (j += 1) {
            if (node.child(j)) |child| {
                const child_type = child.kind();
                if (std.mem.eql(u8, child_type, "text")) {
                    const text = getNodeText(child, source);
                    const trimmed = std.mem.trim(u8, text, " \t\r\n");
                    if (trimmed.len > 0) {
                        try builder.append(trimmed);
                    }
                }
            }
        }
    } else if (content_type == .mixed_inline) {
        // Format inline content on one line with proper indentation
        builder.indent();
        try builder.appendIndent();

        var j: u32 = 0;
        while (j < child_count) : (j += 1) {
            if (node.child(j)) |child| {
                const child_type = child.kind();
                if (std.mem.eql(u8, child_type, "text")) {
                    const text = getNodeText(child, source);
                    const trimmed = std.mem.trim(u8, text, " \t\r\n");
                    if (trimmed.len > 0) {
                        try builder.append(trimmed);
                        if (hasNonEndTagSibling(node, j)) {
                            try builder.append(" ");
                        }
                    }
                } else if (std.mem.eql(u8, child_type, "element")) {
                    try appendNodeText(child, source, builder);
                    if (hasNonEndTagSibling(node, j)) {
                        try builder.append(" ");
                    }
                }
            }
        }

        try builder.newline();
        builder.dedent();
    } else if (content_type == .block) {
        // Format block content with each child on separate lines
        builder.indent();
        var j: u32 = 0;
        while (j < child_count) : (j += 1) {
            if (node.child(j)) |child| {
                const child_type = child.kind();
                if (!std.mem.eql(u8, child_type, "start_tag") and !std.mem.eql(u8, child_type, "end_tag")) {
                    try formatHtmlNode(child, source, builder, depth + 1, options);
                }
            }
        }
        builder.dedent();
    }
    // For .empty content type, do nothing

    // Format end tag
    if (end_tag) |end| {
        if (content_type == .text_only) {
            // For text_only, end tag goes on same line
            try appendNodeText(end, source, builder);
            try builder.newline();
        } else {
            // For other types, end tag goes on separate line with proper indentation
            try builder.appendIndent();
            try appendNodeText(end, source, builder);
            try builder.newline();
        }
    }
}

/// Format HTML comment
fn formatHtmlComment(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
    _ = depth;
    _ = options;

    try builder.appendIndent();
    try appendNodeText(node, source, builder);
    try builder.newline();
}

/// Format HTML DOCTYPE
fn formatHtmlDoctype(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
    _ = depth;
    _ = options;

    try appendNodeText(node, source, builder);
    try builder.newline();
}

/// Format HTML text content
fn formatHtmlText(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
    _ = depth;
    _ = options;

    const text = getNodeText(node, source);
    const trimmed = std.mem.trim(u8, text, " \t\r\n");

    if (trimmed.len > 0) {
        // Text nodes should only be called in block context now
        // Add proper indentation and newlines for block text
        try builder.appendIndent();
        try builder.append(trimmed);
        try builder.newline();
    }
}

/// Content type for HTML elements
const ContentType = enum {
    text_only, // Only text content - format inline
    mixed_inline, // Text + elements - format on separate line but inline
    block, // Only elements - format as block
    empty, // No content
};

/// Determine the content type of an HTML element
fn getContentType(node: ts.Node, source: []const u8) ContentType {
    const child_count = node.childCount();
    var has_text = false;
    var has_element = false;

    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        if (node.child(i)) |child| {
            const child_type = child.kind();
            if (std.mem.eql(u8, child_type, "text")) {
                const text = getNodeText(child, source);
                if (std.mem.trim(u8, text, " \t\r\n").len > 0) {
                    has_text = true;
                }
            } else if (std.mem.eql(u8, child_type, "element")) {
                has_element = true;
            }
        }
    }

    if (has_text and has_element) {
        return .mixed_inline;
    } else if (has_text and !has_element) {
        return .text_only;
    } else if (!has_text and has_element) {
        return .block;
    } else {
        return .empty;
    }
}

/// Check if there's a non-end-tag sibling after the given index
fn hasNonEndTagSibling(node: ts.Node, current_index: u32) bool {
    const child_count = node.childCount();
    var i = current_index + 1;
    while (i < child_count) : (i += 1) {
        if (node.child(i)) |child| {
            const child_type = child.kind();
            if (!std.mem.eql(u8, child_type, "end_tag")) {
                return true;
            }
        }
    }
    return false;
}

/// Check if a node has a following sibling that would need spacing
fn hasFollowingSibling(node: ts.Node) bool {
    const parent = node.parent() orelse return false;
    const child_count = parent.childCount();

    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        if (parent.child(i)) |child| {
            if (child.eql(node)) {
                // Found this node, check if there's a next sibling
                if (i + 1 < child_count) {
                    if (parent.child(i + 1)) |next_sibling| {
                        const next_type = next_sibling.kind();
                        // Add space before elements but not before end tags
                        return std.mem.eql(u8, next_type, "element");
                    }
                }
                return false;
            }
        }
    }
    return false;
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

/// Check if a tag is a void element (self-closing)
fn isVoidElement(tag_name: []const u8) bool {
    const void_elements = [_][]const u8{ "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr" };

    for (void_elements) |void_tag| {
        if (std.mem.eql(u8, tag_name, void_tag)) {
            return true;
        }
    }
    return false;
}

/// Check if a node represents an HTML element
pub fn isHtmlElement(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "element") or
        std.mem.eql(u8, node_type, "start_tag") or
        std.mem.eql(u8, node_type, "end_tag") or
        std.mem.eql(u8, node_type, "self_closing_tag");
}
