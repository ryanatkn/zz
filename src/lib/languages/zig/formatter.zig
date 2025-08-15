const std = @import("std");
const ts = @import("tree-sitter");
const FormatterOptions = @import("../../parsing/formatter.zig").FormatterOptions;
const LineBuilder = @import("../../parsing/formatter.zig").LineBuilder;

// Legacy format function for backwards compatibility - delegates to AST formatter
pub fn format(allocator: std.mem.Allocator, source: []const u8, options: FormatterOptions) ![]const u8 {
    // TODO: This will be removed once we fully transition to AST-only formatting
    // For now, return error to force use of AST formatter
    _ = allocator;
    _ = source;
    _ = options;
    return error.UnsupportedOperation;
}

// AST-based Zig formatting

/// Format Zig using AST-based approach
pub fn formatAst(allocator: std.mem.Allocator, node: ts.Node, source: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
    _ = allocator;
    try formatZigNode(node, source, builder, 0, options);
}

/// Zig node formatting with controlled recursion
fn formatZigNode(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) std.mem.Allocator.Error!void {
    const node_type = node.kind();

    if (std.mem.eql(u8, node_type, "function_declaration")) {
        try formatZigFunction(node, source, builder, depth, options);
    } else if (std.mem.eql(u8, node_type, "struct_declaration")) {
        try formatZigStruct(node, source, builder, depth, options);
    } else if (std.mem.eql(u8, node_type, "enum_declaration")) {
        try formatZigEnum(node, source, builder, depth, options);
    } else if (std.mem.eql(u8, node_type, "union_declaration")) {
        try formatZigUnion(node, source, builder, depth, options);
    } else if (std.mem.eql(u8, node_type, "test_declaration")) {
        try formatZigTest(node, source, builder, depth, options);
    } else if (std.mem.eql(u8, node_type, "variable_declaration")) {
        try formatZigVariable(node, source, builder, depth, options);
    } else if (std.mem.eql(u8, node_type, "source_file") or std.mem.eql(u8, node_type, "block")) {
        // For container nodes, recurse into children
        const child_count = node.childCount();
        var i: u32 = 0;
        while (i < child_count) : (i += 1) {
            if (node.child(i)) |child| {
                try formatZigNode(child, source, builder, depth, options);
            }
        }
    } else {
        // For unknown nodes, just append text without recursion
        try appendNodeText(node, source, builder);
    }
}

/// Format Zig function
fn formatZigFunction(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) std.mem.Allocator.Error!void {
    try builder.appendIndent();

    // Check if it's a public function
    if (node.childByFieldName("pub")) |_| {
        try builder.append("pub ");
    }

    try builder.append("fn ");

    // Function name
    if (node.childByFieldName("name")) |name_node| {
        const name_text = getNodeText(name_node, source);
        try builder.append(name_text);
    }

    // Parameters
    if (node.childByFieldName("parameters")) |params_node| {
        const params_text = getNodeText(params_node, source);
        try builder.append(params_text);
    }

    // Return type
    if (node.childByFieldName("return_type")) |return_node| {
        try builder.append(" ");
        const return_text = getNodeText(return_node, source);
        try builder.append(return_text);
    }

    try builder.append(" {");
    try builder.newline();

    // Function body
    if (node.childByFieldName("body")) |body_node| {
        builder.indent();
        try formatZigNode(body_node, source, builder, depth + 1, options);
        builder.dedent();
    }

    try builder.appendIndent();
    try builder.append("}");
    try builder.newline();
}

/// Format Zig struct
fn formatZigStruct(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) std.mem.Allocator.Error!void {
    try builder.appendIndent();

    // Check if it's public
    if (node.childByFieldName("pub")) |_| {
        try builder.append("pub ");
    }

    try builder.append("const ");

    // Struct name
    if (node.childByFieldName("name")) |name_node| {
        const name_text = getNodeText(name_node, source);
        try builder.append(name_text);
    }

    try builder.append(" = struct {");
    try builder.newline();

    // Struct body
    builder.indent();
    const child_count = node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        if (node.child(i)) |child| {
            const child_type = child.kind();
            if (std.mem.eql(u8, child_type, "field_declaration") or
                std.mem.eql(u8, child_type, "function_declaration"))
            {
                try formatZigNode(child, source, builder, depth + 1, options);
            }
        }
    }
    builder.dedent();

    try builder.appendIndent();
    try builder.append("};");
    try builder.newline();
}

/// Format Zig enum
fn formatZigEnum(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
    _ = depth;
    _ = options;

    try builder.appendIndent();

    // Check if it's public
    if (node.childByFieldName("pub")) |_| {
        try builder.append("pub ");
    }

    try builder.append("const ");

    // Enum name
    if (node.childByFieldName("name")) |name_node| {
        const name_text = getNodeText(name_node, source);
        try builder.append(name_text);
    }

    try builder.append(" = enum {");
    try builder.newline();

    // Enum values
    builder.indent();
    const child_count = node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        if (node.child(i)) |child| {
            const child_type = child.kind();
            if (std.mem.eql(u8, child_type, "enum_field")) {
                try builder.appendIndent();
                try appendNodeText(child, source, builder);
                try builder.append(",");
                try builder.newline();
            }
        }
    }
    builder.dedent();

    try builder.appendIndent();
    try builder.append("};");
    try builder.newline();
}

/// Format Zig union
fn formatZigUnion(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
    _ = depth;
    _ = options;

    try builder.appendIndent();

    // Check if it's public
    if (node.childByFieldName("pub")) |_| {
        try builder.append("pub ");
    }

    try builder.append("const ");

    // Union name
    if (node.childByFieldName("name")) |name_node| {
        const name_text = getNodeText(name_node, source);
        try builder.append(name_text);
    }

    try builder.append(" = union {");
    try builder.newline();

    // Union fields
    builder.indent();
    const child_count = node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        if (node.child(i)) |child| {
            const child_type = child.kind();
            if (std.mem.eql(u8, child_type, "field_declaration")) {
                try builder.appendIndent();
                try appendNodeText(child, source, builder);
                try builder.append(",");
                try builder.newline();
            }
        }
    }
    builder.dedent();

    try builder.appendIndent();
    try builder.append("};");
    try builder.newline();
}

/// Format Zig test
fn formatZigTest(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) std.mem.Allocator.Error!void {
    try builder.appendIndent();
    try builder.append("test ");

    // Test name
    if (node.childByFieldName("name")) |name_node| {
        const name_text = getNodeText(name_node, source);
        try builder.append(name_text);
    }

    try builder.append(" {");
    try builder.newline();

    // Test body
    if (node.childByFieldName("body")) |body_node| {
        builder.indent();
        try formatZigNode(body_node, source, builder, depth + 1, options);
        builder.dedent();
    }

    try builder.appendIndent();
    try builder.append("}");
    try builder.newline();
}

/// Format Zig variable declaration
fn formatZigVariable(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
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

/// Check if a node represents a Zig declaration
pub fn isZigDeclaration(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "function_declaration") or
        std.mem.eql(u8, node_type, "struct_declaration") or
        std.mem.eql(u8, node_type, "enum_declaration") or
        std.mem.eql(u8, node_type, "union_declaration") or
        std.mem.eql(u8, node_type, "variable_declaration");
}

/// Check if a node represents a Zig test
pub fn isZigTest(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "test_declaration");
}
