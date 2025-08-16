const std = @import("std");
const ts = @import("tree-sitter");
const LineBuilder = @import("../../parsing/formatter.zig").LineBuilder;
const FormatterOptions = @import("../../parsing/formatter.zig").FormatterOptions;
const NodeUtils = @import("../../language/node_utils.zig").NodeUtils;
const ZigBodyFormatter = @import("body_formatter.zig").ZigBodyFormatter;

pub const ZigContainerFormatter = struct {
    /// Format Zig struct declaration
    pub fn formatStruct(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
        if (findContainerDecl(node)) |container| {
            const struct_text = NodeUtils.getNodeText(node, source);
            
            // Extract the struct name and format declaration
            if (extractStructName(struct_text)) |name| {
                try builder.append("const ");
                try builder.append(name);
                try builder.append(" = struct {");
                try builder.newline();
                builder.indent();
                
                // Format the struct body
                try formatStructBody(container, source, builder, depth + 1, options);
                
                builder.dedent();
                try builder.appendIndent();
                try builder.append("};");
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
        if (findContainerDecl(node)) |container| {
            const enum_text = NodeUtils.getNodeText(node, source);
            
            // Extract the enum name and format declaration
            if (extractEnumName(enum_text)) |name| {
                try builder.append("const ");
                try builder.append(name);
                try builder.append(" = enum {");
                try builder.newline();
                builder.indent();
                
                // Format the enum body
                try formatEnumBody(container, source, builder, depth + 1, options);
                
                builder.dedent();
                try builder.appendIndent();
                try builder.append("};");
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
        if (findContainerDecl(node)) |container| {
            const union_text = NodeUtils.getNodeText(node, source);
            
            // Extract the union name and format declaration
            if (extractUnionName(union_text)) |name| {
                try builder.append("const ");
                try builder.append(name);
                try builder.append(" = union {");
                try builder.newline();
                builder.indent();
                
                // Format the union body
                try formatUnionBody(container, source, builder, depth + 1, options);
                
                builder.dedent();
                try builder.appendIndent();
                try builder.append("};");
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
        // Look for pattern: const Name = struct
        if (std.mem.indexOf(u8, text, "const ")) |start| {
            const after_const = text[start + "const ".len..];
            if (std.mem.indexOf(u8, after_const, " =")) |equals_pos| {
                return std.mem.trim(u8, after_const[0..equals_pos], " \t");
            }
        }
        return null;
    }

    /// Extract enum name from declaration text
    fn extractEnumName(text: []const u8) ?[]const u8 {
        // Look for pattern: const Name = enum
        if (std.mem.indexOf(u8, text, "const ")) |start| {
            const after_const = text[start + "const ".len..];
            if (std.mem.indexOf(u8, after_const, " =")) |equals_pos| {
                return std.mem.trim(u8, after_const[0..equals_pos], " \t");
            }
        }
        return null;
    }

    /// Extract union name from declaration text
    fn extractUnionName(text: []const u8) ?[]const u8 {
        // Look for pattern: const Name = union
        if (std.mem.indexOf(u8, text, "const ")) |start| {
            const after_const = text[start + "const ".len..];
            if (std.mem.indexOf(u8, after_const, " =")) |equals_pos| {
                return std.mem.trim(u8, after_const[0..equals_pos], " \t");
            }
        }
        return null;
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
        var i: usize = 0;
        var in_string = false;
        var escape_next = false;

        while (i < field_text.len) {
            const c = field_text[i];

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

            if (c == ':') {
                // Zig style: no space before colon, space after
                while (builder.buffer.items.len > 0 and 
                       builder.buffer.items[builder.buffer.items.len - 1] == ' ') {
                    _ = builder.buffer.pop();
                }
                try builder.append(":");
                i += 1;
                
                // Ensure space after colon if next char isn't space
                if (i < field_text.len and field_text[i] != ' ') {
                    try builder.append(" ");
                }
                continue;
            }

            try builder.append(&[_]u8{c});
            i += 1;
        }
    }

    /// Text-based fallback formatting for struct body
    fn formatStructBodyFromText(struct_text: []const u8, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
        _ = source;
        _ = depth;
        _ = options;
        try ZigBodyFormatter.formatStructBodyFromText(struct_text, builder);
    }

    /// Text-based fallback formatting for enum body
    fn formatEnumBodyFromText(enum_text: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
        _ = options;
        try ZigBodyFormatter.formatEnumBodyFromText(enum_text, builder);
    }

    /// Text-based fallback formatting for union body
    fn formatUnionBodyFromText(union_text: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
        _ = options;
        try ZigBodyFormatter.formatUnionBodyFromText(union_text, builder);
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