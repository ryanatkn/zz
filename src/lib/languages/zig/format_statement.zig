const std = @import("std");
const LineBuilder = @import("../../parsing/formatter.zig").LineBuilder;
const FormatDeclaration = @import("format_declaration.zig").FormatDeclaration;
const FormatBody = @import("format_body.zig").FormatBody;

/// Zig-specific statement formatting functionality
pub const FormatStatement = struct {

    /// Format function body with proper statement formatting
    pub fn formatFunctionBody(body: []const u8, builder: *LineBuilder) !void {
        // Simple function body formatting - delegate to statement formatting
        try formatStatement(body, builder);
        try builder.newline();
    }

    /// Format Zig statement with proper spacing
    pub fn formatStatement(statement: []const u8, builder: *LineBuilder) !void {
        const trimmed = std.mem.trim(u8, statement, " \t\n\r");
        
        // Handle different types of statements
        if (std.mem.startsWith(u8, trimmed, "return ")) {
            try formatReturnStatement(statement, builder);
        } else if (std.mem.indexOf(u8, trimmed, " = ") != null) {
            try formatAssignmentStatement(statement, builder);
        } else if (std.mem.startsWith(u8, trimmed, "if ") or 
                   std.mem.startsWith(u8, trimmed, "while ") or
                   std.mem.startsWith(u8, trimmed, "for ")) {
            try formatControlFlowStatement(statement, builder);
        } else if (std.mem.startsWith(u8, trimmed, "switch ")) {
            try formatSwitchStatement(statement, builder);
        } else {
            // Generic statement formatting
            try formatGenericStatement(statement, builder);
        }
    }

    /// Format return statement with struct support
    pub fn formatReturnWithStruct(allocator: std.mem.Allocator, builder: *LineBuilder, statement: []const u8) !void {
        // Check for struct type definition vs struct literal
        if (std.mem.indexOf(u8, statement, "return struct")) |_| {
            try formatStructTypeReturn(allocator, builder, statement);
        } else {
            try formatStructLiteralReturn(allocator, builder, statement);
        }
    }

    /// Format test declaration with proper spacing
    pub fn formatTestDeclaration(test_text: []const u8, builder: *LineBuilder) !void {
        const trimmed = std.mem.trim(u8, test_text, " \t\n\r");
        
        // Find the test name and body
        if (std.mem.indexOf(u8, trimmed, "{")) |brace_pos| {
            const test_decl = std.mem.trim(u8, trimmed[0..brace_pos], " \t");
            try formatTestSignature(test_decl, builder);
            try builder.append(" {");
            
            const body_end = std.mem.lastIndexOf(u8, trimmed, "}") orelse trimmed.len;
            const body = std.mem.trim(u8, trimmed[brace_pos + 1..body_end], " \t\n\r");
            
            if (body.len > 0) {
                try builder.newline();
                builder.indent();
                try formatTestBody(body, builder);
                builder.dedent();
                try builder.appendIndent();
            }
            
            try builder.append("}");
        } else {
            // Just format the declaration part
            try formatTestSignature(trimmed, builder);
        }
    }

    /// Format import statement with proper spacing
    pub fn formatImportStatement(import_text: []const u8, builder: *LineBuilder) !void {
        const trimmed = std.mem.trim(u8, import_text, " \t\n\r");
        
        // Find the assignment and @import parts
        if (std.mem.indexOf(u8, trimmed, " = ")) |equals_pos| {
            const var_part = std.mem.trim(u8, trimmed[0..equals_pos], " \t");
            const import_part = std.mem.trim(u8, trimmed[equals_pos + 3..], " \t");
            
            try FormatDeclaration.formatDeclaration(var_part, builder);
            try builder.append(" = ");
            try builder.append(import_part);
        } else {
            // Fallback: just trim and append
            try builder.append(trimmed);
        }
    }

    /// Format variable declaration with proper spacing
    pub fn formatVariableDeclaration(var_text: []const u8, builder: *LineBuilder) !void {
        const trimmed = std.mem.trim(u8, var_text, " \t\n\r");
        
        // Handle different variable declaration patterns
        if (std.mem.indexOf(u8, trimmed, " = ")) |equals_pos| {
            const decl_part = std.mem.trim(u8, trimmed[0..equals_pos], " \t");
            const value_part = std.mem.trim(u8, trimmed[equals_pos + 3..], " \t");
            
            try FormatDeclaration.formatDeclaration(decl_part, builder);
            try builder.append(" = ");
            try formatExpression(value_part, builder);
        } else {
            // Declaration without assignment
            try FormatDeclaration.formatDeclaration(trimmed, builder);
        }
    }

    /// Format return statement
    fn formatReturnStatement(statement: []const u8, builder: *LineBuilder) !void {
        const trimmed = std.mem.trim(u8, statement, " \t\n\r");
        
        if (std.mem.startsWith(u8, trimmed, "return ")) {
            try builder.append("return ");
            const return_value = std.mem.trim(u8, trimmed[7..], " \t");
            try formatExpression(return_value, builder);
        } else {
            try builder.append(trimmed);
        }
    }

    /// Format assignment statement
    fn formatAssignmentStatement(statement: []const u8, builder: *LineBuilder) !void {
        const trimmed = std.mem.trim(u8, statement, " \t\n\r");
        
        if (std.mem.indexOf(u8, trimmed, " = ")) |equals_pos| {
            const lhs = std.mem.trim(u8, trimmed[0..equals_pos], " \t");
            const rhs = std.mem.trim(u8, trimmed[equals_pos + 3..], " \t");
            
            try builder.append(lhs);
            try builder.append(" = ");
            try formatExpression(rhs, builder);
        } else {
            try builder.append(trimmed);
        }
    }

    /// Format control flow statement (if, while, for)
    fn formatControlFlowStatement(statement: []const u8, builder: *LineBuilder) !void {
        const trimmed = std.mem.trim(u8, statement, " \t\n\r");
        
        // Find the condition part and body
        if (std.mem.indexOf(u8, trimmed, "{")) |brace_pos| {
            const control_part = std.mem.trim(u8, trimmed[0..brace_pos], " \t");
            try formatControlPart(control_part, builder);
            try builder.append(" {");
            
            const body_end = std.mem.lastIndexOf(u8, trimmed, "}") orelse trimmed.len;
            const body = std.mem.trim(u8, trimmed[brace_pos + 1..body_end], " \t\n\r");
            
            if (body.len > 0) {
                try builder.newline();
                builder.indent();
                try formatStatementBody(body, builder);
                builder.dedent();
                try builder.appendIndent();
            }
            
            try builder.append("}");
        } else {
            // Just format the control part
            try formatControlPart(trimmed, builder);
        }
    }

    /// Format switch statement with special handling
    fn formatSwitchStatement(statement: []const u8, builder: *LineBuilder) !void {
        const trimmed = std.mem.trim(u8, statement, " \t\n\r");
        
        // Find switch expression and body
        if (std.mem.indexOf(u8, trimmed, "{")) |brace_pos| {
            const switch_part = std.mem.trim(u8, trimmed[0..brace_pos], " \t");
            try formatSwitchExpression(switch_part, builder);
            try builder.append(" {");
            
            const body_end = std.mem.lastIndexOf(u8, trimmed, "}") orelse trimmed.len;
            const body = std.mem.trim(u8, trimmed[brace_pos + 1..body_end], " \t\n\r");
            
            if (body.len > 0) {
                try builder.newline();
                builder.indent();
                try formatSwitchBody(body, builder);
                builder.dedent();
                try builder.appendIndent();
            }
            
            try builder.append("}");
        } else {
            try builder.append(trimmed);
        }
    }

    /// Format generic statement
    fn formatGenericStatement(statement: []const u8, builder: *LineBuilder) !void {
        const trimmed = std.mem.trim(u8, statement, " \t\n\r");
        
        // Add proper indentation
        try builder.appendIndent();
        
        // Format with proper spacing
        try formatStatementWithSpacing(trimmed, builder);
    }
    
    /// Format statement with proper spacing around operators and punctuation
    fn formatStatementWithSpacing(statement: []const u8, builder: *LineBuilder) !void {
        var i: usize = 0;
        var in_string = false;
        var string_char: u8 = 0;
        
        while (i < statement.len) {
            const c = statement[i];
            
            // Handle string boundaries
            if (!in_string and (c == '"' or c == '\'')) {
                in_string = true;
                string_char = c;
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            } else if (in_string and c == string_char) {
                in_string = false;
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            } else if (in_string) {
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }
            
            // Format spacing around special characters
            if (c == ',' and i + 1 < statement.len) {
                try builder.append(",");
                // Add space after comma if not already there
                if (statement[i + 1] != ' ') {
                    try builder.append(" ");
                }
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

    /// Format return statement with struct type definition
    fn formatStructTypeReturn(allocator: std.mem.Allocator, builder: *LineBuilder, statement: []const u8) !void {
        if (std.mem.indexOf(u8, statement, "{")) |brace_start| {
            // Format "return struct"
            const return_part = std.mem.trim(u8, statement[0..brace_start], " \t");
            try FormatDeclaration.formatDeclaration(return_part, builder);
            try builder.append(" {");
            try builder.newline();
            
            // Extract and format struct body
            const struct_end = std.mem.lastIndexOf(u8, statement, "}") orelse statement.len;
            const struct_content = std.mem.trim(u8, statement[brace_start + 1..struct_end], " \t\n\r");
            
            if (struct_content.len > 0) {
                builder.indent();
                try FormatBody.formatStructBody(allocator, builder, struct_content);
                builder.dedent();
            }
            
            try builder.appendIndent();
            try builder.append("}");
        }
    }

    /// Format return statement with struct literal
    fn formatStructLiteralReturn(allocator: std.mem.Allocator, builder: *LineBuilder, statement: []const u8) !void {
        if (std.mem.indexOf(u8, statement, "{")) |brace_start| {
            const return_part = std.mem.trim(u8, statement[0..brace_start], " \t");
            try FormatDeclaration.formatDeclaration(return_part, builder);
            
            const struct_end = std.mem.lastIndexOf(u8, statement, "}") orelse statement.len;
            const struct_content = std.mem.trim(u8, statement[brace_start + 1..struct_end], " \t\n\r");
            
            if (struct_content.len > 0) {
                try builder.append("{");
                try builder.newline();
                builder.indent();
                
                // Format struct literal fields with proper spacing
                try FormatBody.formatStructLiteralContent(allocator, builder, struct_content);
                
                builder.dedent();
                try builder.appendIndent();
                try builder.append("}");
            } else {
                try builder.append("{}");
            }
        }
    }

    /// Format test signature
    fn formatTestSignature(test_decl: []const u8, builder: *LineBuilder) !void {
        // Test declarations like "test "test name""
        if (std.mem.startsWith(u8, test_decl, "test ")) {
            try builder.append("test ");
            const test_name = std.mem.trim(u8, test_decl[5..], " \t");
            try builder.append(test_name);
        } else {
            try builder.append(test_decl);
        }
    }

    /// Format test body
    fn formatTestBody(body: []const u8, builder: *LineBuilder) !void {
        // Simple body formatting - could be enhanced for specific test patterns
        try builder.appendIndent();
        try builder.append(std.mem.trim(u8, body, " \t\n\r"));
        try builder.newline();
    }

    /// Format control flow part (condition)
    fn formatControlPart(control_part: []const u8, builder: *LineBuilder) !void {
        // Add proper spacing around keywords and parentheses
        var i: usize = 0;
        while (i < control_part.len) : (i += 1) {
            const char = control_part[i];
            if (char == '(') {
                try builder.append("(");
            } else if (char == ')') {
                try builder.append(")");
            } else {
                try builder.append(&[_]u8{char});
            }
        }
    }

    /// Format statement body
    fn formatStatementBody(body: []const u8, builder: *LineBuilder) !void {
        // Simple body formatting
        try builder.appendIndent();
        try builder.append(std.mem.trim(u8, body, " \t\n\r"));
        try builder.newline();
    }

    /// Format switch expression
    fn formatSwitchExpression(switch_part: []const u8, builder: *LineBuilder) !void {
        try builder.append(std.mem.trim(u8, switch_part, " \t"));
    }

    /// Format switch body
    fn formatSwitchBody(body: []const u8, builder: *LineBuilder) !void {
        // Could be enhanced to handle switch cases properly
        try builder.appendIndent();
        try builder.append(std.mem.trim(u8, body, " \t\n\r"));
        try builder.newline();
    }

    /// Format expression
    fn formatExpression(expression: []const u8, builder: *LineBuilder) !void {
        try builder.append(std.mem.trim(u8, expression, " \t"));
    }
};