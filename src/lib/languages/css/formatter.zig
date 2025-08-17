const std = @import("std");
const ts = @import("tree-sitter");
const LineBuilder = @import("../../parsing/formatter.zig").LineBuilder;
const FormatterOptions = @import("../../parsing/formatter.zig").FormatterOptions;
const NodeUtils = @import("../../language/node_utils.zig").NodeUtils;

/// Format CSS using AST-based approach
pub fn formatAst(allocator: std.mem.Allocator, node: ts.Node, source: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
    _ = allocator;
    try formatCssNode(node, source, builder, 0, options);
}

/// CSS node formatting with controlled recursion
fn formatCssNode(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
    const node_type = node.kind();

    if (std.mem.eql(u8, node_type, "stylesheet")) {
        // Top-level stylesheet - format all children directly
        const child_count = node.childCount();
        var i: u32 = 0;
        var prev_child_type: []const u8 = "";

        while (i < child_count) : (i += 1) {
            if (node.child(i)) |child| {
                const child_type = child.kind();

                // Add appropriate spacing between items
                if (i > 0) {
                    // Add blank line between rules or after a rule before a comment
                    const prev_was_rule = std.mem.eql(u8, prev_child_type, "rule_set") or
                        std.mem.eql(u8, prev_child_type, "media_statement");
                    const curr_is_rule = std.mem.eql(u8, child_type, "rule_set") or
                        std.mem.eql(u8, child_type, "media_statement");
                    const curr_is_comment = std.mem.eql(u8, child_type, "comment");

                    if ((prev_was_rule and curr_is_rule) or (prev_was_rule and curr_is_comment)) {
                        try builder.newline();
                    }
                }

                // Format each child based on its type
                if (std.mem.eql(u8, child_type, "rule_set")) {
                    try formatRuleSet(child, source, builder, depth, options);
                } else if (std.mem.eql(u8, child_type, "media_statement")) {
                    try formatMediaStatement(child, source, builder, depth, options);
                } else if (std.mem.eql(u8, child_type, "at_rule")) {
                    try formatAtRule(child, source, builder, depth, options);
                } else if (std.mem.eql(u8, child_type, "import_statement")) {
                    try formatImportStatement(child, source, builder, depth, options);
                } else if (std.mem.eql(u8, child_type, "comment")) {
                    try formatCommentNoNewline(child, source, builder, depth, options);
                }

                // Add newline after each item
                if (i < child_count - 1) {
                    try builder.newline();
                }

                prev_child_type = child_type;
            }
        }
    } else if (std.mem.eql(u8, node_type, "rule_set")) {
        try formatRuleSet(node, source, builder, depth, options);
    } else if (std.mem.eql(u8, node_type, "media_statement")) {
        try formatMediaStatement(node, source, builder, depth, options);
    } else if (std.mem.eql(u8, node_type, "at_rule")) {
        try formatAtRule(node, source, builder, depth, options);
    } else if (std.mem.eql(u8, node_type, "import_statement")) {
        try formatImportStatement(node, source, builder, depth, options);
    } else if (std.mem.eql(u8, node_type, "comment")) {
        try formatComment(node, source, builder, depth, options);
    }
}

/// Format CSS rule set
fn formatRuleSet(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
    _ = depth;

    // Format selectors
    var selectors_found = false;
    const child_count = node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        if (node.child(i)) |child| {
            const child_type = child.kind();
            if (std.mem.eql(u8, child_type, "selectors")) {
                try builder.appendIndent();
                try NodeUtils.appendNodeText(child, source, builder);
                try builder.append(" {");
                try builder.newline();
                selectors_found = true;
                break;
            }
        }
    }

    if (!selectors_found) {
        // Fallback: if no selectors field found, this might be a malformed rule
        return;
    }

    // Format block content
    builder.indent();
    i = 0;
    while (i < child_count) : (i += 1) {
        if (node.child(i)) |child| {
            const child_type = child.kind();
            if (std.mem.eql(u8, child_type, "block")) {
                try formatBlock(child, source, builder, options);
                break;
            }
        }
    }
    builder.dedent();

    try builder.appendIndent();
    try builder.append("}");
}

