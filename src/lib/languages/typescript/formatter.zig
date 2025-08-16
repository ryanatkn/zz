const std = @import("std");
const ts = @import("tree-sitter");
const LineBuilder = @import("../../parsing/formatter.zig").LineBuilder;
const FormatterOptions = @import("../../parsing/formatter.zig").FormatterOptions;
const NodeUtils = @import("../../language/node_utils.zig").NodeUtils;

// Import all TypeScript formatter modules
const TypeScriptFunctionFormatter = @import("function_formatter.zig").TypeScriptFunctionFormatter;
const TypeScriptInterfaceFormatter = @import("interface_formatter.zig").TypeScriptInterfaceFormatter;
const TypeScriptClassFormatter = @import("class_formatter.zig").TypeScriptClassFormatter;
const TypeScriptTypeFormatter = @import("type_formatter.zig").TypeScriptTypeFormatter;
const TypeScriptImportFormatter = @import("import_formatter.zig").TypeScriptImportFormatter;


/// Format TypeScript using AST-based approach - main entry point
pub fn formatAst(allocator: std.mem.Allocator, node: ts.Node, source: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
    _ = allocator;
    
    // Check if the AST contains only ERROR nodes - if so, fallback to source
    if (isOnlyErrorNodes(node)) {
        try builder.append(source);
        return;
    }
    
    try formatTypeScriptNode(node, source, builder, 0, options);
}

/// TypeScript node formatting with controlled recursion - delegates to specialized formatters
fn formatTypeScriptNode(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) anyerror!void {
    const node_type = node.kind();

    // Dispatch to specialized formatters based on node type
    if (std.mem.eql(u8, node_type, "function_declaration")) {
        try TypeScriptFunctionFormatter.formatFunction(node, source, builder, depth, options);
    } else if (std.mem.eql(u8, node_type, "interface_declaration")) {
        try TypeScriptInterfaceFormatter.formatInterface(node, source, builder, depth, options);
    } else if (std.mem.eql(u8, node_type, "class_declaration")) {
        try TypeScriptClassFormatter.formatClass(node, source, builder, depth, options);
    } else if (std.mem.eql(u8, node_type, "type_alias_declaration")) {
        try TypeScriptTypeFormatter.formatTypeAlias(node, source, builder, depth, options);
    } else if (std.mem.eql(u8, node_type, "variable_declarator") or 
              std.mem.eql(u8, node_type, "lexical_declaration")) {
        try TypeScriptTypeFormatter.formatVariableDeclaration(node, source, builder, depth, options);
    } else if (std.mem.eql(u8, node_type, "import_statement")) {
        try TypeScriptImportFormatter.formatImportStatement(node, source, builder, depth, options);
    } else if (std.mem.eql(u8, node_type, "export_statement")) {
        try TypeScriptImportFormatter.formatExportStatement(node, source, builder, depth, options);
    } else if (std.mem.eql(u8, node_type, "program") or 
              std.mem.eql(u8, node_type, "source_file")) {
        // For container nodes, recurse into children
        try formatContainerNode(node, source, builder, depth, options);
    } else if (std.mem.eql(u8, node_type, "ERROR")) {
        // For ERROR nodes (malformed code), preserve the original text exactly
        try NodeUtils.appendNodeText(node, source, builder);
    } else {
        // For other unknown nodes, just append text without recursion
        try NodeUtils.appendNodeText(node, source, builder);
    }
}

/// Format container nodes (program, source_file) by recursing into children
fn formatContainerNode(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) anyerror!void {
    const child_count = node.childCount();
    var i: u32 = 0;
    
    while (i < child_count) : (i += 1) {
        if (node.child(i)) |child| {
            try formatTypeScriptNode(child, source, builder, depth, options);
        }
    }
}

/// Check if node tree contains only ERROR nodes (failed parse)
fn isOnlyErrorNodes(node: ts.Node) bool {
    const node_type = node.kind();
    
    // If this node is an ERROR, check if the whole tree is errors
    if (std.mem.eql(u8, node_type, "ERROR")) {
        return true;
    }
    
    // For program/source_file nodes, check if all children are errors
    if (std.mem.eql(u8, node_type, "program") or std.mem.eql(u8, node_type, "source_file")) {
        const child_count = node.childCount();
        if (child_count == 0) return false;
        
        var i: u32 = 0;
        while (i < child_count) : (i += 1) {
            if (node.child(i)) |child| {
                if (!std.mem.eql(u8, child.kind(), "ERROR")) {
                    return false;
                }
            }
        }
        return true;
    }
    
    return false;
}