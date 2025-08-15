const std = @import("std");
const ts = @import("tree-sitter");
const LineBuilder = @import("../../parsing/formatter.zig").LineBuilder;
const FormatterOptions = @import("../../parsing/formatter.zig").FormatterOptions;

/// Format CSS using AST-based approach
pub fn formatAst(
    allocator: std.mem.Allocator,
    node: ts.Node,
    source: []const u8,
    builder: *LineBuilder,
    options: FormatterOptions
) !void {
    _ = allocator;
    try formatCssNode(node, source, builder, 0, options);
}

/// CSS node formatting with controlled recursion
fn formatCssNode(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
    const node_type = node.kind();


    if (std.mem.eql(u8, node_type, "rule_set")) {
        try formatCssRule(node, source, builder, depth, options);
    } else if (std.mem.eql(u8, node_type, "at_rule")) {
        try formatCssAtRule(node, source, builder, depth, options);
    } else if (std.mem.eql(u8, node_type, "declaration")) {
        try formatCssDeclaration(node, source, builder, depth, options);
    } else if (std.mem.eql(u8, node_type, "comment")) {
        try formatCssComment(node, source, builder, depth, options);
    } else if (std.mem.eql(u8, node_type, "stylesheet") or std.mem.eql(u8, node_type, "block")) {
        // For container nodes, recurse into children and add spacing between rules
        const child_count = node.childCount();
        var rule_count: u32 = 0;
        var i: u32 = 0;
        while (i < child_count) : (i += 1) {
            if (node.child(i)) |child| {
                const child_type = child.kind();
                if (std.mem.eql(u8, child_type, "rule_set")) {
                    if (rule_count > 0) {
                        try builder.newline(); // Add blank line between rules
                    }
                    try formatCssNode(child, source, builder, depth, options);
                    rule_count += 1;
                } else {
                    try formatCssNode(child, source, builder, depth, options);
                }
            }
        }
    } else {
        // For unknown nodes, just append text without recursion
        try appendNodeText(node, source, builder);
    }
}

/// Format CSS rule set
fn formatCssRule(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {


    // Format selector
    if (node.childByFieldName("selectors")) |selector_node| {
        try builder.appendIndent();
        const selector_text = getNodeText(selector_node, source);
        try builder.append(selector_text);
        try builder.append(" {");
        try builder.newline();
    } else {
        // Fallback: try to find selector in rule
        const rule_text = getNodeText(node, source);
        
        // Manual selector extraction as fallback
        if (std.mem.indexOf(u8, rule_text, "{")) |brace_pos| {
            const selector_part = std.mem.trim(u8, rule_text[0..brace_pos], " \t\n\r");
            try builder.appendIndent();
            try builder.append(selector_part);
            try builder.append(" {");
            try builder.newline();
        }
    }

    // Format declarations with indentation
    builder.indent();
    if (node.childByFieldName("block")) |block_node| {
        // Process declarations directly instead of using formatNodeRecursive to avoid double-processing
        const child_count = block_node.childCount();
        var i: u32 = 0;
        while (i < child_count) : (i += 1) {
            if (block_node.child(i)) |child| {
                const child_type = child.kind();
                if (std.mem.eql(u8, child_type, "declaration")) {
                    try formatCssDeclaration(child, source, builder, depth, options);
                }
                // Skip other nodes like braces, whitespace
            }
        }
    } else {
        // Fallback: extract declarations from rule text
        const rule_text = getNodeText(node, source);
        if (std.mem.indexOf(u8, rule_text, "{")) |start| {
            if (std.mem.lastIndexOf(u8, rule_text, "}")) |end| {
                const declarations_text = rule_text[start + 1 .. end];
                var iter = std.mem.splitScalar(u8, declarations_text, ';');
                while (iter.next()) |decl| {
                    const trimmed = std.mem.trim(u8, decl, " \t\n\r");
                    if (trimmed.len > 0) {
                        try builder.appendIndent();
                        if (std.mem.indexOf(u8, trimmed, ":")) |colon_pos| {
                            const prop = std.mem.trim(u8, trimmed[0..colon_pos], " \t");
                            const val = std.mem.trim(u8, trimmed[colon_pos + 1 ..], " \t");
                            try builder.append(prop);
                            try builder.append(": ");
                            try builder.append(val);
                            try builder.append(";");
                        } else {
                            try builder.append(trimmed);
                            if (!std.mem.endsWith(u8, trimmed, ";")) {
                                try builder.append(";");
                            }
                        }
                        try builder.newline();
                    }
                }
            }
        }
    }
    builder.dedent();

    try builder.appendIndent();
    try builder.append("}");
    try builder.newline();
}

/// Format CSS at-rule
fn formatCssAtRule(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
    _ = depth;
    _ = options;

    try builder.appendIndent();
    try appendNodeText(node, source, builder);
    try builder.newline();
}

/// Format CSS declaration
fn formatCssDeclaration(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
    _ = depth;
    _ = options;

    try builder.appendIndent();

    if (node.childByFieldName("property")) |prop_node| {
        const prop_text = getNodeText(prop_node, source);
        try builder.append(prop_text);
        try builder.append(": ");

        if (node.childByFieldName("value")) |value_node| {
            const value_text = getNodeText(value_node, source);
            try builder.append(value_text);
        }

        try builder.append(";");
        try builder.newline();
    } else {
        try appendNodeText(node, source, builder);
        try builder.newline();
    }
}

/// Format CSS comment
fn formatCssComment(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
    _ = depth;
    _ = options;

    try builder.appendIndent();
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

/// Check if a node represents a CSS rule
pub fn isCssRule(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "rule_set") or
        std.mem.eql(u8, node_type, "at_rule") or
        std.mem.eql(u8, node_type, "declaration");
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