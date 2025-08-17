const std = @import("std");
const ts = @import("tree-sitter");
const LineBuilder = @import("../../parsing/formatter.zig").LineBuilder;
const FormatterOptions = @import("../../parsing/formatter.zig").FormatterOptions;
const NodeUtils = @import("../../language/node_utils.zig").NodeUtils;
const TypeScriptHelpers = @import("formatting_helpers.zig").TypeScriptFormattingHelpers;
const builders = @import("../../text/builders.zig");
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

    /// Format arrow functions
    fn formatArrowFunction(func_text: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
        // Find the arrow position
        if (std.mem.indexOf(u8, func_text, "=>")) |arrow_pos| {
            const signature_part = std.mem.trim(u8, func_text[0..arrow_pos], " \t");
            const body_part = std.mem.trim(u8, func_text[arrow_pos + 2..], " \t");
            
            try builder.appendIndent();
            try builder.append(signature_part);
            try builder.append(" => ");
            
            // Check if body is a block or expression
            if (std.mem.startsWith(u8, body_part, "{")) {
                try builder.append(body_part);
            } else {
                // Single expression - check line length
                if (signature_part.len + body_part.len + 4 > options.line_width) {
                    try builder.newline();
                    builder.indent();
                    try builder.appendIndent();
                    try builder.append(body_part);
                    builder.dedent();
                } else {
                    try builder.append(body_part);
                }
            }
        } else {
            // Fallback - just append the text
            try builder.appendIndent();
            try builder.append(func_text);
        }
        
        try builder.newline();
    }

    /// Format function parameters
    fn formatParameters(params_node: ts.Node, source: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
        const params_text = NodeUtils.getNodeText(params_node, source);
        
        // Remove outer parentheses to check content length
        var content = params_text;
        if (std.mem.startsWith(u8, content, "(") and std.mem.endsWith(u8, content, ")")) {
            content = content[1..content.len-1];
        }
        
        // Estimate the current line length (approximation based on current buffer content)
        // Look for the last newline to estimate current line length
        var current_line_length: usize = 0;
        if (builder.buffer.items.len > 0) {
            if (std.mem.lastIndexOf(u8, builder.buffer.items, "\n")) |last_newline| {
                current_line_length = builder.buffer.items.len - last_newline - 1;
            } else {
                current_line_length = builder.buffer.items.len;
            }
        }
        
        const total_length = current_line_length + content.len + 2; // +2 for parentheses
        
        // Check if we need multiline formatting based on line width
        if (total_length > options.line_width and content.len > 0) {
            try formatParametersMultiline(content, builder, options);
        } else {
            try formatParametersSingleLine(content, builder);
        }
    }

    /// Format parameters in multiline style
    fn formatParametersMultiline(content: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
        _ = options;
        
        if (content.len == 0) {
            try builder.append("()");
            return;
        }
        
        try builder.append("(");
        try builder.newline();
        builder.indent();
        
        // Split parameters by comma using common utility
        const params = try processing.splitAndTrim(builder.allocator, content, ',');
        defer {
            for (params) |param| {
                builder.allocator.free(param);
            }
            builder.allocator.free(params);
        }
        
        for (params, 0..) |param, i| {
            if (i > 0) {
                try builder.append(",");
                try builder.newline();
            }
            try builder.appendIndent();
            try formatSingleParameter(param, builder);
        }
        
        try builder.newline();
        builder.dedent();
        try builder.appendIndent();
        try builder.append(")");
    }

    /// Format parameters in single line style
    fn formatParametersSingleLine(content: []const u8, builder: *LineBuilder) !void {
        try builder.append("(");
        
        if (content.len > 0) {
            // Split parameters by comma using common utility
            const params = try processing.splitAndTrim(builder.allocator, content, ',');
            defer {
                for (params) |param| {
                    builder.allocator.free(param);
                }
                builder.allocator.free(params);
            }
            
            for (params, 0..) |param, i| {
                if (i > 0) {
                    try builder.append(", ");
                }
                try formatSingleParameter(param, builder);
            }
        }
        
        try builder.append(")");
    }

    /// Format single parameter with TypeScript-style spacing
    fn formatSingleParameter(param: []const u8, builder: *LineBuilder) !void {
        var i: usize = 0;
        var in_string = false;
        var escape_next = false;

        while (i < param.len) {
            const c = param[i];

            if (escape_next) {
                try builder.append(&[_]u8{c});
                escape_next = false;
                i += 1;
                continue;
            }

            if (c == '\\' and in_string) {
                escape_next = true;
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            if (c == '"' or c == '\'') {
                in_string = !in_string;
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            if (in_string) {
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            if (c == ':') {
                // TypeScript style: no space before colon, space after colon
                try builder.append(":");
                i += 1;
                
                // Ensure space after colon
                if (i < param.len and param[i] != ' ') {
                    try builder.append(" ");
                }
                continue;
            }

            if (c == ' ') {
                // Only add space if we haven't just added one
                if (builder.buffer.items.len > 0 and
                    builder.buffer.items[builder.buffer.items.len - 1] != ' ') {
                    try builder.append(" ");
                }
                i += 1;
                continue;
            }

            try builder.append(&[_]u8{c});
            i += 1;
        }
    }

    /// Format return type annotation
    fn formatReturnType(return_text: []const u8, builder: *LineBuilder) !void {
        var trimmed = std.mem.trim(u8, return_text, " \t");
        if (trimmed.len > 0) {
            // Handle TypeScript return type formatting:
            // The return_text may start with colon, so we need to format it properly
            if (std.mem.startsWith(u8, trimmed, ":")) {
                // Add colon with proper spacing
                try builder.append(": ");
                trimmed = std.mem.trim(u8, trimmed[1..], " \t");
            } else {
                // No colon present, just add space
                try builder.append(" ");
            }
            
            // Format union types with proper spacing
            try formatTypeWithSpacing(trimmed, builder);
        }
    }
    
    /// Format type with proper spacing for union types
    fn formatTypeWithSpacing(type_text: []const u8, builder: *LineBuilder) !void {
        var i: usize = 0;
        var in_angle_brackets: u32 = 0;
        
        while (i < type_text.len) {
            const c = type_text[i];
            
            if (c == '<') {
                in_angle_brackets += 1;
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }
            
            if (c == '>') {
                if (in_angle_brackets > 0) {
                    in_angle_brackets -= 1;
                }
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }
            
            // Format union types with spacing: User | null instead of User|null
            if (c == '|') {
                // Add space before if not already present
                if (builder.buffer.items.len > 0 and 
                    builder.buffer.items[builder.buffer.items.len - 1] != ' ') {
                    try builder.append(" ");
                }
                try builder.append("|");
                i += 1;
                // Add space after
                if (i < type_text.len and type_text[i] != ' ') {
                    try builder.append(" ");
                }
                continue;
            }
            
            try builder.append(&[_]u8{c});
            i += 1;
        }
    }

    /// Format function body
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
        
        // Use common line processing utility
        const ProcessLineCtx = struct {
            builder: *LineBuilder,
        };
        const ctx = ProcessLineCtx{ .builder = builder };
        
        processing.processLinesWithState(
            ProcessLineCtx,
            content,
            ctx,
            struct {
                fn processLine(context: ProcessLineCtx, line: []const u8) void {
                    const trimmed = std.mem.trim(u8, line, " \t");
                    if (trimmed.len > 0) {
                        context.builder.appendIndent() catch return;
                        context.builder.append(trimmed) catch return;
                        context.builder.newline() catch return;
                    }
                }
            }.processLine,
        );
        
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