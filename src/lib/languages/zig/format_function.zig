const std = @import("std");
const ts = @import("tree-sitter");
const LineBuilder = @import("../../parsing/formatter.zig").LineBuilder;
const FormatterOptions = @import("../../parsing/formatter.zig").FormatterOptions;
const NodeUtils = @import("../../language/node_utils.zig").NodeUtils;
const ZigUtils = @import("zig_utils.zig").ZigUtils;
const FormatParameter = @import("format_parameter.zig").FormatParameter;
const FormatStatement = @import("format_statement.zig").FormatStatement;

/// Zig-specific function formatting functionality
pub const FormatFunction = struct {

    /// Format Zig function node (AST-based)
    pub fn formatFunction(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
        _ = depth;
        const func_text = NodeUtils.getNodeText(node, source);
        try builder.appendIndent();
        try formatFunctionWithSpacing(func_text, builder, options);
    }

    /// Format function with proper spacing
    pub fn formatFunctionWithSpacing(func_text: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
        // Find the function signature and body parts
        if (std.mem.indexOf(u8, func_text, "{")) |brace_pos| {
            const signature = std.mem.trim(u8, func_text[0..brace_pos], " \t");
            const body_start = brace_pos + 1;
            const body_end = std.mem.lastIndexOf(u8, func_text, "}") orelse func_text.len;
            const body = std.mem.trim(u8, func_text[body_start..body_end], " \t\n\r");
            
            // Format signature
            try formatFunctionSignature(signature, builder, options);
            try builder.append(" {");
            
            // Format body if present
            if (body.len > 0) {
                try builder.newline();
                builder.indent();
                try formatFunctionBody(body, builder);
                builder.dedent();
                try builder.appendIndent();
            }
            
            try builder.append("}");
        } else {
            // Function declaration without body
            try formatFunctionSignature(func_text, builder, options);
        }
    }

    /// Format function signature with proper spacing and multiline support
    pub fn formatFunctionSignature(signature: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
        // First handle the pub fn keyword spacing
        if (std.mem.indexOf(u8, signature, "pubfn")) |pos| {
            // Replace "pubfn" with "pub fn"
            try builder.append(signature[0..pos]);
            try builder.append("pub fn");
            
            // Continue with the rest after "pubfn"
            const rest = signature[pos + 5..];
            try formatSignatureWithOptions(rest, builder, options);
            return;
        }
        
        try formatSignatureWithOptions(signature, builder, options);
    }

    /// Format signature with line width awareness and multiline parameter support
    fn formatSignatureWithOptions(signature: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
        // Find function name and parameter section
        if (std.mem.indexOf(u8, signature, "(")) |paren_start| {
            if (std.mem.lastIndexOf(u8, signature, ")")) |paren_end| {
                // Extract parts
                const func_name_part = signature[0..paren_start];
                const params_part = signature[paren_start + 1..paren_end];
                const return_part = if (paren_end + 1 < signature.len) signature[paren_end + 1..] else "";
                
                // Format function name part with proper spacing
                try formatFunctionNamePart(func_name_part, builder);
                
                // Check if we need multiline formatting
                const total_width = func_name_part.len + params_part.len + return_part.len + 2; // +2 for parentheses
                if (total_width > options.line_width and params_part.len > 0) {
                    // Use multiline format
                    try builder.append("(");
                    try builder.newline();
                    builder.indent();
                    
                    try formatParametersMultilineLocal(params_part, builder, options);
                    
                    builder.dedent();
                    try builder.appendIndent();
                    try builder.append(")");
                } else {
                    // Use single line format
                    try builder.append("(");
                    try formatParametersSingleLineLocal(params_part, builder);
                    try builder.append(")");
                }
                
                // Format return type
                if (return_part.len > 0) {
                    try builder.append(" ");
                    try formatReturnType(return_part, builder);
                }
                
                return;
            }
        }
        
        // Fallback - basic formatting without parameter parsing
        try formatBasicSignature(signature, builder);
    }

    /// Format function name part with proper spacing
    fn formatFunctionNamePart(name_part: []const u8, builder: *LineBuilder) !void {
        var i: usize = 0;
        while (i < name_part.len) : (i += 1) {
            const char = name_part[i];
            if (char == ':') {
                try builder.append(&[_]u8{char});
                // Add space after : if not present
                if (i + 1 < name_part.len and name_part[i + 1] != ' ') {
                    try builder.append(" ");
                }
            } else {
                try builder.append(&[_]u8{char});
            }
        }
    }

    /// Format parameters in multiline style
    fn formatParametersMultilineLocal(params: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
        if (params.len == 0) return;
        
        var param_start: usize = 0;
        var depth: i32 = 0;
        var in_string: bool = false;
        var string_char: u8 = 0;
        
        for (params, 0..) |char, i| {
            // Track string boundaries
            if (!in_string and (char == '\'' or char == '"')) {
                in_string = true;
                string_char = char;
            } else if (in_string and char == string_char) {
                in_string = false;
            }
            
            // Skip processing inside strings
            if (in_string) continue;
            
            // Track parentheses depth for nested types
            if (char == '(') {
                depth += 1;
            } else if (char == ')') {
                depth -= 1;
            } else if (char == ',' and depth == 0) {
                // Found parameter boundary
                const param = std.mem.trim(u8, params[param_start..i], " \t\n");
                if (param.len > 0) {
                    try builder.appendIndent();
                    try formatSingleParameter(param, builder);
                    try builder.append(",");
                    try builder.newline();
                }
                param_start = i + 1;
            }
        }
        
        // Handle last parameter
        const last_param = std.mem.trim(u8, params[param_start..], " \t\n");
        if (last_param.len > 0) {
            try builder.appendIndent();
            try formatSingleParameter(last_param, builder);
            if (options.trailing_comma) {
                try builder.append(",");
            }
            try builder.newline();
        }
    }

    /// Format parameters in single line style
    fn formatParametersSingleLineLocal(params: []const u8, builder: *LineBuilder) !void {
        if (params.len == 0) return;
        
        var param_start: usize = 0;
        var depth: i32 = 0;
        var in_string: bool = false;
        var string_char: u8 = 0;
        var first_param = true;
        
        for (params, 0..) |char, i| {
            // Track string boundaries
            if (!in_string and (char == '\'' or char == '"')) {
                in_string = true;
                string_char = char;
            } else if (in_string and char == string_char) {
                in_string = false;
            }
            
            // Skip processing inside strings
            if (in_string) continue;
            
            // Track parentheses depth for nested types
            if (char == '(') {
                depth += 1;
            } else if (char == ')') {
                depth -= 1;
            } else if (char == ',' and depth == 0) {
                // Found parameter boundary
                const param = std.mem.trim(u8, params[param_start..i], " \t\n");
                if (param.len > 0) {
                    if (!first_param) {
                        try builder.append(", ");
                    }
                    try formatSingleParameter(param, builder);
                    first_param = false;
                }
                param_start = i + 1;
            }
        }
        
        // Handle last parameter
        const last_param = std.mem.trim(u8, params[param_start..], " \t\n");
        if (last_param.len > 0) {
            if (!first_param) {
                try builder.append(", ");
            }
            try formatSingleParameter(last_param, builder);
        }
    }

    /// Format single parameter with proper colon spacing
    fn formatSingleParameter(param: []const u8, builder: *LineBuilder) !void {
        return FormatParameter.formatSingleParameter(param, builder);
    }

    /// Format return type with proper spacing
    fn formatReturnType(return_part: []const u8, builder: *LineBuilder) !void {
        const trimmed = std.mem.trim(u8, return_part, " \t");
        if (trimmed.len > 0) {
            try builder.append(trimmed);
        }
    }

    /// Format basic signature without advanced parameter parsing
    fn formatBasicSignature(signature: []const u8, builder: *LineBuilder) !void {
        var i: usize = 0;
        var in_string = false;
        var escape_next = false;

        while (i < signature.len) {
            const c = signature[i];

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

            if (c == '"') {
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

    /// Format function body with proper indentation
    fn formatFunctionBody(body: []const u8, builder: *LineBuilder) !void {
        return FormatStatement.formatFunctionBody(body, builder);
    }

    /// Check if text represents a function declaration
    pub fn isFunctionDecl(text: []const u8) bool {
        // First check if this is a struct/enum/union declaration that happens to contain functions
        if (std.mem.indexOf(u8, text, "struct") != null or
            std.mem.indexOf(u8, text, "enum") != null or
            std.mem.indexOf(u8, text, "union") != null) {
            return false;
        }
        
        // Look for function patterns at the beginning of the declaration
        const trimmed = std.mem.trim(u8, text, " \t\n\r");
        return std.mem.startsWith(u8, trimmed, "fn ") or 
               std.mem.startsWith(u8, trimmed, "pub fn") or
               std.mem.startsWith(u8, trimmed, "inline fn") or
               std.mem.startsWith(u8, trimmed, "export fn") or
               std.mem.startsWith(u8, trimmed, "async fn") or
               std.mem.startsWith(u8, trimmed, "extern fn");
    }
};