/// Format CSS block
fn formatBlock(node: ts.Node, source: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
    const child_count = node.childCount();

    // First pass: collect all declarations to check if we should align
    var declarations = std.ArrayList(ts.Node).init(builder.allocator);
    defer declarations.deinit();

    var max_prop_len: usize = 0;
    var min_prop_len: usize = std.math.maxInt(usize);

    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        if (node.child(i)) |child| {
            const child_type = child.kind();
            if (std.mem.eql(u8, child_type, "declaration")) {
                try declarations.append(child);

                // Find property_name length
                const decl_child_count = child.childCount();
                var j: u32 = 0;
                while (j < decl_child_count) : (j += 1) {
                    if (child.child(j)) |decl_child| {
                        if (std.mem.eql(u8, decl_child.kind(), "property_name")) {
                            const prop_text = NodeUtils.getNodeText(decl_child, source);
                            max_prop_len = @max(max_prop_len, prop_text.len);
                            min_prop_len = @min(min_prop_len, prop_text.len);
                            break;
                        }
                    }
                }
            }
        }
    }

    // Reset min_prop_len if no declarations found
    if (min_prop_len == std.math.maxInt(usize)) {
        min_prop_len = 0;
    }

    // Determine if we should align properties
    // Align if we have 3+ properties with 2+ character difference
    // OR if we have 4+ properties with 4+ character difference
    const length_diff = max_prop_len - min_prop_len;
    const should_align = (declarations.items.len == 3 and length_diff >= 2) or
        (declarations.items.len >= 4 and length_diff >= 4);

    // Second pass: format all children
    i = 0;
    while (i < child_count) : (i += 1) {
        if (node.child(i)) |child| {
            const child_type = child.kind();

            if (std.mem.eql(u8, child_type, "declaration")) {
                // Check if there's an inline comment following this declaration
                var inline_comment: ?ts.Node = null;
                if (i + 1 < child_count) {
                    if (node.child(i + 1)) |next_child| {
                        if (std.mem.eql(u8, next_child.kind(), "comment")) {
                            // Check if comment is on the same line as declaration end
                            const decl_end = child.endByte();
                            const comment_start = next_child.startByte();

                            // Look for newline between declaration and comment
                            var has_newline = false;
                            if (decl_end < comment_start and comment_start <= source.len) {
                                const between = source[decl_end..comment_start];
                                for (between) |ch| {
                                    if (ch == '\n') {
                                        has_newline = true;
                                        break;
                                    }
                                }
                            }

                            if (!has_newline) {
                                inline_comment = next_child;
                                i += 1; // Skip the comment in next iteration
                            }
                        }
                    }
                }

                try formatDeclarationWithInlineComment(child, source, builder, options, should_align, max_prop_len, inline_comment, declarations.items.len);
            } else if (std.mem.eql(u8, child_type, "comment")) {
                try builder.appendIndent();
                try NodeUtils.appendNodeText(child, source, builder);
                try builder.newline();
            } else if (std.mem.eql(u8, child_type, "rule_set")) {
                // Nested rule - TODO: handle properly without circular reference
                // For now, just output as-is
                try builder.appendIndent();
                try NodeUtils.appendNodeText(child, source, builder);
                try builder.newline();
            }
        }
    }
}

