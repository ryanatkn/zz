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
                // Expression body
                if (before_arrow.len + after_arrow.len + 4 > options.line_width) {
                    try builder.newline();
                    builder.indent();
                    try builder.appendIndent();
                    try builder.append(after_arrow);
                    builder.dedent();
                } else {
                    try builder.append(after_arrow);
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
                // TypeScript style: space before and after colon
                if (builder.buffer.items.len > 0 and 
                    builder.buffer.items[builder.buffer.items.len - 1] != ' ') {
                    try builder.append(" ");
                }
                try builder.append(":");
                i += 1;
                
                // Ensure space after colon
                if (i < declaration.len and declaration[i] != ' ') {
                    try builder.append(" ");
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
};