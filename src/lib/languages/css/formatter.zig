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
    
    // Debug: log node types to understand AST structure
    std.log.debug("CSS node type: '{s}' (depth={})", .{node_type, depth});

    if (std.mem.eql(u8, node_type, "rule_set")) {
        try formatCssRule(node, source, builder, depth, options, true); // Single rule is last rule
    } else if (std.mem.eql(u8, node_type, "at_rule") or std.mem.eql(u8, node_type, "media_statement")) {
        try formatCssAtRule(node, source, builder, depth, options);
    } else if (std.mem.eql(u8, node_type, "declaration")) {
        try formatCssDeclaration(node, source, builder, depth, options);
    } else if (std.mem.eql(u8, node_type, "comment")) {
        try formatCssComment(node, source, builder, depth, options);
    } else if (std.mem.eql(u8, node_type, "stylesheet") or std.mem.eql(u8, node_type, "block")) {
        // For container nodes, recurse into children and add spacing between rules
        const child_count = node.childCount();
        
        // First pass: count rules to track the last one
        var total_rules: u32 = 0;
        var i: u32 = 0;
        while (i < child_count) : (i += 1) {
            if (node.child(i)) |child| {
                if (std.mem.eql(u8, child.kind(), "rule_set")) {
                    total_rules += 1;
                }
            }
        }
        
        // Second pass: format rules
        var rule_count: u32 = 0;
        i = 0;
        while (i < child_count) : (i += 1) {
            if (node.child(i)) |child| {
                const child_type = child.kind();
                if (std.mem.eql(u8, child_type, "rule_set")) {
                    if (rule_count > 0) {
                        try builder.newline(); // Add blank line between rules
                    }
                    rule_count += 1;
                    const is_last_rule = (rule_count == total_rules);
                    try formatCssRule(child, source, builder, depth, options, is_last_rule);
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
fn formatCssRule(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions, is_last_rule: bool) !void {
    _ = depth;
    std.log.debug("CSS formatCssRule called for: {s}", .{getNodeText(node, source)});

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

    // Format declarations with indentation and property alignment
    builder.indent();
    
    // Debug: Log node info and check for block field
    std.log.debug("CSS formatCssRule looking for block field in node type: '{s}'", .{node.kind()});
    const child_count = node.childCount();
    std.log.debug("CSS formatCssRule node has {} children", .{child_count});
    
    if (node.childByFieldName("block")) |block_node| {
        std.log.debug("CSS using AST-based declaration formatting with block type: '{s}'", .{block_node.kind()});
        try formatCssDeclarationsFromAST(block_node, source, builder, options);
    } else {
        std.log.debug("CSS using fallback declaration formatting - no 'block' field found", .{});
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
    
    // Only add newline if not the last rule
    if (!is_last_rule) {
        try builder.newline();
    }
}

/// Format CSS at-rule (e.g., @media, @import, @keyframes)
fn formatCssAtRule(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
    try builder.appendIndent();
    
    // Get the full text to parse the at-rule structure
    const rule_text = getNodeText(node, source);
    
    // Check if this is a media query or similar block at-rule
    if (std.mem.startsWith(u8, rule_text, "@media") or 
        std.mem.startsWith(u8, rule_text, "@supports") or
        std.mem.startsWith(u8, rule_text, "@keyframes")) {
        
        // Find the opening brace
        if (std.mem.indexOf(u8, rule_text, "{")) |brace_pos| {
            // Format the at-rule declaration
            const declaration = std.mem.trim(u8, rule_text[0..brace_pos], " \t\n\r");
            try builder.append(declaration);
            try builder.append(" {");
            try builder.newline();
            
            // Process nested content with increased indentation
            builder.indent();
            
            // Extract content between braces
            if (std.mem.lastIndexOf(u8, rule_text, "}")) |end_brace| {
                const content = rule_text[brace_pos + 1 .. end_brace];
                
                // Parse and format nested rules
                try formatNestedCssContent(content, builder, depth + 1, options);
            }
            
            builder.dedent();
            try builder.appendIndent();
            try builder.append("}");
        } else {
            // No block content, just format as simple at-rule
            try builder.append(std.mem.trim(u8, rule_text, " \t\n\r"));
            try builder.newline();
        }
    } else {
        // Simple at-rules like @import
        try builder.append(std.mem.trim(u8, rule_text, " \t\n\r"));
        try builder.newline();
    }
}

/// Format nested CSS content (used inside media queries, etc.)
fn formatNestedCssContent(content: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
    // Split content into rules and format each one
    var remaining = std.mem.trim(u8, content, " \t\n\r");
    var rule_count: u32 = 0;
    
    while (remaining.len > 0) {
        // Find the next rule end
        var brace_count: i32 = 0;
        var rule_end: usize = 0;
        
        for (remaining, 0..) |char, i| {
            if (char == '{') {
                brace_count += 1;
            } else if (char == '}') {
                brace_count -= 1;
                if (brace_count == 0) {
                    rule_end = i + 1;
                    break;
                }
            }
        }
        
        if (rule_end == 0) break; // No complete rule found
        
        // Add indented blank line before subsequent rules (not the first)
        if (rule_count > 0) {
            try builder.appendIndent();
            try builder.newline();
        }
        
        // Extract and format this rule
        const rule = std.mem.trim(u8, remaining[0..rule_end], " \t\n\r");
        try formatSingleRule(rule, builder, depth, options);
        
        rule_count += 1;
        
        // Move to next rule
        remaining = std.mem.trim(u8, remaining[rule_end..], " \t\n\r");
    }
}

/// Format a single CSS rule from text
fn formatSingleRule(rule_text: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
    _ = depth;
    
    if (std.mem.indexOf(u8, rule_text, "{")) |brace_pos| {
        // Format selector
        const selector = std.mem.trim(u8, rule_text[0..brace_pos], " \t\n\r");
        try builder.appendIndent();
        try builder.append(selector);
        try builder.append(" {");
        try builder.newline();
        
        // Format declarations with property alignment
        if (std.mem.lastIndexOf(u8, rule_text, "}")) |end_brace| {
            const declarations_text = rule_text[brace_pos + 1 .. end_brace];
            try formatCssDeclarations(declarations_text, builder, options);
        }
        
        try builder.appendIndent();
        try builder.append("}");
        try builder.newline();
    }
}

/// Format CSS declarations from AST nodes with property alignment
fn formatCssDeclarationsFromAST(block_node: ts.Node, source: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
    _ = options;
    // First pass: collect all declaration properties and values
    var declarations = std.ArrayList(struct { property: []const u8, value: []const u8 }).init(builder.allocator);
    defer declarations.deinit();
    
    var max_prop_len: usize = 0;
    
    const child_count = block_node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        if (block_node.child(i)) |child| {
            const child_type = child.kind();
            if (std.mem.eql(u8, child_type, "declaration")) {
                if (child.childByFieldName("property")) |prop_node| {
                    if (child.childByFieldName("value")) |value_node| {
                        const prop_text = std.mem.trim(u8, getNodeText(prop_node, source), " \t\n\r");
                        const value_text = std.mem.trim(u8, getNodeText(value_node, source), " \t\n\r");
                        max_prop_len = @max(max_prop_len, prop_text.len);
                        try declarations.append(.{ .property = prop_text, .value = value_text });
                    }
                }
            }
        }
    }
    
    // Apply alignment logic
    var min_prop_len: usize = std.math.maxInt(usize);
    for (declarations.items) |decl| {
        min_prop_len = @min(min_prop_len, decl.property.len);
    }
    
    const length_diff = max_prop_len - min_prop_len;
    const should_align = declarations.items.len >= 2 and length_diff >= 4;
    
    std.log.debug("CSS AST alignment: items={d}, max_len={d}, min_len={d}, diff={d}, should_align={}", .{ declarations.items.len, max_prop_len, min_prop_len, length_diff, should_align });
    
    // Debug: Log all extracted properties to understand the data
    for (declarations.items, 0..) |decl, idx| {
        std.log.debug("CSS property[{}]: '{s}' (len={})", .{ idx, decl.property, decl.property.len });
    }
    
    // Second pass: format with alignment
    for (declarations.items) |decl| {
        try builder.appendIndent();
        try builder.append(decl.property);
        try builder.append(":");
        
        if (should_align) {
            // Add spaces for alignment
            const spaces_needed = max_prop_len - decl.property.len + 6; // 6 spaces minimum after colon
            for (0..spaces_needed) |_| {
                try builder.append(" ");
            }
        } else {
            // Regular single space formatting
            try builder.append(" ");
        }
        
        // Format the value (handle rgba spacing)
        const formatted_value = try formatCssValue(decl.value, builder.allocator);
        defer builder.allocator.free(formatted_value);
        try builder.append(formatted_value);
        try builder.append(";");
        try builder.newline();
    }
}

/// Format CSS declarations with property alignment
fn formatCssDeclarations(declarations_text: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
    _ = options;
    
    // First pass: collect all declarations and find max property name length
    var declarations = std.ArrayList(struct { property: []const u8, value: []const u8 }).init(builder.allocator);
    defer declarations.deinit();
    
    var max_prop_len: usize = 0;
    var iter = std.mem.splitScalar(u8, declarations_text, ';');
    
    while (iter.next()) |decl| {
        const trimmed = std.mem.trim(u8, decl, " \t\n\r");
        if (trimmed.len > 0) {
            if (std.mem.indexOf(u8, trimmed, ":")) |colon_pos| {
                const prop = std.mem.trim(u8, trimmed[0..colon_pos], " \t");
                const val = std.mem.trim(u8, trimmed[colon_pos + 1 ..], " \t");
                max_prop_len = @max(max_prop_len, prop.len);
                try declarations.append(.{ .property = prop, .value = val });
            }
        }
    }
    
    // Second pass: format with alignment
    builder.indent();
    
    // Apply property alignment based on property length variation
    // Calculate if there's significant variation in property name lengths
    var min_prop_len: usize = std.math.maxInt(usize);
    for (declarations.items) |decl| {
        min_prop_len = @min(min_prop_len, decl.property.len);
    }
    
    // Apply alignment if we have multiple properties with significant length differences
    const length_diff = max_prop_len - min_prop_len;
    // Apply alignment when there are multiple properties and meaningful length variation
    const should_align = declarations.items.len >= 2 and length_diff >= 4;
    
    // Debug: log alignment decision
    std.log.debug("CSS alignment: items={d}, max_len={d}, min_len={d}, diff={d}, should_align={}", .{ declarations.items.len, max_prop_len, min_prop_len, length_diff, should_align });
    
    for (declarations.items) |decl| {
        try builder.appendIndent();
        try builder.append(decl.property);
        try builder.append(":");
        
        if (should_align) {
            // Add spaces for alignment
            const spaces_needed = max_prop_len - decl.property.len + 6; // 6 spaces minimum after colon
            for (0..spaces_needed) |_| {
                try builder.append(" ");
            }
        } else {
            // Regular single space formatting
            try builder.append(" ");
        }
        
        // Format the value (handle rgba spacing)
        const formatted_value = try formatCssValue(decl.value, builder.allocator);
        defer builder.allocator.free(formatted_value);
        try builder.append(formatted_value);
        try builder.append(";");
        try builder.newline();
    }
    builder.dedent();
}

/// Format CSS values (handle rgba spacing, etc.)
fn formatCssValue(value: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    // Handle rgba() spacing: rgba(0,0,0,0.1) -> rgba(0, 0, 0, 0.1)
    if (std.mem.indexOf(u8, value, "rgba(")) |start| {
        if (std.mem.lastIndexOf(u8, value, ")")) |end| {
            const before = value[0..start];
            const rgba_content = value[start + 5..end];
            const after = value[end..];
            
            // Split and format rgba values
            var rgba_parts = std.ArrayList([]const u8).init(allocator);
            defer rgba_parts.deinit();
            
            var rgba_iter = std.mem.splitScalar(u8, rgba_content, ',');
            while (rgba_iter.next()) |part| {
                try rgba_parts.append(std.mem.trim(u8, part, " \t"));
            }
            
            // Reconstruct with proper spacing
            var result = std.ArrayList(u8).init(allocator);
            defer result.deinit();
            
            try result.appendSlice(before);
            try result.appendSlice("rgba(");
            for (rgba_parts.items, 0..) |part, i| {
                if (i > 0) try result.appendSlice(", ");
                try result.appendSlice(part);
            }
            try result.appendSlice(")");
            try result.appendSlice(after);
            
            return result.toOwnedSlice();
        }
    }
    
    // No special formatting needed, return copy
    return allocator.dupe(u8, value);
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
    
    std.log.debug("CSS formatter success: formatted {} bytes to {} bytes", .{source.len, result.len});
    return result;
}