/// Format CSS declaration with optional alignment and inline comment
fn formatDeclarationWithInlineComment(node: ts.Node, source: []const u8, builder: *LineBuilder, options: FormatterOptions, should_align: bool, max_prop_len: usize, inline_comment: ?ts.Node, declaration_count: usize) !void {
    _ = options;

    try builder.appendIndent();

    // Get property name
    var property_found = false;
    var property_len: usize = 0;
    const child_count = node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        if (node.child(i)) |child| {
            const child_type = child.kind();
            if (std.mem.eql(u8, child_type, "property_name")) {
                const prop_text = NodeUtils.getNodeText(child, source);
                property_len = prop_text.len;
                try NodeUtils.appendNodeText(child, source, builder);
                try builder.append(":");

                // Add alignment spaces if needed
                if (should_align) {
                    // Align values to start at the same column
                    // For 3 properties: add extra space for readability
                    // For 4+ properties: standard alignment
                    const extra_space: usize = if (declaration_count == 3) 1 else 0;
                    const alignment_spaces = @max(1, max_prop_len - property_len + extra_space);
                    var j: usize = 0;
                    while (j < alignment_spaces) : (j += 1) {
                        try builder.append(" ");
                    }
                } else {
                    try builder.append(" ");
                }

                property_found = true;
                break;
            }
        }
    }

    if (!property_found) {
        // If no property_name field, output the whole declaration
        try NodeUtils.appendNodeText(node, source, builder);
        if (!std.mem.endsWith(u8, NodeUtils.getNodeText(node, source), ";")) {
            try builder.append(";");
        }
        try builder.newline();
        return;
    }

    // Get all value nodes (everything after property_name except semicolon and important)
    var value_start_index = i + 1;
    var first_value = true;
    while (value_start_index < child_count) : (value_start_index += 1) {
        if (node.child(value_start_index)) |child| {
            const child_type = child.kind();
            const child_text = NodeUtils.getNodeText(child, source);

            // Skip comments within declaration (they're handled separately)
            if (std.mem.eql(u8, child_type, "comment")) {
                continue;
            }

            // Skip colons and semicolons
            if (std.mem.eql(u8, child_text, ":") or std.mem.eql(u8, child_text, ";")) {
                continue;
            }

            // Special handling for call_expression (like rgba)
            if (std.mem.eql(u8, child_type, "call_expression")) {
                if (!first_value) {
                    try builder.append(" ");
                }
                try formatCallExpression(child, source, builder);
                first_value = false;
            } else {
                // Add space between value parts
                if (!first_value) {
                    try builder.append(" ");
                }

                // Handle important flag
                if (std.mem.eql(u8, child_type, "important")) {
                    try builder.append("!");
                    try NodeUtils.appendNodeText(child, source, builder);
                } else {
                    try NodeUtils.appendNodeText(child, source, builder);
                }

                first_value = false;
            }
        }
    }

    try builder.append(";");

    // If there was an inline comment, add it after the semicolon
    if (inline_comment) |comment| {
        try builder.append(" ");
        try NodeUtils.appendNodeText(comment, source, builder);
    }

    try builder.newline();
}

/// Format CSS declaration with optional alignment
fn formatDeclarationWithAlignment(node: ts.Node, source: []const u8, builder: *LineBuilder, options: FormatterOptions, should_align: bool, max_prop_len: usize) !void {
    try formatDeclarationWithInlineComment(node, source, builder, options, should_align, max_prop_len, null, 0);
}

/// Format CSS declaration (simple version without alignment)
fn formatDeclaration(node: ts.Node, source: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
    try formatDeclarationWithAlignment(node, source, builder, options, false, 0);
}

/// Format call expression (like rgba()) with proper spacing
fn formatCallExpression(node: ts.Node, source: []const u8, builder: *LineBuilder) !void {
    // Get function name
    const child_count = node.childCount();
    var i: u32 = 0;

    // First, output the function name
    while (i < child_count) : (i += 1) {
        if (node.child(i)) |child| {
            const child_type = child.kind();
            if (std.mem.eql(u8, child_type, "function_name")) {
                try NodeUtils.appendNodeText(child, source, builder);
                try builder.append("(");
                break;
            }
        }
    }

    // Then format arguments
    i = 0;
    while (i < child_count) : (i += 1) {
        if (node.child(i)) |child| {
            const child_type = child.kind();
            if (std.mem.eql(u8, child_type, "arguments")) {
                // Format arguments with comma spacing
                const args_child_count = child.childCount();
                var j: u32 = 0;
                var first_arg = true;

                while (j < args_child_count) : (j += 1) {
                    if (child.child(j)) |arg| {
                        const arg_text = NodeUtils.getNodeText(arg, source);

                        // Skip parentheses and commas
                        if (std.mem.eql(u8, arg_text, "(") or
                            std.mem.eql(u8, arg_text, ")") or
                            std.mem.eql(u8, arg_text, ","))
                        {
                            continue;
                        }

                        if (!first_arg) {
                            try builder.append(", ");
                        }
                        try NodeUtils.appendNodeText(arg, source, builder);
                        first_arg = false;
                    }
                }
                break;
            }
        }
    }

    try builder.append(")");
}

