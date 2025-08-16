const std = @import("std");
const ts = @import("tree-sitter");
const LineBuilder = @import("../../parsing/formatter.zig").LineBuilder;
const FormatterOptions = @import("../../parsing/formatter.zig").FormatterOptions;
const NodeUtils = @import("../../language/node_utils.zig").NodeUtils;
const ZigUtils = @import("zig_utils.zig").ZigUtils;
const ZigParameterFormatter = @import("parameter_formatter.zig").ZigParameterFormatter;
const ZigStatementFormatter = @import("statement_formatter.zig").ZigStatementFormatter;

/// Zig-specific function formatting functionality
pub const ZigFunctionFormatter = struct {

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

    /// Format function signature with proper parameter handling
    pub fn formatFunctionSignature(signature: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
        // Check for complex signatures that need special handling
        if (shouldUseAdvancedFormatting(signature)) {
            try formatSignatureWithOptions(signature, builder, options);
        } else {
            try formatBasicSignature(signature, builder);
        }
    }

    /// Format signature with parameter parsing and line width awareness
    fn formatSignatureWithOptions(signature: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
        // Find function name and parameters
        if (std.mem.indexOf(u8, signature, "(")) |paren_start| {
            if (std.mem.lastIndexOf(u8, signature, ")")) |paren_end| {
                // Format function name part
                const name_part = std.mem.trim(u8, signature[0..paren_start], " \t");
                try formatFunctionNamePart(name_part, builder);
                
                // Extract parameters and return type
                const params_part = signature[paren_start + 1..paren_end];
                const return_part = if (paren_end + 1 < signature.len) 
                    std.mem.trim(u8, signature[paren_end + 1..], " \t") 
                else 
                    "";
                
                // Decide on parameter formatting style
                if (shouldUseMultilineParams(params_part, options)) {
                    try builder.append("(");
                    try builder.newline();
                    builder.indent();
                    
                    try formatParametersMultiline(params_part, builder, options);
                    
                    builder.dedent();
                    try builder.appendIndent();
                    try builder.append(")");
                } else {
                    // Use single line format
                    try builder.append("(");
                    try formatParametersSingleLine(params_part, builder);
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
        try ZigUtils.formatDeclarationWithSpacing(name_part, builder);
    }

    /// Format parameters in multiline style
    fn formatParametersMultiline(params: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
        if (params.len == 0) return;
        
        const param_list = try ZigUtils.splitByDelimiter(builder.allocator, params, ',');
        defer builder.allocator.free(param_list);
        
        for (param_list, 0..) |param, i| {
            const trimmed = std.mem.trim(u8, param, " \t\n\r");
            if (trimmed.len > 0) {
                try builder.appendIndent();
                try ZigParameterFormatter.formatSingleParameter(trimmed, builder);
                if (i < param_list.len - 1) {
                    try builder.append(",");
                }
                if (options.trailing_comma and i == param_list.len - 1) {
                    try builder.append(",");
                }
                try builder.newline();
            }
        }
    }

    /// Format parameters in single line style
    fn formatParametersSingleLine(params: []const u8, builder: *LineBuilder) !void {
        if (params.len == 0) return;
        
        const param_list = try ZigUtils.splitByDelimiter(builder.allocator, params, ',');
        defer builder.allocator.free(param_list);
        
        for (param_list, 0..) |param, i| {
            const trimmed = std.mem.trim(u8, param, " \t\n\r");
            if (trimmed.len > 0) {
                try ZigParameterFormatter.formatSingleParameter(trimmed, builder);
                if (i < param_list.len - 1) {
                    try builder.append(", ");
                }
            }
        }
    }

    /// Format return type with proper spacing
    fn formatReturnType(return_part: []const u8, builder: *LineBuilder) !void {
        const trimmed = std.mem.trim(u8, return_part, " \t");
        if (trimmed.len > 0) {
            try builder.append(trimmed);
        }
    }

    /// Fallback basic signature formatting
    fn formatBasicSignature(signature: []const u8, builder: *LineBuilder) !void {
        try ZigUtils.formatDeclarationWithSpacing(signature, builder);
    }

    /// Format function body with proper indentation
    fn formatFunctionBody(body: []const u8, builder: *LineBuilder) !void {
        // Split body into statements and format each
        const statements = try splitIntoStatements(builder.allocator, body);
        defer {
            for (statements) |stmt| {
                builder.allocator.free(stmt);
            }
            builder.allocator.free(statements);
        }
        
        for (statements, 0..) |statement, i| {
            const trimmed = std.mem.trim(u8, statement, " \t\n\r");
            if (trimmed.len > 0) {
                try builder.appendIndent();
                try ZigStatementFormatter.formatStatement(trimmed, builder);
                try builder.newline();
                
                // Add spacing between different types of statements
                if (i < statements.len - 1 and shouldAddSpacingAfterStatement(trimmed)) {
                    try builder.newline();
                }
            }
        }
    }

    /// Check if signature should use advanced formatting
    fn shouldUseAdvancedFormatting(signature: []const u8) bool {
        // Use advanced formatting for complex signatures
        return std.mem.indexOf(u8, signature, "comptime") != null or
               std.mem.indexOf(u8, signature, "anytype") != null or
               signature.len > 50; // Arbitrary threshold
    }

    /// Check if parameters should use multiline format
    fn shouldUseMultilineParams(params_part: []const u8, options: FormatterOptions) bool {
        if (params_part.len == 0) return false;
        
        // Count commas to estimate parameter count
        var comma_count: u32 = 0;
        for (params_part) |char| {
            if (char == ',') comma_count += 1;
        }
        
        // Use multiline if more than 2 parameters or total length exceeds limit
        return comma_count > 1 or params_part.len > options.line_width - 20;
    }

    /// Split function body into statements
    fn splitIntoStatements(allocator: std.mem.Allocator, body: []const u8) ![][]const u8 {
        var statements = std.ArrayList([]const u8).init(allocator);
        defer statements.deinit();
        
        var start: usize = 0;
        var brace_depth: i32 = 0;
        var in_string: bool = false;
        var string_char: u8 = 0;
        
        for (body, 0..) |char, i| {
            // Handle string boundaries
            if (!in_string and (char == '"' or char == '\'')) {
                in_string = true;
                string_char = char;
            } else if (in_string and char == string_char) {
                in_string = false;
            }
            
            if (!in_string) {
                switch (char) {
                    '{' => brace_depth += 1,
                    '}' => brace_depth -= 1,
                    ';' => {
                        if (brace_depth == 0) {
                            const stmt = std.mem.trim(u8, body[start..i], " \t\n\r");
                            if (stmt.len > 0) {
                                try statements.append(try allocator.dupe(u8, stmt));
                            }
                            start = i + 1;
                        }
                    },
                    '\n' => {
                        // Handle statements that don't end with semicolon
                        if (brace_depth == 0 and i > start) {
                            const potential_stmt = std.mem.trim(u8, body[start..i], " \t\n\r");
                            if (potential_stmt.len > 0 and !std.mem.endsWith(u8, potential_stmt, ",")) {
                                // Check if this looks like a complete statement
                                if (isCompleteStatement(potential_stmt)) {
                                    try statements.append(try allocator.dupe(u8, potential_stmt));
                                    start = i + 1;
                                }
                            }
                        }
                    },
                    else => {},
                }
            }
        }
        
        // Handle final statement
        if (start < body.len) {
            const final_stmt = std.mem.trim(u8, body[start..], " \t\n\r");
            if (final_stmt.len > 0) {
                try statements.append(try allocator.dupe(u8, final_stmt));
            }
        }
        
        return statements.toOwnedSlice();
    }

    /// Check if text represents a complete statement
    fn isCompleteStatement(text: []const u8) bool {
        const trimmed = std.mem.trim(u8, text, " \t\n\r");
        return std.mem.startsWith(u8, trimmed, "return ") or
               std.mem.startsWith(u8, trimmed, "if ") or
               std.mem.startsWith(u8, trimmed, "while ") or
               std.mem.startsWith(u8, trimmed, "for ") or
               std.mem.indexOf(u8, trimmed, " = ") != null;
    }

    /// Check if spacing should be added after this statement
    fn shouldAddSpacingAfterStatement(statement: []const u8) bool {
        const trimmed = std.mem.trim(u8, statement, " \t\n\r");
        return std.mem.startsWith(u8, trimmed, "const ") or
               std.mem.startsWith(u8, trimmed, "var ") or
               std.mem.indexOf(u8, trimmed, "struct") != null or
               std.mem.indexOf(u8, trimmed, "enum") != null;
    }
};