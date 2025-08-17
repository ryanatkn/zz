const std = @import("std");
const ts = @import("tree-sitter");
const LineBuilder = @import("../../parsing/formatter.zig").LineBuilder;
const FormatterOptions = @import("../../parsing/formatter.zig").FormatterOptions;
const NodeUtils = @import("../../language/node_utils.zig").NodeUtils;

pub const FormatType = struct {
    /// Format TypeScript type alias declaration
    pub fn formatTypeAlias(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
        _ = depth;
        _ = options;
        
        const child_count = node.childCount();
        var i: u32 = 0;
        
        var has_export = false;
        var type_name: ?[]const u8 = null;
        var generic_params: ?[]const u8 = null;
        var type_definition: ?[]const u8 = null;
        
        // Parse type alias components
        while (i < child_count) : (i += 1) {
            if (node.child(i)) |child| {
                const child_type = child.kind();
                const child_text = NodeUtils.getNodeText(child, source);
                
                if (std.mem.eql(u8, child_type, "export")) {
                    has_export = true;
                } else if (std.mem.eql(u8, child_type, "identifier")) {
                    if (type_name == null) {
                        type_name = child_text;
                    }
                } else if (std.mem.eql(u8, child_type, "type_parameters")) {
                    generic_params = child_text;
                } else if (std.mem.indexOf(u8, child_type, "type") != null) {
                    type_definition = child_text;
                }
            }
        }
        
        // Format type alias declaration
        try builder.appendIndent();
        
        if (has_export) {
            try builder.append("export ");
        }
        
        try builder.append("type");
        
        if (type_name) |name| {
            try builder.append(" ");
            try builder.append(name);
        }
        
        // Add generic parameters
        if (generic_params) |generics| {
            try formatGenericParameters(generics, builder);
        }
        
        try builder.append(" =");
        
        // Format type definition
        if (type_definition) |type_def| {
            try builder.append(" ");
            try formatTypeDefinition(type_def, builder);
        }
        
        try builder.append(";");
        try builder.newline();
        try builder.newline();
    }

    /// Format variable declaration (including arrow functions)
    pub fn formatVariableDeclaration(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
        _ = depth;
        
        const var_text = NodeUtils.getNodeText(node, source);
        
        // Check if this contains an arrow function
        if (std.mem.indexOf(u8, var_text, "=>") != null) {
            try formatArrowFunctionDeclaration(var_text, builder, options);
        } else {
            try formatSimpleVariableDeclaration(var_text, builder);
        }
    }

    /// Format arrow function variable declaration
    fn formatArrowFunctionDeclaration(var_text: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
        try builder.appendIndent();
        
        // Find key positions
        if (std.mem.indexOf(u8, var_text, "=>")) |arrow_pos| {
            const before_arrow = std.mem.trim(u8, var_text[0..arrow_pos], " \t");
            const after_arrow = std.mem.trim(u8, var_text[arrow_pos + 2..], " \t");
            
            // Format the part before arrow
            try formatTypeDeclaration(before_arrow, builder);
            try builder.append(" => ");
            
            // Format the part after arrow (function body)
            if (std.mem.startsWith(u8, after_arrow, "{")) {
                // Block body
                try formatTypeBlockBody(after_arrow, builder, options);
            } else {
                // Expression body - check for method chaining
                if (std.mem.indexOf(u8, after_arrow, ".") != null and 
                    (before_arrow.len + after_arrow.len + 4 > options.line_width or
                     std.mem.indexOf(u8, after_arrow, ").") != null)) {
                    // Method chaining detected or line too long
                    try builder.newline();
                    builder.indent();
                    try formatMethodChain(after_arrow, builder, options);
                    builder.dedent();
                } else {
                    // Simple expression
                    if (before_arrow.len + after_arrow.len + 4 > options.line_width) {
                        try builder.newline();
                        builder.indent();
                        try builder.appendIndent();
                        try formatArrowFunctionExpression(after_arrow, builder);
                        builder.dedent();
                    } else {
                        try formatArrowFunctionExpression(after_arrow, builder);
                    }
                }
            }
        } else {
            // Fallback
            try formatTypeDeclaration(var_text, builder);
        }
        
        try builder.newline();
    }

    /// Format simple variable declaration
    fn formatSimpleVariableDeclaration(var_text: []const u8, builder: *LineBuilder) !void {
        try builder.appendIndent();
        try formatTypeDeclaration(var_text, builder);
        try builder.newline();
    }

    /// Format type declaration with proper spacing
    fn formatTypeDeclaration(declaration: []const u8, builder: *LineBuilder) !void {
        var i: usize = 0;
        var in_string = false;
        var string_char: u8 = 0;
        var escape_next = false;
        var in_generic = false;
        var generic_depth: u32 = 0;

        while (i < declaration.len) {
            const c = declaration[i];

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

            if (!in_string and (c == '"' or c == '\'' or c == '`')) {
                in_string = true;
                string_char = c;
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            if (in_string and c == string_char) {
                in_string = false;
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            if (in_string) {
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            // Track generic type parameters
            if (c == '<') {
                in_generic = true;
                generic_depth += 1;
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            if (c == '>') {
                if (generic_depth > 0) {
                    generic_depth -= 1;
                    if (generic_depth == 0) {
                        in_generic = false;
                    }
                }
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            if (c == ':' and !in_generic) {
                // TypeScript style: no space before colon, space after
                // Remove any trailing space before colon
                if (builder.buffer.items.len > 0 and 
                    builder.buffer.items[builder.buffer.items.len - 1] == ' ') {
                    _ = builder.buffer.pop();
                }
                try builder.append(": ");
                i += 1;
                
                // Skip any spaces after colon in original
                while (i < declaration.len and declaration[i] == ' ') {
                    i += 1;
                }
                continue;
            }

            if (c == '=') {
                // Ensure space around assignment
                if (builder.buffer.items.len > 0 and 
                    builder.buffer.items[builder.buffer.items.len - 1] != ' ') {
                    try builder.append(" ");
                }
                try builder.append("=");
                i += 1;
                
                // Ensure space after equals
                if (i < declaration.len and declaration[i] != ' ') {
                    try builder.append(" ");
                }
                continue;
            }

            if (c == '|' or c == '&') {
                // Ensure space around union and intersection types
                if (builder.buffer.items.len > 0 and 
                    builder.buffer.items[builder.buffer.items.len - 1] != ' ') {
                    try builder.append(" ");
                }
                try builder.append(&[_]u8{c});
                i += 1;
                
                // Ensure space after operator
                if (i < declaration.len and declaration[i] != ' ') {
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

    /// Format type definition (right side of type alias)
    fn formatTypeDefinition(type_def: []const u8, builder: *LineBuilder) !void {
        // Handle union types, object types, etc.
        if (std.mem.indexOf(u8, type_def, "|") != null) {
            try formatUnionType(type_def, builder);
        } else if (std.mem.indexOf(u8, type_def, "&") != null) {
            try formatIntersectionType(type_def, builder);
        } else if (std.mem.startsWith(u8, type_def, "{")) {
            try formatObjectType(type_def, builder);
        } else {
            try formatSimpleType(type_def, builder);
        }
    }

    /// Format union type (A | B | C)
    fn formatUnionType(union_type: []const u8, builder: *LineBuilder) !void {
        var parts = std.mem.splitSequence(u8, union_type, "|");
        var first = true;
        
        while (parts.next()) |part| {
            const trimmed = std.mem.trim(u8, part, " \t");
            if (trimmed.len > 0) {
                if (!first) {
                    try builder.append(" | ");
                }
                try builder.append(trimmed);
                first = false;
            }
        }
    }

    /// Format intersection type (A & B & C)
    fn formatIntersectionType(intersection_type: []const u8, builder: *LineBuilder) !void {
        var parts = std.mem.splitSequence(u8, intersection_type, "&");
        var first = true;
        
        while (parts.next()) |part| {
            const trimmed = std.mem.trim(u8, part, " \t");
            if (trimmed.len > 0) {
                if (!first) {
                    try builder.append(" & ");
                }
                try builder.append(trimmed);
                first = false;
            }
        }
    }

    /// Format object type ({ key: value })
    fn formatObjectType(object_type: []const u8, builder: *LineBuilder) !void {
        // Simple approach - just clean up spacing
        try formatSimpleType(object_type, builder);
    }

    /// Format simple type with basic spacing
    fn formatSimpleType(simple_type: []const u8, builder: *LineBuilder) !void {
        var i: usize = 0;
        var in_string = false;
        var string_char: u8 = 0;
        var prev_was_space = false;

        while (i < simple_type.len) {
            const c = simple_type[i];

            if (!in_string and (c == '"' or c == '\'' or c == '`')) {
                in_string = true;
                string_char = c;
                try builder.append(&[_]u8{c});
                prev_was_space = false;
            } else if (in_string and c == string_char) {
                in_string = false;
                try builder.append(&[_]u8{c});
                prev_was_space = false;
            } else if (in_string) {
                try builder.append(&[_]u8{c});
                prev_was_space = false;
            } else if (c == ' ') {
                if (!prev_was_space) {
                    try builder.append(" ");
                    prev_was_space = true;
                }
            } else {
                try builder.append(&[_]u8{c});
                prev_was_space = false;
            }

            i += 1;
        }
    }

    /// Format block body for functions
    fn formatTypeBlockBody(body: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
        _ = options;
        
        try builder.append("{");
        
        // Simple body formatting
        var lines = std.mem.splitSequence(u8, body, "\n");
        var has_content = false;
        
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t");
            if (trimmed.len > 0 and !std.mem.eql(u8, trimmed, "{") and !std.mem.eql(u8, trimmed, "}")) {
                if (!has_content) {
                    try builder.newline();
                    builder.indent();
                    has_content = true;
                }
                try builder.appendIndent();
                try builder.append(trimmed);
                try builder.newline();
            }
        }
        
        if (has_content) {
            builder.dedent();
            try builder.appendIndent();
        }
        
        try builder.append("}");
    }

    /// Format generic parameters
    fn formatGenericParameters(type_params: []const u8, builder: *LineBuilder) !void {
        try builder.append(type_params);
    }

    /// Check if node represents a type alias
    pub fn isTypeAliasNode(node_type: []const u8) bool {
        return std.mem.eql(u8, node_type, "type_alias_declaration");
    }

    /// Check if text contains arrow function
    pub fn isArrowFunction(text: []const u8) bool {
        return std.mem.indexOf(u8, text, "=>") != null;
    }
    
    /// Format method chain with proper line breaks
    fn formatMethodChain(chain: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
        // Look for method calls and split them
        var start: usize = 0;
        var i: usize = 0;
        var in_string = false;
        var paren_depth: u32 = 0;
        var brace_depth: u32 = 0;
        var first_segment = true;
        
        while (i < chain.len) {
            const c = chain[i];
            
            if (c == '"' or c == '\'' or c == '`') {
                in_string = !in_string;
            } else if (!in_string) {
                if (c == '(') {
                    paren_depth += 1;
                } else if (c == ')') {
                    paren_depth -= 1;
                } else if (c == '{') {
                    brace_depth += 1;
                } else if (c == '}') {
                    brace_depth -= 1;
                } else if (c == '.' and paren_depth == 0 and brace_depth == 0) {
                    // Found method chain break point - handle any segment before this dot
                    const segment = std.mem.trim(u8, chain[start..i], " \t");
                    if (segment.len > 0) {
                        if (first_segment) {
                            try builder.appendIndent();
                            first_segment = false;
                        } else {
                            try builder.newline();
                            try builder.appendIndent();
                        }
                        try formatArrowFunctionExpression(segment, builder);
                        try builder.newline();
                        try builder.appendIndent();
                        try builder.append(".");
                    }
                    start = i + 1;
                    i += 1;
                    continue;
                }
            }
            i += 1;
        }
        
        // Format the final segment
        if (start < chain.len) {
            const segment = std.mem.trim(u8, chain[start..], " \t");
            if (segment.len > 0) {
                if (first_segment) {
                    try builder.appendIndent();
                } else {
                    // This is a method call continuation
                }
                try formatArrowFunctionExpression(segment, builder);
            }
        }
        
        _ = options;
    }
    
    /// Format arrow function expression with proper spacing
    fn formatArrowFunctionExpression(expr: []const u8, builder: *LineBuilder) !void {
        var i: usize = 0;
        var in_string = false;
        var paren_depth: u32 = 0;
        
        while (i < expr.len) {
            const c = expr[i];
            
            if (c == '"' or c == '\'' or c == '`') {
                in_string = !in_string;
                try builder.append(&[_]u8{c});
            } else if (!in_string) {
                if (c == '(') {
                    paren_depth += 1;
                    try builder.append(&[_]u8{c});
                } else if (c == ')') {
                    paren_depth -= 1;
                    try builder.append(&[_]u8{c});
                } else if (c == '=' and i + 1 < expr.len and expr[i + 1] == '>') {
                    // Arrow function
                    try builder.append(" => ");
                    i += 2;
                    continue;
                } else if (c == '{' and paren_depth == 0) {
                    // Object literal - format with proper spacing
                    try formatObjectLiteral(expr[i..], builder);
                    break;
                } else if (c == ' ') {
                    // Only add space if previous char isn't space
                    if (builder.buffer.items.len > 0 and
                        builder.buffer.items[builder.buffer.items.len - 1] != ' ') {
                        try builder.append(" ");
                    }
                } else {
                    try builder.append(&[_]u8{c});
                }
            } else {
                try builder.append(&[_]u8{c});
            }
            i += 1;
        }
    }
    
    /// Format object literal with line breaks
    fn formatObjectLiteral(obj: []const u8, builder: *LineBuilder) !void {
        if (!std.mem.startsWith(u8, obj, "{")) {
            try builder.append(obj);
            return;
        }
        
        // Find matching closing brace
        var brace_depth: u32 = 0;
        var end_pos: usize = 0;
        for (obj, 0..) |c, i| {
            if (c == '{') {
                brace_depth += 1;
            } else if (c == '}') {
                brace_depth -= 1;
                if (brace_depth == 0) {
                    end_pos = i;
                    break;
                }
            }
        }
        
        if (end_pos == 0) {
            try builder.append(obj);
            return;
        }
        
        const content = std.mem.trim(u8, obj[1..end_pos], " \t\n\r");
        
        try builder.append("({");
        if (content.len > 0) {
            try builder.newline();
            builder.indent();
            
            // Split by comma and format each property
            var prop_start: usize = 0;
            var i: usize = 0;
            var in_string = false;
            var nested_depth: u32 = 0;
            
            while (i < content.len) {
                const c = content[i];
                if (c == '"' or c == '\'' or c == '`') {
                    in_string = !in_string;
                } else if (!in_string) {
                    if (c == '{' or c == '[' or c == '(') {
                        nested_depth += 1;
                    } else if (c == '}' or c == ']' or c == ')') {
                        nested_depth -= 1;
                    } else if (c == ',' and nested_depth == 0) {
                        const prop = std.mem.trim(u8, content[prop_start..i], " \t");
                        if (prop.len > 0) {
                            try builder.appendIndent();
                            try formatObjectProperty(prop, builder);
                            try builder.append(",");
                            try builder.newline();
                        }
                        prop_start = i + 1;
                    }
                }
                i += 1;
            }
            
            // Handle last property
            if (prop_start < content.len) {
                const prop = std.mem.trim(u8, content[prop_start..], " \t");
                if (prop.len > 0) {
                    try builder.appendIndent();
                    try formatObjectProperty(prop, builder);
                    try builder.newline();
                }
            }
            
            builder.dedent();
            try builder.appendIndent();
        }
        try builder.append("})");
        
        // Append anything after the object literal
        if (end_pos + 1 < obj.len) {
            try builder.append(obj[end_pos + 1..]);
        }
    }
    
    /// Format object property
    fn formatObjectProperty(prop: []const u8, builder: *LineBuilder) !void {
        // Look for spread operator
        if (std.mem.startsWith(u8, prop, "...")) {
            try builder.append("...");
            try builder.append(std.mem.trim(u8, prop[3..], " \t"));
        } else {
            // Regular property
            try builder.append(prop);
        }
    }
};