/// Format media statement
fn formatMediaStatement(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
    try builder.appendIndent();
    try builder.append("@media ");

    // Format the media query
    const child_count = node.childCount();
    var i: u32 = 0;
    var query_found = false;

    while (i < child_count) : (i += 1) {
        if (node.child(i)) |child| {
            const child_type = child.kind();

            // Media queries can have various query types
            if (std.mem.eql(u8, child_type, "binary_query") or
                std.mem.eql(u8, child_type, "unary_query") or
                std.mem.eql(u8, child_type, "selector_query") or
                std.mem.eql(u8, child_type, "feature_query") or
                std.mem.eql(u8, child_type, "keyword_query") or
                std.mem.eql(u8, child_type, "parenthesized_query"))
            {
                if (query_found) {
                    try builder.append(", ");
                }
                try NodeUtils.appendNodeText(child, source, builder);
                query_found = true;
            } else if (std.mem.eql(u8, child_type, "block")) {
                // Found the block, format it
                try builder.append(" {");
                try builder.newline();

                builder.indent();
                try formatMediaBlock(child, source, builder, depth + 1, options);
                builder.dedent();

                try builder.appendIndent();
                try builder.append("}");
                break;
            }
        }
    }
}

/// Format block inside media query
fn formatMediaBlock(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
    const child_count = node.childCount();
    var i: u32 = 0;
    var prev_was_rule = false;

    while (i < child_count) : (i += 1) {
        if (node.child(i)) |child| {
            const child_type = child.kind();
            const is_rule = std.mem.eql(u8, child_type, "rule_set");

            // Add blank line between rules in media query
            if (prev_was_rule and is_rule) {
                try builder.appendIndent();
                try builder.newline();
            }

            if (std.mem.eql(u8, child_type, "rule_set")) {
                try formatRuleSet(child, source, builder, depth, options);
                if (i < child_count - 1) {
                    try builder.newline();
                }
            } else if (std.mem.eql(u8, child_type, "comment")) {
                try builder.appendIndent();
                try NodeUtils.appendNodeText(child, source, builder);
                try builder.newline();
            }

            prev_was_rule = is_rule;
        }
    }
}

/// Format at-rule (generic handler for @import, @charset, etc.)
fn formatAtRule(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
    _ = depth;
    _ = options;

    try builder.appendIndent();
    try NodeUtils.appendNodeText(node, source, builder);

    // Ensure at-rules end with semicolon
    const text = NodeUtils.getNodeText(node, source);
    if (!std.mem.endsWith(u8, text, ";")) {
        try builder.append(";");
    }
    try builder.newline();
}

/// Format import statement
fn formatImportStatement(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
    _ = depth;
    _ = options;

    try builder.appendIndent();
    try NodeUtils.appendNodeText(node, source, builder);

    // Ensure import ends with semicolon
    const text = NodeUtils.getNodeText(node, source);
    if (!std.mem.endsWith(u8, text, ";")) {
        try builder.append(";");
    }
    try builder.newline();
}

/// Format comment with newline
fn formatComment(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
    _ = depth;
    _ = options;

    try builder.appendIndent();
    try NodeUtils.appendNodeText(node, source, builder);
    try builder.newline();
}

/// Format comment without newline (for top-level comments)
fn formatCommentNoNewline(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
    _ = depth;
    _ = options;

    try builder.appendIndent();
    try NodeUtils.appendNodeText(node, source, builder);
}


/// Check if a node represents a CSS rule
pub fn isCssRule(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "rule_set") or
        std.mem.eql(u8, node_type, "at_rule") or
        std.mem.eql(u8, node_type, "declaration");
}

