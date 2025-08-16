const std = @import("std");
const ts = @import("tree-sitter");
const LineBuilder = @import("../../parsing/formatter.zig").LineBuilder;
const FormatterOptions = @import("../../parsing/formatter.zig").FormatterOptions;

/// Format Svelte using AST-based approach
pub fn formatAst(allocator: std.mem.Allocator, node: ts.Node, source: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
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
    } else if (std.mem.eql(u8, node_type, "element")) {
        // Handle HTML elements with proper indentation
        try formatSvelteElement(node, source, builder, depth, options);
    } else if (std.mem.eql(u8, node_type, "start_tag") or std.mem.eql(u8, node_type, "end_tag") or std.mem.eql(u8, node_type, "text")) {
        // Handle HTML tags and text content
        const element_text = getNodeText(node, source);
        const trimmed = std.mem.trim(u8, element_text, " \t\n\r");
        if (trimmed.len > 0) {
            try builder.appendIndent();
            try builder.append(trimmed);
            try builder.newline();
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

    try builder.append("<script>");
    try builder.newline();

    // Extract script content and format it line by line
    const script_text = getNodeText(node, source);
    if (std.mem.indexOf(u8, script_text, ">")) |start_tag_end| {
        if (std.mem.lastIndexOf(u8, script_text, "</script>")) |end_tag_start| {
            const content = script_text[start_tag_end + 1 .. end_tag_start];
            const trimmed_content = std.mem.trim(u8, content, " \t\n\r");

            if (trimmed_content.len > 0) {
                // Format JavaScript content with proper indentation
                builder.indent();
                try formatJavaScriptContent(trimmed_content, builder, options);
                builder.dedent();
            }
        }
    }

    try builder.append("</script>");
    try builder.newline();
    try builder.newline();
}

/// Format Svelte style section
fn formatSvelteStyle(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) std.mem.Allocator.Error!void {
    _ = depth;

    try builder.append("<style>");
    try builder.newline();

    // Extract style content and format it as CSS
    const style_text = getNodeText(node, source);
    if (std.mem.indexOf(u8, style_text, ">")) |start_tag_end| {
        if (std.mem.lastIndexOf(u8, style_text, "</style>")) |end_tag_start| {
            const content = style_text[start_tag_end + 1 .. end_tag_start];
            const trimmed_content = std.mem.trim(u8, content, " \t\n\r");

            if (trimmed_content.len > 0) {
                // Format CSS content with proper indentation
                builder.indent();
                try formatCSSContent(trimmed_content, builder, options);
                builder.dedent();
            }
        }
    }

    try builder.append("</style>");
    try builder.newline();
}

/// Format CSS content with proper rule formatting
fn formatCSSContent(css_content: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
    _ = options;
    
    // Parse CSS rules by finding selector { properties } patterns
    var current_pos: usize = 0;
    
    while (current_pos < css_content.len) {
        // Find next selector (content before {)
        if (std.mem.indexOfPos(u8, css_content, current_pos, "{")) |brace_start| {
            const selector = std.mem.trim(u8, css_content[current_pos..brace_start], " \t\n\r");
            
            // Find matching closing brace
            var brace_depth: u32 = 1;
            var rule_end = brace_start + 1;
            while (rule_end < css_content.len and brace_depth > 0) {
                if (css_content[rule_end] == '{') {
                    brace_depth += 1;
                } else if (css_content[rule_end] == '}') {
                    brace_depth -= 1;
                }
                rule_end += 1;
            }
            
            if (brace_depth == 0) {
                // Found complete rule
                const properties = std.mem.trim(u8, css_content[brace_start + 1 .. rule_end - 1], " \t\n\r");
                
                // Format the rule
                try builder.appendIndent();
                try builder.append(selector);
                try builder.append(" {");
                try builder.newline();
                
                if (properties.len > 0) {
                    try formatCSSProperties(properties, builder);
                }
                
                try builder.appendIndent();
                try builder.append("}");
                try builder.newline();
                
                // Add blank line between rules
                if (rule_end < css_content.len) {
                    try builder.newline();
                }
                
                current_pos = rule_end;
            } else {
                // Malformed CSS, skip to end
                break;
            }
        } else {
            // No more rules found
            break;
        }
    }
}

/// Format CSS properties within a rule
fn formatCSSProperties(properties: []const u8, builder: *LineBuilder) !void {
    // Split properties by semicolon
    var prop_iter = std.mem.splitScalar(u8, properties, ';');
    
    while (prop_iter.next()) |property| {
        const trimmed_prop = std.mem.trim(u8, property, " \t\n\r");
        if (trimmed_prop.len > 0) {
            try builder.appendIndent();
            try builder.appendIndent(); // Double indent for properties within rules
            
            // Format property with proper spacing around colon
            if (std.mem.indexOf(u8, trimmed_prop, ":")) |colon_pos| {
                const prop_name = std.mem.trim(u8, trimmed_prop[0..colon_pos], " \t");
                const prop_value = std.mem.trim(u8, trimmed_prop[colon_pos + 1..], " \t");
                
                try builder.append(prop_name);
                try builder.append(": ");
                try builder.append(prop_value);
            } else {
                // Malformed property, just append as-is
                try builder.append(trimmed_prop);
            }
            
            try builder.append(";");
            try builder.newline();
        }
    }
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

/// Format JavaScript content within a script tag
fn formatJavaScriptContent(js_content: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
    // Parse JavaScript statements and format them properly
    var statements = std.ArrayList([]const u8).init(builder.allocator);
    defer statements.deinit();
    
    // Split by semicolons to find statements
    var current_pos: usize = 0;
    var brace_depth: i32 = 0;
    var paren_depth: i32 = 0;
    var string_char: ?u8 = null;
    
    for (js_content, 0..) |char, i| {
        // Track string boundaries
        if (string_char == null and (char == '\'' or char == '"')) {
            string_char = char;
        } else if (string_char != null and char == string_char.?) {
            string_char = null;
        }
        
        // Only process structural characters outside strings
        if (string_char == null) {
            switch (char) {
                '{' => brace_depth += 1,
                '}' => brace_depth -= 1,
                '(' => paren_depth += 1,
                ')' => paren_depth -= 1,
                ';' => {
                    if (brace_depth == 0 and paren_depth == 0) {
                        // Found statement boundary
                        const statement = std.mem.trim(u8, js_content[current_pos..i], " \t\n\r");
                        if (statement.len > 0) {
                            try statements.append(statement);
                        }
                        current_pos = i + 1;
                    }
                },
                else => {},
            }
        }
    }
    
    // Add final statement if no trailing semicolon
    if (current_pos < js_content.len) {
        const statement = std.mem.trim(u8, js_content[current_pos..], " \t\n\r");
        if (statement.len > 0) {
            try statements.append(statement);
        }
    }
    
    // Format each statement
    for (statements.items, 0..) |statement, i| {
        try builder.appendIndent();
        
        // Check if this is a reactive statement
        if (std.mem.startsWith(u8, statement, "$:")) {
            try formatReactiveStatement(statement, builder, options);
        } else {
            try formatJavaScriptStatement(statement, builder, options);
        }
        
        // Only add semicolon for non-function statements
        if (std.mem.indexOf(u8, statement, "function ") == null) {
            try builder.append(";");
        }
        
        try builder.newline();
        
        // Add blank line only between different statement types (variable vs reactive vs function)
        if (i < statements.items.len - 1) {
            const current_is_function = std.mem.indexOf(u8, statement, "function ") != null;
            const current_is_declaration = std.mem.startsWith(u8, statement, "let ") or 
                                           std.mem.startsWith(u8, statement, "const ") or
                                           std.mem.startsWith(u8, statement, "var ") or
                                           std.mem.startsWith(u8, statement, "export let");
            
            const next = statements.items[i + 1];
            const next_is_function = std.mem.indexOf(u8, next, "function ") != null;
            const next_is_reactive = std.mem.startsWith(u8, next, "$:");
            
            // Add blank line when transitioning from variable declarations to reactive statements  
            if (current_is_declaration and next_is_reactive) {
                try builder.appendIndent();  // Add indented blank line
                try builder.newline();  // Complete the blank line
            }
            // Or between function and non-function
            else if (current_is_function != next_is_function) {
                try builder.newline();
            }
        }
    }
}

/// Format HTML element with proper indentation
fn formatSvelteElement(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
    // Check if this element has only inline content (text and expressions)
    const is_inline = isInlineElement(node, source);
    
    if (is_inline) {
        // Format inline element on a single line
        try builder.appendIndent();
        const element_text = getNodeText(node, source);
        try builder.append(element_text);
        try builder.newline();
    } else {
        // Format block element with proper indentation
        const child_count = node.childCount();
        var i: u32 = 0;
        
        while (i < child_count) : (i += 1) {
            if (node.child(i)) |child| {
                const child_type = child.kind();
                
                if (std.mem.eql(u8, child_type, "start_tag")) {
                    try builder.appendIndent();
                    const tag_text = getNodeText(child, source);
                    try builder.append(tag_text);
                    try builder.newline();
                    builder.indent();
                } else if (std.mem.eql(u8, child_type, "end_tag")) {
                    builder.dedent();
                    try builder.appendIndent();
                    const tag_text = getNodeText(child, source);
                    try builder.append(tag_text);
                    try builder.newline();
                } else if (std.mem.eql(u8, child_type, "element")) {
                    // Nested element
                    try formatSvelteElement(child, source, builder, depth + 1, options);
                } else {
                    // Other content (text, expressions)
                    try formatSvelteNode(child, source, builder, depth + 1, options);
                }
            }
        }
    }
}

/// Check if an element should be formatted inline (has only simple text/expressions)
fn isInlineElement(node: ts.Node, source: []const u8) bool {
    const child_count = node.childCount();
    if (child_count == 0) return true;
    
    // Count non-tag children to see if it's just simple content
    var content_children: u32 = 0;
    var has_nested_elements = false;
    
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        if (node.child(i)) |child| {
            const child_type = child.kind();
            if (!std.mem.eql(u8, child_type, "start_tag") and !std.mem.eql(u8, child_type, "end_tag")) {
                content_children += 1;
                if (std.mem.eql(u8, child_type, "element")) {
                    has_nested_elements = true;
                }
            }
        }
    }
    
    // If it has nested elements or too much content, format as block
    if (has_nested_elements or content_children > 3) {
        return false;
    }
    
    // Check content length - if short, keep inline
    const element_text = getNodeText(node, source);
    return element_text.len < 60; // Arbitrary threshold for inline vs block
}

/// Format a reactive statement with proper spacing
fn formatReactiveStatement(statement: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
    // Skip the "$: " part and format the rest
    if (statement.len > 3) {
        const reactive_content = std.mem.trim(u8, statement[2..], " \t");
        try builder.append("$: ");
        try formatJavaScriptBasic(reactive_content, builder, options);
    } else {
        try builder.append(statement);
    }
}

/// Format a single JavaScript statement with proper spacing
fn formatJavaScriptStatement(statement: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
    // Check if this is a function declaration
    if (std.mem.indexOf(u8, statement, "function ") != null) {
        try formatJavaScriptFunction(statement, builder, options);
    } else {
        // Regular statement formatting
        try formatJavaScriptBasic(statement, builder, options);
    }
}

/// Format JavaScript function with proper body expansion
fn formatJavaScriptFunction(statement: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
    
    // Find function parts: signature and body
    if (std.mem.indexOf(u8, statement, "{")) |brace_pos| {
        // Has function body
        const signature = std.mem.trim(u8, statement[0..brace_pos], " \t");
        const body_with_braces = std.mem.trim(u8, statement[brace_pos..], " \t");
        
        // Format signature with proper spacing
        try formatFunctionSignature(signature, builder);
        try builder.append(" {");
        try builder.newline();
        
        // Format function body
        if (std.mem.startsWith(u8, body_with_braces, "{") and std.mem.endsWith(u8, body_with_braces, "}")) {
            const body_content = std.mem.trim(u8, body_with_braces[1..body_with_braces.len-1], " \t\n\r");
            if (body_content.len > 0) {
                builder.indent();
                try builder.appendIndent();
                try formatJavaScriptBasic(body_content, builder, options);
                try builder.newline();
                builder.dedent();
            }
        }
        
        try builder.appendIndent();
        try builder.append("}");
    } else {
        // No body, just format as basic statement
        try formatJavaScriptBasic(statement, builder, options);
    }
}

/// Format function signature with proper spacing around parentheses
fn formatFunctionSignature(signature: []const u8, builder: *LineBuilder) !void {
    // Just use the signature as-is but with proper spacing
    // e.g., "function greet" stays as "function greet"
    try builder.append(signature);
    
    // Add parentheses if not present
    if (std.mem.indexOf(u8, signature, "(") == null) {
        try builder.append("()");
    }
}

/// Format basic JavaScript statement with operator spacing
fn formatJavaScriptBasic(statement: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
    _ = options;
    
    var i: usize = 0;
    var string_char: ?u8 = null;
    
    while (i < statement.len) : (i += 1) {
        const char = statement[i];
        
        // Track string boundaries
        if (string_char == null and (char == '\'' or char == '"')) {
            string_char = char;
            try builder.append(&[_]u8{char});
        } else if (string_char != null and char == string_char.?) {
            string_char = null;
            try builder.append(&[_]u8{char});
        } else if (string_char != null) {
            // Inside string - preserve as-is
            try builder.append(&[_]u8{char});
        } else {
            // Outside string - apply formatting
            if (char == '=') {
                // Add spaces around = if not present
                if (i > 0 and statement[i-1] != ' ') {
                    try builder.append(" ");
                }
                try builder.append(&[_]u8{char});
                if (i + 1 < statement.len and statement[i + 1] != ' ') {
                    try builder.append(" ");
                }
            } else if (char == '+' or char == '-' or char == '*') {
                // Add spaces around arithmetic operators if not present
                if (i > 0 and statement[i-1] != ' ') {
                    try builder.append(" ");
                }
                try builder.append(&[_]u8{char});
                if (i + 1 < statement.len and statement[i + 1] != ' ') {
                    try builder.append(" ");
                }
            } else if (char == ',') {
                // Add space after comma if not present
                try builder.append(&[_]u8{char});
                if (i + 1 < statement.len and statement[i + 1] != ' ') {
                    try builder.append(" ");
                }
            } else if (char == ':' and i > 0) {
                // Add space after colon if not present (for object properties and console.log)
                try builder.append(&[_]u8{char});
                if (i + 1 < statement.len and statement[i + 1] != ' ') {
                    try builder.append(" ");
                }
            } else {
                try builder.append(&[_]u8{char});
            }
        }
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

