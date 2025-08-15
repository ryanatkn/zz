const std = @import("std");
const ts = @import("tree-sitter");
const LineBuilder = @import("../../parsing/formatter.zig").LineBuilder;
const FormatterOptions = @import("../../parsing/formatter.zig").FormatterOptions;

/// Format TypeScript using AST-based approach
pub fn formatAst(allocator: std.mem.Allocator, node: ts.Node, source: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
    _ = allocator;
    try formatTypeScriptNode(node, source, builder, 0, options);
}

/// TypeScript node formatting with controlled recursion
fn formatTypeScriptNode(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) std.mem.Allocator.Error!void {
    const node_type = node.kind();

    if (std.mem.eql(u8, node_type, "function_declaration")) {
        try formatFunction(node, source, builder, depth, options);
    } else if (std.mem.eql(u8, node_type, "interface_declaration")) {
        try formatInterface(node, source, builder, depth, options);
    } else if (std.mem.eql(u8, node_type, "class_declaration")) {
        try formatClass(node, source, builder, depth, options);
    } else if (std.mem.eql(u8, node_type, "type_alias_declaration")) {
        try formatTypeAlias(node, source, builder, depth, options);
    } else if (std.mem.eql(u8, node_type, "program") or std.mem.eql(u8, node_type, "source_file")) {
        // For container nodes, recurse into children
        const child_count = node.childCount();
        var i: u32 = 0;
        while (i < child_count) : (i += 1) {
            if (node.child(i)) |child| {
                try formatTypeScriptNode(child, source, builder, depth, options);
            }
        }
    } else if (std.mem.eql(u8, node_type, "ERROR")) {
        // For ERROR nodes (malformed code), preserve the original text exactly
        try appendNodeText(node, source, builder);
    } else {
        // For other unknown nodes, just append text without recursion
        try appendNodeText(node, source, builder);
    }
}

/// Format TypeScript parameters with proper spacing and line breaking
fn formatParameters(params_node: ts.Node, source: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
    const params_text = getNodeText(params_node, source);
    
    // Check if we need to break across multiple lines
    const estimated_length = params_text.len + 20; // Include function name and return type
    
    if (estimated_length > options.line_width) {
        // Multi-line format
        try builder.append("(");
        try builder.newline();
        builder.indent();
        
        // Parse parameters and format each on its own line
        // Simple approach: split by comma and format each parameter
        var param_start: usize = 1; // Skip opening paren
        var i: usize = 1;
        var paren_depth: u32 = 0;
        var angle_depth: u32 = 0;
        
        while (i < params_text.len - 1) : (i += 1) { // Skip closing paren
            const char = params_text[i];
            switch (char) {
                '(' => paren_depth += 1,
                ')' => paren_depth -= 1,
                '<' => angle_depth += 1,
                '>' => angle_depth -= 1,
                ',' => {
                    if (paren_depth == 0 and angle_depth == 0) {
                        // Found a parameter boundary
                        const param = std.mem.trim(u8, params_text[param_start..i], " \t");
                        try builder.appendIndent();
                        try formatSingleParameter(param, builder);
                        try builder.append(",");
                        try builder.newline();
                        param_start = i + 1;
                    }
                },
                else => {},
            }
        }
        
        // Handle last parameter (no trailing comma)
        if (param_start < params_text.len - 1) {
            const last_param = std.mem.trim(u8, params_text[param_start..params_text.len-1], " \t");
            if (last_param.len > 0) {
                try builder.appendIndent();
                try formatSingleParameter(last_param, builder);
                try builder.newline();
            }
        }
        
        builder.dedent();
        try builder.appendIndent();
        try builder.append(")");
    } else {
        // Single line format with spacing
        try builder.append("(");
        if (params_text.len > 2) { // More than just "()"
            const inner_params = params_text[1..params_text.len-1];
            var formatted_params = std.ArrayList(u8).init(builder.allocator);
            defer formatted_params.deinit();
            
            // Add proper spacing around colons (no space before, space after)
            var i: usize = 0;
            while (i < inner_params.len) : (i += 1) {
                const char = inner_params[i];
                if (char == ':') {
                    // Remove any space before colon if present
                    if (formatted_params.items.len > 0 and formatted_params.items[formatted_params.items.len - 1] == ' ') {
                        _ = formatted_params.pop();
                    }
                    try formatted_params.append(char);
                    // Add space after colon if not present
                    if (i + 1 < inner_params.len and inner_params[i + 1] != ' ') {
                        try formatted_params.append(' ');
                    }
                } else {
                    try formatted_params.append(char);
                }
            }
            
            try builder.append(formatted_params.items);
        }
        try builder.append(")");
    }
}

/// Format a single parameter with proper spacing
fn formatSingleParameter(param: []const u8, builder: *LineBuilder) !void {
    // Add proper spacing around colons (no space before, space after)
    var i: usize = 0;
    while (i < param.len) : (i += 1) {
        const char = param[i];
        if (char == ':') {
            // Don't add extra space before colon
            try builder.append(&[_]u8{char});
            // Add space after colon if not present
            if (i + 1 < param.len and param[i + 1] != ' ') {
                try builder.append(" ");
            }
        } else if (char == ' ' and i + 1 < param.len and param[i + 1] == ':') {
            // Skip space before colon
            continue;
        } else {
            try builder.append(&[_]u8{char});
        }
    }
}

