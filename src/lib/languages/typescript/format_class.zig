const std = @import("std");
const ts = @import("tree-sitter");
const LineBuilder = @import("../../parsing/formatter.zig").LineBuilder;
const FormatterOptions = @import("../../parsing/formatter.zig").FormatterOptions;
const NodeUtils = @import("../../language/node_utils.zig").NodeUtils;
const TypeScriptHelpers = @import("formatting_helpers.zig").TypeScriptFormattingHelpers;
const TypeScriptSpacing = @import("spacing_helpers.zig").TypeScriptSpacingHelpers;

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
            try TypeScriptHelpers.formatGenericParameters(generics, builder);
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

    /// Format individual class members using consolidated helpers
    fn formatClassMember(member_node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
        _ = depth;
        
        const member_text = NodeUtils.getNodeText(member_node, source);
        const member_type = member_node.kind();
        
        if (std.mem.eql(u8, member_type, "method_definition")) {
            try formatMethodWithSpacing(member_text, builder, options);
        } else if (std.mem.eql(u8, member_type, "field_definition") or
                  std.mem.eql(u8, member_type, "property_definition")) {
            try builder.appendIndent();
            try TypeScriptHelpers.formatPropertyWithSpacing(member_text, builder);
            // Ensure semicolon at end for properties
            if (builder.buffer.items.len > 0 and
                builder.buffer.items[builder.buffer.items.len - 1] != ';' and
                builder.buffer.items[builder.buffer.items.len - 1] != '}') {
                try builder.append(";");
            }
            try builder.newline();
        } else {
            // Fallback - format with consolidated spacing
            try builder.appendIndent();
            try TypeScriptHelpers.formatWithTypeScriptSpacing(member_text, builder);
            try builder.newline();
        }
    }

    /// Format class method using consolidated helpers
    fn formatMethodWithSpacing(method_text: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
        // Check if it's a single line or multiline method
        if (std.mem.indexOf(u8, method_text, "{\n") != null or
            method_text.len > options.line_width) {
            try formatMultiLineMethod(method_text, builder, options);
        } else {
            try formatSingleLineMethod(method_text, builder);
        }
    }

    /// Format single line method using consolidated helpers
    fn formatSingleLineMethod(method_text: []const u8, builder: *LineBuilder) !void {
        try builder.appendIndent();
        try TypeScriptHelpers.formatWithTypeScriptSpacing(method_text, builder);
        try builder.newline();
    }

    /// Format multiline method using consolidated helpers
    fn formatMultiLineMethod(method_text: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
        // Find the opening brace
        if (std.mem.indexOf(u8, method_text, "{")) |brace_pos| {
            const signature = std.mem.trim(u8, method_text[0..brace_pos], " \t");
            const body_start = brace_pos + 1;
            const body_end = std.mem.lastIndexOf(u8, method_text, "}") orelse method_text.len;
            const body = std.mem.trim(u8, method_text[body_start..body_end], " \t\n\r");
            
            // Format signature using consolidated helper
            try builder.appendIndent();
            try TypeScriptHelpers.formatMethodSignature(builder.allocator, signature, builder, options);
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
                        try TypeScriptHelpers.formatWithTypeScriptSpacing(trimmed, builder);
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
            try TypeScriptHelpers.formatMethodSignature(builder.allocator, method_text, builder, options);
        }
        
        try builder.newline();
    }

    /// Check if node represents a class
    pub fn isClassNode(node_type: []const u8) bool {
        return std.mem.eql(u8, node_type, "class_declaration");
    }

    /// Extract class name from declaration using consolidated helper
    pub fn extractClassName(class_text: []const u8) ?[]const u8 {
        return TypeScriptHelpers.extractDeclarationName(class_text);
    }
};