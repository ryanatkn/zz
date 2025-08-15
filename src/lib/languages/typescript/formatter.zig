const std = @import("std");
const ts = @import("tree-sitter");
const LineBuilder = @import("../../parsing/formatter.zig").LineBuilder;
const FormatterOptions = @import("../../parsing/formatter.zig").FormatterOptions;

/// Format TypeScript using AST-based approach
pub fn formatAst(
    allocator: std.mem.Allocator,
    node: ts.Node,
    source: []const u8,
    builder: *LineBuilder,
    options: FormatterOptions
) !void {
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
    } else {
        // For unknown nodes, just append text without recursion
        try appendNodeText(node, source, builder);
    }
}

/// Format TypeScript function
fn formatFunction(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) std.mem.Allocator.Error!void {

    // Add proper indentation
    try builder.appendIndent();

    // Extract function signature and format it
    if (node.childByFieldName("name")) |name_node| {
        const name_text = getNodeText(name_node, source);

        // Format: function name(params): returnType {
        try builder.append("function ");
        try builder.append(name_text);

        if (node.childByFieldName("parameters")) |params_node| {
            const params_text = getNodeText(params_node, source);
            try builder.append(params_text);
        }

        if (node.childByFieldName("return_type")) |return_node| {
            try builder.append(": ");
            const return_text = getNodeText(return_node, source);
            try builder.append(return_text);
        }

        try builder.append(" {");
        try builder.newline();

        // Format function body with increased indentation
        if (node.childByFieldName("body")) |body_node| {
            builder.indent();
            try formatTypeScriptNode(body_node, source, builder, depth + 1, options);
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

// Legacy format function for backwards compatibility - delegates to AST formatter
pub fn format(allocator: std.mem.Allocator, source: []const u8, options: FormatterOptions) ![]const u8 {
    // TODO: This will be removed once we fully transition to AST-only formatting
    // For now, return error to force use of AST formatter
    _ = allocator;
    _ = source;
    _ = options;
    return error.UnsupportedOperation;
}
