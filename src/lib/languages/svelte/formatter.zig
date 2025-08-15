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
                // Format JavaScript content
                try formatJavaScriptContent(trimmed_content, builder, options);
            }
        }
    }

    try builder.append("</script>");
    try builder.newline();
    try builder.newline(); // Add blank line after script section
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
        try builder.append("    "); // 4-space indent
        try formatJavaScriptStatement(statement, builder, options);
        try builder.append(";");
        try builder.newline();
        
        // Add blank line between statements for readability
        if (i < statements.items.len - 1) {
            try builder.newline();
        }
    }
}

/// Format HTML element with proper indentation
fn formatSvelteElement(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
    // Format element by processing its children
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
            } else if (std.mem.eql(u8, child_type, "text")) {
                const text_content = getNodeText(child, source);
                const trimmed = std.mem.trim(u8, text_content, " \t\n\r");
                if (trimmed.len > 0) {
                    try builder.appendIndent();
                    try builder.append(trimmed);
                    try builder.newline();
                }
            } else if (std.mem.eql(u8, child_type, "element")) {
                // Nested element
                try formatSvelteElement(child, source, builder, depth + 1, options);
            } else {
                // Other content
                try formatSvelteNode(child, source, builder, depth + 1, options);
            }
        }
    }
}

/// Format a single JavaScript statement with proper spacing
fn formatJavaScriptStatement(statement: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
    _ = options;
    
    // Basic JavaScript formatting - add spaces around key operators
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
            } else if (char == '+') {
                // Add spaces around + if not present (for string concatenation)
                if (i > 0 and statement[i-1] != ' ') {
                    try builder.append(" ");
                }
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

// Legacy format function for backwards compatibility - delegates to AST formatter
pub fn format(allocator: std.mem.Allocator, source: []const u8, options: FormatterOptions) ![]const u8 {
    // TODO: This will be removed once we fully transition to AST-only formatting
    // For now, return error to force use of AST formatter
    _ = allocator;
    _ = source;
    _ = options;
    return error.UnsupportedOperation;
}
