const std = @import("std");
const ts = @import("tree-sitter");
const LineBuilder = @import("../../parsing/formatter.zig").LineBuilder;
const FormatterOptions = @import("../../parsing/formatter.zig").FormatterOptions;
const NodeUtils = @import("../../language/node_utils.zig").NodeUtils;
const FormatBody = @import("format_body.zig").FormatBody;
const ZigFormattingHelpers = @import("formatting_helpers.zig").ZigFormattingHelpers;

pub const FormatContainer = struct {
    /// Format Zig struct declaration
    pub fn formatStruct(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
        if (findContainerDecl(node)) |container| {
            const struct_text = NodeUtils.getNodeText(node, source);
            
            // Extract the struct name and format declaration
            if (extractStructName(struct_text)) |name| {
                const signature = try std.fmt.allocPrint(builder.allocator, "const {s} = struct", .{name});
                defer builder.allocator.free(signature);
                
                // Get the struct body content as text
                const body_content = getContainerBodyText(container, source);
                
                // Use consolidated block formatting helper
                try ZigFormattingHelpers.formatBlockWithBraces(builder, signature, body_content, true);
                try builder.append(";");
            } else {
                // Fallback: format as text
                try formatStructBodyFromText(struct_text, source, builder, depth, options);
            }
        } else {
            // No container found, format as text
            const struct_text = NodeUtils.getNodeText(node, source);
            try formatStructBodyFromText(struct_text, source, builder, depth, options);
        }
    }

    /// Format Zig enum declaration
    pub fn formatEnum(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
        _ = depth;
        if (findContainerDecl(node)) |container| {
            const enum_text = NodeUtils.getNodeText(node, source);
            
            // Extract the enum name and format declaration
            if (extractEnumName(enum_text)) |name| {
                const signature = try std.fmt.allocPrint(builder.allocator, "const {s} = enum", .{name});
                defer builder.allocator.free(signature);
                
                // Get the enum body content as text
                const body_content = getContainerBodyText(container, source);
                
                // Use consolidated block formatting helper
                try ZigFormattingHelpers.formatBlockWithBraces(builder, signature, body_content, true);
                try builder.append(";");
            } else {
                // Fallback: format as text
                try formatEnumBodyFromText(enum_text, builder, options);
            }
        } else {
            // No container found, format as text
            const enum_text = NodeUtils.getNodeText(node, source);
            try formatEnumBodyFromText(enum_text, builder, options);
        }
    }

    /// Format Zig union declaration
    pub fn formatUnion(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
        _ = depth;
        if (findContainerDecl(node)) |container| {
            const union_text = NodeUtils.getNodeText(node, source);
            
            // Extract the union name and format declaration
            if (extractUnionName(union_text)) |name| {
                const signature = try std.fmt.allocPrint(builder.allocator, "const {s} = union", .{name});
                defer builder.allocator.free(signature);
                
                // Get the union body content as text
                const body_content = getContainerBodyText(container, source);
                
                // Use consolidated block formatting helper
                try ZigFormattingHelpers.formatBlockWithBraces(builder, signature, body_content, true);
                try builder.append(";");
            } else {
                // Fallback: format as text
                try formatUnionBodyFromText(union_text, builder, options);
            }
        } else {
            // No container found, format as text
            const union_text = NodeUtils.getNodeText(node, source);
            try formatUnionBodyFromText(union_text, builder, options);
        }
    }

    /// Find container declaration node within a struct/enum/union
    fn findContainerDecl(node: ts.Node) ?ts.Node {
        const child_count = node.childCount();
        var i: u32 = 0;
        while (i < child_count) : (i += 1) {
            if (node.child(i)) |child| {
                const child_type = child.kind();
                if (std.mem.eql(u8, child_type, "ContainerDecl")) {
                    return child;
                }
            }
        }
        return null;
    }

    /// Extract struct name from declaration text
    fn extractStructName(text: []const u8) ?[]const u8 {
        // Use consolidated helper for name extraction
        return ZigFormattingHelpers.extractDeclarationName(text);
    }

    /// Extract enum name from declaration text
    fn extractEnumName(text: []const u8) ?[]const u8 {
        // Use consolidated helper for name extraction
        return ZigFormattingHelpers.extractDeclarationName(text);
    }

    /// Extract union name from declaration text
    fn extractUnionName(text: []const u8) ?[]const u8 {
        // Use consolidated helper for name extraction
        return ZigFormattingHelpers.extractDeclarationName(text);
    }

    /// Format struct body using AST nodes
    fn formatStructBody(container: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
        const child_count = container.childCount();
        var i: u32 = 0;
        
        while (i < child_count) : (i += 1) {
            if (container.child(i)) |child| {
                const child_type = child.kind();
                
                if (std.mem.eql(u8, child_type, "ContainerField")) {
                    try formatStructField(child, source, builder);
                    try builder.append(",");
                    try builder.newline();
                } else if (std.mem.eql(u8, child_type, "Decl") or 
                          std.mem.eql(u8, child_type, "VarDecl")) {
                    // Nested function or declaration
                    try builder.newline(); // Extra space before nested items
                    try formatZigNode(child, source, builder, depth, options);
                    try builder.newline();
                }
            }
        }
    }

    /// Format enum body using AST nodes
    fn formatEnumBody(container: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
        _ = depth;
        _ = options;
        
        const child_count = container.childCount();
        var i: u32 = 0;
        
        while (i < child_count) : (i += 1) {
            if (container.child(i)) |child| {
                const child_type = child.kind();
                
                if (std.mem.eql(u8, child_type, "ContainerField")) {
                    const field_text = NodeUtils.getNodeText(child, source);
                    try builder.appendIndent();
                    try builder.append(std.mem.trim(u8, field_text, " \t\n"));
                    try builder.append(",");
                    try builder.newline();
                }
            }
        }
    }

    /// Format union body using AST nodes
    fn formatUnionBody(container: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
        _ = depth;
        _ = options;
        
        const child_count = container.childCount();
        var i: u32 = 0;
        
        while (i < child_count) : (i += 1) {
            if (container.child(i)) |child| {
                const child_type = child.kind();
                
                if (std.mem.eql(u8, child_type, "ContainerField")) {
                    try formatUnionField(child, source, builder);
                    try builder.append(",");
                    try builder.newline();
                }
            }
        }
    }

    /// Format struct field with proper typing
    fn formatStructField(node: ts.Node, source: []const u8, builder: *LineBuilder) !void {
        const field_text = NodeUtils.getNodeText(node, source);
        try builder.appendIndent();
        try formatFieldWithSpacing(field_text, builder);
    }

    /// Format union field with proper typing
    fn formatUnionField(node: ts.Node, source: []const u8, builder: *LineBuilder) !void {
        const field_text = NodeUtils.getNodeText(node, source);
        try builder.appendIndent();
        try formatFieldWithSpacing(field_text, builder);
    }

    /// Format field with proper spacing around colons
    fn formatFieldWithSpacing(field_text: []const u8, builder: *LineBuilder) !void {
        // Use consolidated helper for field formatting
        try ZigFormattingHelpers.formatFieldWithColon(field_text, builder);
    }

    /// Text-based fallback formatting for struct body
    fn formatStructBodyFromText(struct_text: []const u8, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
        _ = source;
        _ = depth;
        _ = options;
        try FormatBody.formatStructBodyFromText(struct_text, builder);
    }

    /// Text-based fallback formatting for enum body
    fn formatEnumBodyFromText(enum_text: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
        _ = options;
        try FormatBody.formatEnumBodyFromText(enum_text, builder);
    }

    /// Text-based fallback formatting for union body
    fn formatUnionBodyFromText(union_text: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
        _ = options;
        try FormatBody.formatUnionBodyFromText(union_text, builder);
    }

    /// Extract container body text from AST node
    fn getContainerBodyText(container: ts.Node, source: []const u8) []const u8 {
        return NodeUtils.getNodeText(container, source);
    }

    // Forward declaration for formatZigNode (will be imported from main formatter)
    fn formatZigNode(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
        // This will be replaced with proper import once main formatter is restructured
        _ = node;
        _ = source;
        _ = builder;
        _ = depth;
        _ = options;
        // Placeholder - will delegate to main formatter
    }
};