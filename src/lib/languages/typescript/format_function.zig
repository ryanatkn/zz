const std = @import("std");
const ts = @import("tree-sitter");
const LineBuilder = @import("../../parsing/formatter.zig").LineBuilder;
const FormatterOptions = @import("../../parsing/formatter.zig").FormatterOptions;
const NodeUtils = @import("../../language/node_utils.zig").NodeUtils;
const TypeScriptHelpers = @import("formatting_helpers.zig").TypeScriptFormattingHelpers;
const TypeScriptSpacing = @import("spacing_helpers.zig").TypeScriptSpacingHelpers;
const collections = @import("../../core/collections.zig");
const processing = @import("../../text/processing.zig");

pub const FormatFunction = struct {
    /// Format TypeScript function declaration
    pub fn formatFunction(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
        _ = depth;
        
        const func_text = NodeUtils.getNodeText(node, source);
        
        // Check if this is an arrow function
        if (std.mem.indexOf(u8, func_text, "=>") != null) {
            try formatArrowFunction(func_text, builder, options);
        } else {
            try formatRegularFunction(node, source, builder, options);
        }
    }

    /// Format regular function declarations
    fn formatRegularFunction(node: ts.Node, source: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
        const child_count = node.childCount();
        var i: u32 = 0;
        
        var has_async = false;
        var has_export = false;
        var func_name: ?[]const u8 = null;
        var params_node: ?ts.Node = null;
        var return_type_node: ?ts.Node = null;
        var body_node: ?ts.Node = null;
        
        // Parse function components
        while (i < child_count) : (i += 1) {
            if (node.child(i)) |child| {
                const child_type = child.kind();
                
                if (std.mem.eql(u8, child_type, "async")) {
                    has_async = true;
                } else if (std.mem.eql(u8, child_type, "export")) {
                    has_export = true;
                } else if (std.mem.eql(u8, child_type, "identifier")) {
                    func_name = NodeUtils.getNodeText(child, source);
                } else if (std.mem.eql(u8, child_type, "formal_parameters")) {
                    params_node = child;
                } else if (std.mem.eql(u8, child_type, "type_annotation")) {
                    return_type_node = child;
                } else if (std.mem.eql(u8, child_type, "statement_block")) {
                    body_node = child;
                }
            }
        }
        
        // Format function signature
        try builder.appendIndent();
        
        if (has_export) {
            try builder.append("export ");
        }
        
        if (has_async) {
            try builder.append("async ");
        }
        
        try builder.append("function");
        
        if (func_name) |name| {
            try builder.append(" ");
            try builder.append(name);
        }
        
        // Format parameters
        if (params_node) |params| {
            try formatParameters(params, source, builder, options);
        } else {
            try builder.append("()");
        }
        
        // Format return type
        if (return_type_node) |return_type| {
            const return_text = NodeUtils.getNodeText(return_type, source);
            try formatReturnType(return_text, builder);
        }
        
        // Format body
        if (body_node) |body| {
            try builder.append(" {");
            try formatFunctionBody(body, source, builder, options);
            try builder.append("}");
        }
        
        try builder.newline();
    }

    /// Format arrow functions using consolidated helpers
    fn formatArrowFunction(func_text: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
        try builder.appendIndent();
        
        // Use consolidated arrow function helper
        try TypeScriptHelpers.formatArrowFunction(builder.allocator, builder, func_text, options);
        
        try builder.newline();
    }

    /// Format function parameters using consolidated helpers
    fn formatParameters(params_node: ts.Node, source: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
        const params_text = NodeUtils.getNodeText(params_node, source);
        
        // Remove outer parentheses to get content
        var content = params_text;
        if (std.mem.startsWith(u8, content, "(") and std.mem.endsWith(u8, content, ")")) {
            content = content[1..content.len-1];
        }
        
        // Use consolidated parameter list formatter
        try TypeScriptHelpers.formatParameterList(builder.allocator, content, builder, options);
    }



    /// Format single parameter using consolidated spacing helpers
    fn formatSingleParameter(param: []const u8, builder: *LineBuilder) !void {
        try TypeScriptHelpers.formatPropertyWithSpacing(param, builder);
    }

    /// Format return type annotation using consolidated helpers
    fn formatReturnType(return_text: []const u8, builder: *LineBuilder) !void {
        const trimmed = std.mem.trim(u8, return_text, " \t");
        if (trimmed.len > 0) {
            if (!std.mem.startsWith(u8, trimmed, ":")) {
                try builder.append(" ");
            }
            // Use consolidated TypeScript spacing helper
            try TypeScriptHelpers.formatWithTypeScriptSpacing(trimmed, builder);
        }
    }
    

    /// Format function body using consolidated helpers
    fn formatFunctionBody(body_node: ts.Node, source: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
        _ = options;
        
        const body_text = NodeUtils.getNodeText(body_node, source);
        
        // Remove outer braces from statement_block if present
        var content = body_text;
        if (std.mem.startsWith(u8, content, "{") and std.mem.endsWith(u8, content, "}")) {
            content = std.mem.trim(u8, content[1..content.len-1], " \t\n\r");
        }
        
        // Simple body formatting - just add newlines and indentation
        try builder.newline();
        builder.indent();
        
        // Split by lines and format each
        var lines = std.mem.splitSequence(u8, content, "\n");
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t");
            if (trimmed.len > 0) {
                try builder.appendIndent();
                try TypeScriptHelpers.formatWithTypeScriptSpacing(trimmed, builder);
                try builder.newline();
            }
        }
        
        builder.dedent();
        try builder.appendIndent();
    }

    /// Check if node represents a function
    pub fn isFunctionNode(node_type: []const u8) bool {
        return std.mem.eql(u8, node_type, "function_declaration") or
               std.mem.eql(u8, node_type, "arrow_function") or
               std.mem.eql(u8, node_type, "method_definition");
    }
};