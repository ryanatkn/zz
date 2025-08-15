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
pub fn formatAst(
    allocator: std.mem.Allocator,
    node: ts.Node,
    source: []const u8,
    builder: *LineBuilder,
    options: FormatterOptions
) !void {
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

    // Get tag name to check if it's a void element
    var tag_name: []const u8 = "";
    if (node.childByFieldName("start_tag")) |start_tag| {
        if (start_tag.childByFieldName("name")) |name_node| {
            tag_name = getNodeText(name_node, source);
        }
    }

    const is_void = isVoidElement(tag_name);

    // Format start tag
    if (node.childByFieldName("start_tag")) |start_tag| {
        try builder.appendIndent();
        try appendNodeText(start_tag, source, builder);
        try builder.newline();

        // Only indent if not a void element
        if (!is_void) {
            builder.indent();
        }
    }

    // Format content (children)
    if (!is_void) {
        const child_count = node.childCount();
        var i: u32 = 0;
        while (i < child_count) : (i += 1) {
            if (node.child(i)) |child| {
                const child_type = child.kind();
                if (!std.mem.eql(u8, child_type, "start_tag") and !std.mem.eql(u8, child_type, "end_tag")) {
                    try formatHtmlNode(child, source, builder, depth + 1, options);
                }
            }
        }

        // Format end tag
        if (node.childByFieldName("end_tag")) |end_tag| {
            builder.dedent();
            try builder.appendIndent();
            try appendNodeText(end_tag, source, builder);
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
        try builder.appendIndent();
        try builder.append(trimmed);
        try builder.newline();
    }
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
    const void_elements = [_][]const u8{
        "area", "base", "br", "col", "embed", "hr", "img", "input",
        "link", "meta", "param", "source", "track", "wbr"
    };
    
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
