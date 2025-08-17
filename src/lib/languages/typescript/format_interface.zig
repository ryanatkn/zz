const std = @import("std");
const ts = @import("tree-sitter");
const LineBuilder = @import("../../parsing/formatter.zig").LineBuilder;
const FormatterOptions = @import("../../parsing/formatter.zig").FormatterOptions;
const NodeUtils = @import("../../language/node_utils.zig").NodeUtils;

pub const FormatInterface = struct {
    /// Format TypeScript interface declaration
    pub fn formatInterface(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
        const child_count = node.childCount();
        var i: u32 = 0;
        
        var has_export = false;
        var interface_name: ?[]const u8 = null;
        var body_node: ?ts.Node = null;
        var generic_params: ?[]const u8 = null;
        var extends_clause: ?[]const u8 = null;
        
        // Parse interface components
        while (i < child_count) : (i += 1) {
            if (node.child(i)) |child| {
                const child_type = child.kind();
                const child_text = NodeUtils.getNodeText(child, source);
                
                if (std.mem.eql(u8, child_type, "export")) {
                    has_export = true;
                } else if (std.mem.eql(u8, child_type, "identifier") or std.mem.eql(u8, child_type, "type_identifier")) {
                    if (interface_name == null) {
                        interface_name = child_text;
                    }
                } else if (std.mem.eql(u8, child_type, "type_parameters")) {
                    generic_params = child_text;
                } else if (std.mem.eql(u8, child_type, "extends_clause")) {
                    extends_clause = child_text;
                } else if (std.mem.eql(u8, child_type, "object_type") or std.mem.eql(u8, child_type, "interface_body")) {
                    body_node = child;
                }
            }
        }
        
        // Format interface declaration
        try builder.appendIndent();
        
        if (has_export) {
            try builder.append("export ");
        }
        
        try builder.append("interface");
        
        if (interface_name) |name| {
            try builder.append(" ");
            try builder.append(name);
        }
        
        // Add generic parameters
        if (generic_params) |generics| {
            try formatGenericParameters(generics, builder);
        }
        
        // Add extends clause
        if (extends_clause) |extends| {
            try builder.append(" ");
            try builder.append(extends);
        }
        
        try builder.append(" {");
        
        // Format interface body
        if (body_node) |body| {
            try formatInterfaceBody(body, source, builder, depth + 1, options);
        }
        
        try builder.appendIndent();
        try builder.append("}");
        try builder.newline();
        try builder.newline();
    }

    /// Format interface body with proper member handling
    fn formatInterfaceBody(body_node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
        _ = depth;
        
        const child_count = body_node.childCount();
        if (child_count == 0) return;
        
        try builder.newline();
        builder.indent();
        
        var i: u32 = 0;
        while (i < child_count) : (i += 1) {
            if (body_node.child(i)) |child| {
                const child_type = child.kind();
                
                if (std.mem.eql(u8, child_type, "property_signature") or
                   std.mem.eql(u8, child_type, "method_signature") or
                   std.mem.eql(u8, child_type, "construct_signature") or
                   std.mem.eql(u8, child_type, "call_signature")) {
                    
                    const property_text = NodeUtils.getNodeText(child, source);
                    try formatInterfaceProperty(property_text, builder, options);
                    try builder.newline();
                }
            }
        }
        
        builder.dedent();
    }

    /// Format interface property with proper indentation and spacing
    fn formatInterfaceProperty(property: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
        const trimmed = std.mem.trim(u8, property, " \t\n");
        if (trimmed.len == 0) return;
        
        try builder.appendIndent();
        
        // Check if this is a complex property that needs special formatting
        if (std.mem.indexOf(u8, trimmed, "=>") != null or
            std.mem.indexOf(u8, trimmed, "{") != null or
            trimmed.len > options.line_width) {
            try formatNestedProperty(trimmed, builder, options);
        } else {
            try formatSimpleProperty(trimmed, builder);
        }
    }

    /// Format simple properties on single line
    fn formatSimpleProperty(property: []const u8, builder: *LineBuilder) !void {
        var i: usize = 0;
        var in_string = false;
        var string_char: u8 = 0;
        var escape_next = false;

        while (i < property.len) {
            const c = property[i];

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
                // TypeScript style: no space before colon, space after colon
                try builder.append(":");
                i += 1;
                
                // Ensure space after colon
                if (i < property.len and property[i] != ' ') {
                    try builder.append(" ");
                }
                continue;
            }

            if (c == ';') {
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
        
        // Ensure semicolon at end
        if (builder.buffer.items.len > 0 and
            builder.buffer.items[builder.buffer.items.len - 1] != ';') {
            try builder.append(";");
        }
    }

    /// Format complex properties with multiline support
    fn formatNestedProperty(property: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
        // Check if this is an object type property
        if (std.mem.indexOf(u8, property, "{") != null) {
            try formatObjectTypeProperty(property, builder, options);
        } else {
            // For other complex properties, just format with basic spacing
            var lines = std.mem.splitSequence(u8, property, "\n");
            var first_line = true;
            
            while (lines.next()) |line| {
                const trimmed = std.mem.trim(u8, line, " \t");
                if (trimmed.len > 0) {
                    if (!first_line) {
                        try builder.newline();
                        try builder.appendIndent();
                    }
                    try builder.append(trimmed);
                    first_line = false;
                }
            }
            
            // Ensure semicolon at end
            if (builder.buffer.items.len > 0 and
                builder.buffer.items[builder.buffer.items.len - 1] != ';') {
                try builder.append(";");
            }
        }
    }
    
    /// Format object type property (e.g., profile: { bio: string; avatar?: string; })
    fn formatObjectTypeProperty(property: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
        _ = options;
        
        // Find the colon and object start
        if (std.mem.indexOf(u8, property, ":")) |colon_pos| {
            const prop_name = std.mem.trim(u8, property[0..colon_pos], " \t");
            const remaining = std.mem.trim(u8, property[colon_pos + 1..], " \t");
            
            // Add property name and colon
            try builder.append(prop_name);
            try builder.append(": ");
            
            if (std.mem.indexOf(u8, remaining, "{")) |brace_pos| {
                const before_brace = std.mem.trim(u8, remaining[0..brace_pos], " \t");
                if (before_brace.len > 0) {
                    try builder.append(before_brace);
                    try builder.append(" ");
                }
                
                // Format object content
                try builder.append("{");
                try builder.newline();
                builder.indent();
                
                // Extract content between braces
                if (std.mem.lastIndexOf(u8, remaining, "}")) |end_brace_pos| {
                    const content = std.mem.trim(u8, remaining[brace_pos + 1..end_brace_pos], " \t\n");
                    
                    // Split by semicolon and format each property
                    var parts = std.mem.splitSequence(u8, content, ";");
                    while (parts.next()) |part| {
                        const trimmed = std.mem.trim(u8, part, " \t\n");
                        if (trimmed.len > 0) {
                            try builder.appendIndent();
                            try formatSimpleProperty(trimmed, builder);
                            try builder.newline();
                        }
                    }
                }
                
                builder.dedent();
                try builder.appendIndent();
                try builder.append("};");
            } else {
                // No braces, just add the remaining content
                try builder.append(remaining);
                if (!std.mem.endsWith(u8, remaining, ";")) {
                    try builder.append(";");
                }
            }
        } else {
            // No colon found, just append as simple property
            try formatSimpleProperty(property, builder);
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

    /// Check if node represents an interface
    pub fn isInterfaceNode(node_type: []const u8) bool {
        return std.mem.eql(u8, node_type, "interface_declaration");
    }

    /// Extract interface name from declaration
    pub fn extractInterfaceName(interface_text: []const u8) ?[]const u8 {
        // Look for "interface Name" pattern
        if (std.mem.indexOf(u8, interface_text, "interface ")) |start| {
            const after_interface = interface_text[start + "interface ".len..];
            
            // Find the end of the name (space, <, {, or end)
            var end_pos: usize = 0;
            for (after_interface) |c| {
                if (c == ' ' or c == '<' or c == '{' or c == '\n') {
                    break;
                }
                end_pos += 1;
            }
            
            if (end_pos > 0) {
                return after_interface[0..end_pos];
            }
        }
        return null;
    }
};