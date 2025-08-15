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
    } else if (std.mem.eql(u8, node_type, "self_closing_tag")) {
        try formatSelfClosingTag(node, source, builder, depth, options);
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
        // For unknown nodes, append both node type and text for debugging
        try builder.append("<!-- UNKNOWN: ");
        try builder.append(node_type);
        try builder.append(" -->");
        try appendNodeText(node, source, builder);
    }
}

/// Format start tag conditionally with attribute line wrapping only when needed
fn formatStartTagConditionally(start_tag: ts.Node, source: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
    const tag_text = getNodeText(start_tag, source);
    
    // Only apply attribute wrapping for specific tags that commonly have many attributes
    const needs_attribute_wrapping = shouldWrapAttributes(tag_text, options);
    
    if (needs_attribute_wrapping) {
        try formatStartTagWithWrapping(start_tag, source, builder, options);
    } else {
        // Use original formatting for most tags
        try appendNodeText(start_tag, source, builder);
    }
}

/// Check if a start tag should have its attributes wrapped
fn shouldWrapAttributes(tag_text: []const u8, options: FormatterOptions) bool {
    // Only wrap attributes if all conditions are met:
    // 1. Tag exceeds line width
    // 2. Tag has multiple attributes
    // 3. Tag is a type that commonly has many attributes (form elements, etc.)
    if (tag_text.len <= options.line_width) return false;
    if (!hasMultipleAttributes(tag_text)) return false;
    
    // Check if it's a tag type that commonly benefits from attribute wrapping
    return std.mem.indexOf(u8, tag_text, "<input ") != null or
           std.mem.indexOf(u8, tag_text, "<textarea ") != null or
           std.mem.indexOf(u8, tag_text, "<select ") != null or
           std.mem.indexOf(u8, tag_text, "<button ") != null;
}

