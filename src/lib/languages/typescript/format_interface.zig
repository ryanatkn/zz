const std = @import("std");
const ts = @import("tree-sitter");
const LineBuilder = @import("../../parsing/formatter.zig").LineBuilder;
const FormatterOptions = @import("../../parsing/formatter.zig").FormatterOptions;
const NodeUtils = @import("../../language/node_utils.zig").NodeUtils;
const TypeScriptHelpers = @import("formatting_helpers.zig").TypeScriptFormattingHelpers;
const TypeScriptSpacing = @import("spacing_helpers.zig").TypeScriptSpacingHelpers;

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
            try TypeScriptHelpers.formatGenericParameters(generics, builder);
        }
        
        // Add extends clause
        if (extends_clause) |extends| {
            try builder.append(" ");
            try TypeScriptHelpers.formatWithTypeScriptSpacing(extends, builder);
        }
        
        try builder.append(" {");
        
        // Format interface body
        if (body_node) |body| {
            try formatInterfaceBody(body, source, builder, depth + 1, options);
        }
        
        try builder.appendIndent();
        try builder.append("}");
        try builder.newline();
    }

    /// Format interface body with proper member handling
    fn formatInterfaceBody(body_node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
        _ = depth;
        _ = options;
        
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
                    try builder.appendIndent();
                    try TypeScriptHelpers.formatPropertyWithSpacing(property_text, builder);
                    try builder.append(";");
                    try builder.newline();
                }
            }
        }
        
        builder.dedent();
    }



    


    /// Check if node represents an interface
    pub fn isInterfaceNode(node_type: []const u8) bool {
        return std.mem.eql(u8, node_type, "interface_declaration");
    }

    /// Extract interface name from declaration using consolidated helper
    pub fn extractInterfaceName(interface_text: []const u8) ?[]const u8 {
        return TypeScriptHelpers.extractDeclarationName(interface_text);
    }
};