/// Format return type with proper spacing around union types
fn formatReturnType(return_text: []const u8, builder: *LineBuilder) !void {
    // Add spaces around | in union types and format the return type
    var i: usize = 0;
    while (i < return_text.len) : (i += 1) {
        const char = return_text[i];
        if (char == '|') {
            // Add space before | if not present
            if (i > 0 and return_text[i-1] != ' ') {
                try builder.append(" ");
            }
            try builder.append(&[_]u8{char});
            // Add space after | if not present
            if (i + 1 < return_text.len and return_text[i+1] != ' ') {
                try builder.append(" ");
            }
        } else {
            try builder.append(&[_]u8{char});
        }
    }
}

/// Format return type for multi-line functions with proper colon spacing
fn formatReturnTypeMultiline(return_text: []const u8, builder: *LineBuilder) !void {
    // For multi-line, we want ": Type" not ":Type"
    var i: usize = 0;
    while (i < return_text.len) : (i += 1) {
        const char = return_text[i];
        if (char == ':') {
            try builder.append(&[_]u8{char});
            // Add space after colon if not present
            if (i + 1 < return_text.len and return_text[i + 1] != ' ') {
                try builder.append(" ");
            }
        } else if (char == '|') {
            // Add space before | if not present
            if (i > 0 and return_text[i-1] != ' ') {
                try builder.append(" ");
            }
            try builder.append(&[_]u8{char});
            // Add space after | if not present
            if (i + 1 < return_text.len and return_text[i+1] != ' ') {
                try builder.append(" ");
            }
        } else {
            try builder.append(&[_]u8{char});
        }
    }
}

/// Format TypeScript function
fn formatFunction(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) std.mem.Allocator.Error!void {
    _ = depth;

    // Add proper indentation
    try builder.appendIndent();

    // Extract function signature and format it
    if (node.childByFieldName("name")) |name_node| {
        const name_text = getNodeText(name_node, source);

        // Format: function name(params): returnType {
        try builder.append("function ");
        try builder.append(name_text);

        var used_multiline_params = false;
        if (node.childByFieldName("parameters")) |params_node| {
            const params_text = getNodeText(params_node, source);
            const estimated_length = params_text.len + 20;
            used_multiline_params = estimated_length > options.line_width;
            try formatParameters(params_node, source, builder, options);
        }

        if (node.childByFieldName("return_type")) |return_node| {
            const return_text = getNodeText(return_node, source);
            
            if (used_multiline_params) {
                try formatReturnTypeMultiline(return_text, builder);
            } else {
                try formatReturnType(return_text, builder);
            }
        }

        try builder.append(" {");
        try builder.newline();

        // Format function body with increased indentation
        if (node.childByFieldName("body")) |body_node| {
            builder.indent();
            try builder.appendIndent();
            const body_text = getNodeText(body_node, source);
            // Remove braces from body text and format content
            if (std.mem.startsWith(u8, body_text, "{") and std.mem.endsWith(u8, body_text, "}")) {
                const inner_body = std.mem.trim(u8, body_text[1..body_text.len-1], " \t\r\n");
                try builder.append(inner_body);
            } else {
                try builder.append(body_text);
            }
            try builder.newline();
            builder.dedent();
        }

        try builder.appendIndent();
        try builder.append("}");
        try builder.newline();
    } else {
        // Fallback to raw node text if field extraction fails
        try appendNodeText(node, source, builder);
    }
}

/// Format TypeScript interface
fn formatInterface(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) std.mem.Allocator.Error!void {
    try builder.appendIndent();

    if (node.childByFieldName("name")) |name_node| {
        const name_text = getNodeText(name_node, source);
        try builder.append("interface ");
        try builder.append(name_text);
        try builder.append(" {");
        try builder.newline();

        // Format interface members
        builder.indent();
        if (node.childByFieldName("body")) |body_node| {
            try formatTypeScriptNode(body_node, source, builder, depth + 1, options);
        }
        builder.dedent();

        try builder.appendIndent();
        try builder.append("}");
        try builder.newline();
    } else {
        try appendNodeText(node, source, builder);
    }
}

/// Format TypeScript class
fn formatClass(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) std.mem.Allocator.Error!void {
    try builder.appendIndent();
    try builder.append("class ");

    if (node.childByFieldName("name")) |name_node| {
        const name_text = getNodeText(name_node, source);
        try builder.append(name_text);
    }

    try builder.append(" {");
    try builder.newline();

    // Format class body
    builder.indent();
    if (node.childByFieldName("body")) |body_node| {
        try formatTypeScriptNode(body_node, source, builder, depth + 1, options);
    }
    builder.dedent();

    try builder.appendIndent();
    try builder.append("}");
    try builder.newline();
}

/// Format TypeScript type alias
fn formatTypeAlias(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
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

/// Check if a node represents a TypeScript function
pub fn isTypeScriptFunction(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "function_declaration") or
        std.mem.eql(u8, node_type, "method_definition") or
        std.mem.eql(u8, node_type, "arrow_function");
}

/// Check if a node represents a TypeScript type definition
pub fn isTypeScriptType(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "interface_declaration") or
        std.mem.eql(u8, node_type, "class_declaration") or
        std.mem.eql(u8, node_type, "type_alias_declaration") or
        std.mem.eql(u8, node_type, "enum_declaration");
}

/// Format TypeScript source using AST-based approach
pub fn format(allocator: std.mem.Allocator, source: []const u8, options: FormatterOptions) ![]const u8 {
    // Use the AST formatter infrastructure
    var formatter = @import("../../parsing/ast_formatter.zig").AstFormatter.init(allocator, .typescript, options) catch {
        // If AST formatting fails, return original source
        return allocator.dupe(u8, source);
    };
    defer formatter.deinit();

    return formatter.format(source);
}

