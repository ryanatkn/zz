const std = @import("std");
const ts = @import("tree-sitter");
const LineBuilder = @import("../../parsing/formatter.zig").LineBuilder;
const FormatterOptions = @import("../../parsing/formatter.zig").FormatterOptions;
const NodeUtils = @import("../../language/node_utils.zig").NodeUtils;

pub const FormatClass = struct {
    /// Format TypeScript class declaration
    pub fn formatClass(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
        const child_count = node.childCount();
        var i: u32 = 0;
        
        var has_export = false;
        var has_abstract = false;
        var class_name: ?[]const u8 = null;
        var body_node: ?ts.Node = null;
        var generic_params: ?[]const u8 = null;
        var extends_clause: ?[]const u8 = null;
        var implements_clause: ?[]const u8 = null;
        
        // Parse class components
        while (i < child_count) : (i += 1) {
            if (node.child(i)) |child| {
                const child_type = child.kind();
                const child_text = NodeUtils.getNodeText(child, source);
                
                if (std.mem.eql(u8, child_type, "export")) {
                    has_export = true;
                } else if (std.mem.eql(u8, child_type, "abstract")) {
                    has_abstract = true;
                } else if (std.mem.eql(u8, child_type, "identifier") or std.mem.eql(u8, child_type, "type_identifier")) {
                    if (class_name == null) {
                        class_name = child_text;
                    }
                } else if (std.mem.eql(u8, child_type, "type_parameters")) {
                    generic_params = child_text;
                } else if (std.mem.eql(u8, child_type, "class_heritage")) {
                    // Parse extends and implements
                    const heritage_text = child_text;
                    if (std.mem.indexOf(u8, heritage_text, "extends")) |_| {
                        extends_clause = heritage_text;
                    }
                    if (std.mem.indexOf(u8, heritage_text, "implements")) |_| {
                        implements_clause = heritage_text;
                    }
                } else if (std.mem.eql(u8, child_type, "class_body")) {
                    body_node = child;
                }
            }
        }
        
        // Format class declaration
        try builder.appendIndent();
        
        if (has_export) {
            try builder.append("export ");
        }
        
        if (has_abstract) {
            try builder.append("abstract ");
        }
        
        try builder.append("class");
        
        if (class_name) |name| {
            try builder.append(" ");
            try builder.append(name);
        }
        
        // Add generic parameters
        if (generic_params) |generics| {
            try formatGenericParameters(generics, builder);
        }
        
        // Add heritage clauses
        if (extends_clause) |extends| {
            try builder.append(" ");
            try builder.append(extends);
        }
        
        if (implements_clause) |implements| {
            try builder.append(" ");
            try builder.append(implements);
        }
        
        try builder.append(" {");
        
        // Format class body
        if (body_node) |body| {
            try formatClassBody(body, source, builder, depth + 1, options);
        }
        
        try builder.appendIndent();
        try builder.append("}");
        try builder.newline();
        try builder.newline();
    }

    /// Format class body with proper member handling
    fn formatClassBody(body_node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
        const child_count = body_node.childCount();
        if (child_count == 0) return;
        
        try builder.newline();
        builder.indent();
        
        var i: u32 = 0;
        var prev_was_method = false;
        
        while (i < child_count) : (i += 1) {
            if (body_node.child(i)) |child| {
                const child_type = child.kind();
                
                if (std.mem.eql(u8, child_type, "field_definition") or
                   std.mem.eql(u8, child_type, "property_definition")) {
                    
                    // Add spacing between methods and properties
                    if (prev_was_method) {
                        try builder.newline();
                    }
                    
                    try formatClassMember(child, source, builder, depth, options);
                    prev_was_method = false;
                    
                } else if (std.mem.eql(u8, child_type, "method_definition") or
                          std.mem.eql(u8, child_type, "method_signature")) {
                    
                    // Add spacing between different types of members
                    if (i > 0) {
                        try builder.newline();
                    }
                    
                    try formatClassMember(child, source, builder, depth, options);
                    prev_was_method = true;
                    
                } else if (std.mem.eql(u8, child_type, "constructor_definition")) {
                    // Constructor gets special treatment
                    if (i > 0) {
                        try builder.newline();
                    }
                    
                    try formatClassMember(child, source, builder, depth, options);
                    prev_was_method = true;
                }
            }
        }
        
        try builder.newline();
        builder.dedent();
    }

    /// Format individual class members
    fn formatClassMember(member_node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
        _ = depth;
        
        const member_text = NodeUtils.getNodeText(member_node, source);
        const member_type = member_node.kind();
        
        if (std.mem.eql(u8, member_type, "method_definition")) {
            try formatMethodWithSpacing(member_text, builder, options);
        } else if (std.mem.eql(u8, member_type, "field_definition") or
                  std.mem.eql(u8, member_type, "property_definition")) {
            try formatPropertyWithSpacing(member_text, builder);
        } else {
            // Fallback - format with basic spacing
            try builder.appendIndent();
            try formatWithBasicSpacing(member_text, builder);
            try builder.newline();
        }
    }

    /// Format class property with proper spacing
    fn formatPropertyWithSpacing(property_text: []const u8, builder: *LineBuilder) !void {
        try builder.appendIndent();
        
        var i: usize = 0;
        var in_string = false;
        var string_char: u8 = 0;
        var escape_next = false;

        while (i < property_text.len) {
            const c = property_text[i];

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

            if (c == ':') {
                // TypeScript style: space before and after colon
                if (builder.buffer.items.len > 0 and 
                    builder.buffer.items[builder.buffer.items.len - 1] != ' ') {
                    try builder.append(" ");
                }
                try builder.append(":");
                i += 1;
                
                // Ensure space after colon
                if (i < property_text.len and property_text[i] != ' ') {
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
                if (i < property_text.len and property_text[i] != ' ') {
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
        
        // Ensure semicolon at end for properties
        if (builder.buffer.items.len > 0 and
            builder.buffer.items[builder.buffer.items.len - 1] != ';' and
            builder.buffer.items[builder.buffer.items.len - 1] != '}') {
            try builder.append(";");
        }
        
        try builder.newline();
    }

    /// Format class method with proper spacing
    fn formatMethodWithSpacing(method_text: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
        // Check if it's a single line or multiline method
        if (std.mem.indexOf(u8, method_text, "{\n") != null or
            method_text.len > options.line_width) {
            try formatMultiLineMethod(method_text, builder, options);
        } else {
            try formatSingleLineMethod(method_text, builder);
        }
    }

    /// Format single line method
    fn formatSingleLineMethod(method_text: []const u8, builder: *LineBuilder) !void {
        try builder.appendIndent();
        try formatWithBasicSpacing(method_text, builder);
        try builder.newline();
    }

    /// Format multiline method with proper indentation
    fn formatMultiLineMethod(method_text: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
        // Find the opening brace
        if (std.mem.indexOf(u8, method_text, "{")) |brace_pos| {
            const signature = std.mem.trim(u8, method_text[0..brace_pos], " \t");
            const body_start = brace_pos + 1;
            const body_end = std.mem.lastIndexOf(u8, method_text, "}") orelse method_text.len;
            const body = std.mem.trim(u8, method_text[body_start..body_end], " \t\n\r");
            
            // Format signature
            try builder.appendIndent();
            try formatMethodSignature(signature, builder, options);
            try builder.append(" {");
            
            // Format body
            if (body.len > 0) {
                try builder.newline();
                builder.indent();
                
                var lines = std.mem.splitSequence(u8, body, "\n");
                while (lines.next()) |line| {
                    const trimmed = std.mem.trim(u8, line, " \t");
                    if (trimmed.len > 0) {
                        try builder.appendIndent();
                        try builder.append(trimmed);
                        try builder.newline();
                    }
                }
                
                builder.dedent();
                try builder.appendIndent();
            }
            
            try builder.append("}");
        } else {
            // No body, just format as signature
            try builder.appendIndent();
            try formatMethodSignature(method_text, builder, options);
        }
        
        try builder.newline();
    }

    /// Format method signature
    fn formatMethodSignature(signature: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
        // For now, delegate to parameter formatting
        try formatMethodParameters(signature, builder, options);
    }

    /// Format method parameters
    fn formatMethodParameters(params_text: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
        _ = options;
        
        // Simple approach - clean up basic spacing
        var i: usize = 0;
        var in_string = false;
        var string_char: u8 = 0;
        var prev_was_space = false;

        while (i < params_text.len) {
            const c = params_text[i];

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

    /// Format with basic spacing cleanup
    fn formatWithBasicSpacing(text: []const u8, builder: *LineBuilder) !void {
        var i: usize = 0;
        var in_string = false;
        var string_char: u8 = 0;
        var prev_was_space = false;

        while (i < text.len) {
            const c = text[i];

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

    /// Format generic parameters
    fn formatGenericParameters(type_params: []const u8, builder: *LineBuilder) !void {
        // Simple approach - just clean up spacing
        var cleaned = std.ArrayList(u8).init(std.heap.page_allocator);
        defer cleaned.deinit();
        
        var i: usize = 0;
        var in_string = false;
        var prev_was_space = false;
        
        while (i < type_params.len) {
            const c = type_params[i];
            
            if (c == '"' or c == '\'') {
                in_string = !in_string;
                try cleaned.append(c);
                prev_was_space = false;
            } else if (in_string) {
                try cleaned.append(c);
                prev_was_space = false;
            } else if (c == ' ') {
                if (!prev_was_space) {
                    try cleaned.append(' ');
                    prev_was_space = true;
                }
            } else {
                try cleaned.append(c);
                prev_was_space = false;
            }
            
            i += 1;
        }
        
        try builder.append(cleaned.items);
    }

    /// Check if node represents a class
    pub fn isClassNode(node_type: []const u8) bool {
        return std.mem.eql(u8, node_type, "class_declaration");
    }

    /// Extract class name from declaration
    pub fn extractClassName(class_text: []const u8) ?[]const u8 {
        // Look for "class Name" pattern
        if (std.mem.indexOf(u8, class_text, "class ")) |start| {
            const after_class = class_text[start + "class ".len..];
            
            // Find the end of the name (space, <, {, extends, implements, or end)
            var end_pos: usize = 0;
            for (after_class) |c| {
                if (c == ' ' or c == '<' or c == '{' or c == '\n') {
                    break;
                }
                end_pos += 1;
            }
            
            if (end_pos > 0) {
                return after_class[0..end_pos];
            }
        }
        return null;
    }
};