/// Format start tag with attribute line wrapping
fn formatStartTagWithWrapping(start_tag: ts.Node, source: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
    const tag_text = getNodeText(start_tag, source);
    
    // Only apply attribute wrapping if the tag has multiple attributes and exceeds line width
    const should_wrap_attributes = tag_text.len > options.line_width and hasMultipleAttributes(tag_text);
    
    if (!should_wrap_attributes) {
        // Short enough to fit on one line or doesn't have multiple attributes - use original formatting
        try builder.append(tag_text);
        return;
    }
    
    // Parse the start tag to extract tag name and attributes
    // Format: <tagname attr1="value1" attr2="value2" ...>
    
    // Find tag name (everything after < until first space or >)
    var i: usize = 1; // Skip opening <
    while (i < tag_text.len and tag_text[i] != ' ' and tag_text[i] != '>') : (i += 1) {}
    
    const tag_name = tag_text[1..i];
    
    // Output opening tag name
    try builder.append("<");
    try builder.append(tag_name);
    
    if (i >= tag_text.len or tag_text[i] == '>') {
        // No attributes, just close the tag
        try builder.append(">");
        return;
    }
    
    // Parse and format attributes
    try builder.append(" ");
    try builder.newline();
    
    // Increase indentation for all attributes
    builder.indent();
    
    // Count total attributes first
    var total_attrs: u32 = 0;
    var count_pos = i;
    while (count_pos < tag_text.len) {
        // Skip whitespace
        while (count_pos < tag_text.len and (tag_text[count_pos] == ' ' or tag_text[count_pos] == '\t' or tag_text[count_pos] == '\n' or tag_text[count_pos] == '\r')) : (count_pos += 1) {}
        if (count_pos >= tag_text.len or tag_text[count_pos] == '>') break;
        
        total_attrs += 1;
        
        // Skip this attribute
        var in_quotes = false;
        var quote_char: u8 = 0;
        while (count_pos < tag_text.len) {
            const c = tag_text[count_pos];
            if (!in_quotes) {
                if (c == '"' or c == '\'') {
                    in_quotes = true;
                    quote_char = c;
                } else if (c == ' ' or c == '\t' or c == '\n' or c == '\r' or c == '>') {
                    break;
                }
            } else {
                if (c == quote_char) {
                    in_quotes = false;
                }
            }
            count_pos += 1;
        }
    }
    
    // Now parse and output attributes with proper trailing space handling
    var attr_count: u32 = 0;
    var attr_start = i;
    while (attr_start < tag_text.len) {
        // Skip whitespace
        while (attr_start < tag_text.len and (tag_text[attr_start] == ' ' or tag_text[attr_start] == '\t' or tag_text[attr_start] == '\n' or tag_text[attr_start] == '\r')) : (attr_start += 1) {}
        
        if (attr_start >= tag_text.len or tag_text[attr_start] == '>') break;
        
        // Find end of this attribute
        var attr_end = attr_start;
        var in_quotes = false;
        var quote_char: u8 = 0;
        
        while (attr_end < tag_text.len) {
            const c = tag_text[attr_end];
            if (!in_quotes) {
                if (c == '"' or c == '\'') {
                    in_quotes = true;
                    quote_char = c;
                } else if (c == ' ' or c == '\t' or c == '\n' or c == '\r' or c == '>') {
                    break;
                }
            } else {
                if (c == quote_char) {
                    in_quotes = false;
                }
            }
            attr_end += 1;
        }
        
        // Extract and output the attribute
        if (attr_end > attr_start) {
            const attribute = std.mem.trim(u8, tag_text[attr_start..attr_end], " \t\n\r");
            if (attribute.len > 0) {
                attr_count += 1;
                try builder.appendIndent();
                try builder.append(attribute);
                
                // Add trailing space for all attributes except the last one
                if (attr_count < total_attrs) {
                    try builder.append(" ");
                }
                
                try builder.newline();
            }
        }
        
        attr_start = attr_end;
    }
    
    // Restore indentation level and output closing >
    builder.dedent();
    try builder.appendIndent();
    try builder.append(">");
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
            try formatStartTagConditionally(start, source, builder, options);
        } else {
            // For other types, start tag goes on separate line
            try builder.appendIndent();
            try formatStartTagConditionally(start, source, builder, options);
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
                    if (shouldAddSpaceAfterElement(node, j, source)) {
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

/// Format self-closing HTML tag (like <img />, <hr />)
fn formatSelfClosingTag(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
    _ = depth;
    
    try builder.appendIndent();
    try formatStartTagConditionally(node, source, builder, options);
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

/// Check if we should add a space after an element based on the next sibling
fn shouldAddSpaceAfterElement(node: ts.Node, current_index: u32, source: []const u8) bool {
    const child_count = node.childCount();
    var i = current_index + 1;
    while (i < child_count) : (i += 1) {
        if (node.child(i)) |child| {
            const child_type = child.kind();
            if (std.mem.eql(u8, child_type, "end_tag")) {
                continue; // Skip end tags
            }
            
            if (std.mem.eql(u8, child_type, "text")) {
                // Check if the text starts with punctuation - if so, don't add space
                const text = getNodeText(child, source);
                const trimmed = std.mem.trim(u8, text, " \t\r\n");
                if (trimmed.len > 0) {
                    const first_char = trimmed[0];
                    // Don't add space before punctuation
                    if (first_char == '.' or first_char == ',' or first_char == ';' or 
                        first_char == ':' or first_char == '!' or first_char == '?' or
                        first_char == ')' or first_char == ']' or first_char == '}') {
                        return false;
                    }
                }
                return true; // Add space before other text
            } else if (std.mem.eql(u8, child_type, "element")) {
                return true; // Add space before other elements
            }
        }
    }
    return false; // No relevant siblings found
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

/// Check if a tag has multiple attributes
fn hasMultipleAttributes(tag_text: []const u8) bool {
    var attr_count: u32 = 0;
    var i: usize = 0;
    
    // Skip the tag name
    while (i < tag_text.len and tag_text[i] != ' ') : (i += 1) {}
    
    // Count attributes (space-separated key=value or boolean attributes)
    while (i < tag_text.len) {
        // Skip whitespace
        while (i < tag_text.len and (tag_text[i] == ' ' or tag_text[i] == '\t' or tag_text[i] == '\n' or tag_text[i] == '\r')) : (i += 1) {}
        
        if (i >= tag_text.len or tag_text[i] == '>') break;
        
        // Found start of an attribute
        attr_count += 1;
        if (attr_count >= 2) return true; // Early exit for performance
        
        // Skip to end of this attribute
        var in_quotes = false;
        var quote_char: u8 = 0;
        
        while (i < tag_text.len) {
            const c = tag_text[i];
            if (!in_quotes) {
                if (c == '"' or c == '\'') {
                    in_quotes = true;
                    quote_char = c;
                } else if (c == ' ' or c == '\t' or c == '\n' or c == '\r' or c == '>') {
                    break;
                }
            } else {
                if (c == quote_char) {
                    in_quotes = false;
                }
            }
            i += 1;
        }
    }
    
    return attr_count >= 2;
}

/// Check if a node represents an HTML element
pub fn isHtmlElement(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "element") or
        std.mem.eql(u8, node_type, "start_tag") or
        std.mem.eql(u8, node_type, "end_tag") or
        std.mem.eql(u8, node_type, "self_closing_tag");
}
