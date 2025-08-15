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

    if (std.mem.eql(u8, node_type, "stylesheet")) {
        // Top-level stylesheet - format all children directly
        const child_count = node.childCount();
        var i: u32 = 0;
        var prev_was_rule = false;
        
        while (i < child_count) : (i += 1) {
            if (node.child(i)) |child| {
                const child_type = child.kind();
                const is_rule = std.mem.eql(u8, child_type, "rule_set") or 
                               std.mem.eql(u8, child_type, "media_statement");
                
                // Add blank line between rules
                if (prev_was_rule and is_rule) {
                    try builder.newline();
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
                    try formatComment(child, source, builder, depth, options);
                }
                
                // Add newline after each top-level item except the last
                if (i < child_count - 1) {
                    try builder.newline();
                }
                
                prev_was_rule = is_rule;
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
                try appendNodeText(child, source, builder);
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
                            const prop_text = getNodeText(decl_child, source);
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
    const length_diff = max_prop_len - min_prop_len;
    const should_align = declarations.items.len >= 4 and length_diff >= 4;
    
    // Second pass: format all children
    i = 0;
    while (i < child_count) : (i += 1) {
        if (node.child(i)) |child| {
            const child_type = child.kind();
            
            if (std.mem.eql(u8, child_type, "declaration")) {
                try formatDeclarationWithAlignment(child, source, builder, options, should_align, max_prop_len);
            } else if (std.mem.eql(u8, child_type, "comment")) {
                try builder.appendIndent();
                try appendNodeText(child, source, builder);
                try builder.newline();
            } else if (std.mem.eql(u8, child_type, "rule_set")) {
                // Nested rule - TODO: handle properly without circular reference
                // For now, just output as-is
                try builder.appendIndent();
                try appendNodeText(child, source, builder);
                try builder.newline();
            }
        }
    }
}

/// Format CSS declaration with optional alignment
fn formatDeclarationWithAlignment(node: ts.Node, source: []const u8, builder: *LineBuilder, options: FormatterOptions, should_align: bool, max_prop_len: usize) !void {
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
                const prop_text = getNodeText(child, source);
                property_len = prop_text.len;
                try appendNodeText(child, source, builder);
                try builder.append(":");
                
                // Add alignment spaces if needed
                if (should_align) {
                    // Align values to start at roughly the same column
                    // Each property gets: max_prop_len - property_len spaces after the colon
                    const base_spaces = max_prop_len - property_len;
                    // Ensure at least 1 space for the longest property
                    const spaces_to_add = if (base_spaces == 0) 1 else base_spaces;
                    var j: usize = 0;
                    while (j < spaces_to_add) : (j += 1) {
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
        try appendNodeText(node, source, builder);
        if (!std.mem.endsWith(u8, getNodeText(node, source), ";")) {
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
            const child_text = getNodeText(child, source);
            
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
                    try appendNodeText(child, source, builder);
                } else {
                    try appendNodeText(child, source, builder);
                }
                
                first_value = false;
            }
        }
    }
    
    try builder.append(";");
    try builder.newline();
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
                try appendNodeText(child, source, builder);
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
                        const arg_text = getNodeText(arg, source);
                        
                        // Skip parentheses and commas
                        if (std.mem.eql(u8, arg_text, "(") or 
                            std.mem.eql(u8, arg_text, ")") or
                            std.mem.eql(u8, arg_text, ",")) {
                            continue;
                        }
                        
                        if (!first_arg) {
                            try builder.append(", ");
                        }
                        try appendNodeText(arg, source, builder);
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
                std.mem.eql(u8, child_type, "parenthesized_query")) {
                
                if (query_found) {
                    try builder.append(", ");
                }
                try appendNodeText(child, source, builder);
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
                try appendNodeText(child, source, builder);
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
    try appendNodeText(node, source, builder);
    
    // Ensure at-rules end with semicolon
    const text = getNodeText(node, source);
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
    try appendNodeText(node, source, builder);
    
    // Ensure import ends with semicolon
    const text = getNodeText(node, source);
    if (!std.mem.endsWith(u8, text, ";")) {
        try builder.append(";");
    }
    try builder.newline();
}

/// Format comment
fn formatComment(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
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

/// Format CSS source using AST-based approach
pub fn format(allocator: std.mem.Allocator, source: []const u8, options: FormatterOptions) ![]const u8 {
    // Use the AST formatter infrastructure
    var formatter = @import("../../parsing/ast_formatter.zig").AstFormatter.init(allocator, .css, options) catch |err| {
        // If AST formatting fails, return original source
        std.log.debug("CSS formatter AST init failed: {}", .{err});
        return allocator.dupe(u8, source);
    };
    defer formatter.deinit();
    
    const result = formatter.format(source) catch |err| {
        std.log.debug("CSS formatter format failed: {}", .{err});
        return allocator.dupe(u8, source);
    };
    
    return result;
}