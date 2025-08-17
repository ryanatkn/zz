const std = @import("std");
const ts = @import("tree-sitter");
const LineBuilder = @import("../../parsing/formatter.zig").LineBuilder;
const FormatterOptions = @import("../../parsing/formatter.zig").FormatterOptions;
const NodeUtils = @import("../../language/node_utils.zig").NodeUtils;
const TypeScriptHelpers = @import("formatting_helpers.zig").TypeScriptFormattingHelpers;
const TypeScriptSpacing = @import("spacing_helpers.zig").TypeScriptSpacingHelpers;

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
            try TypeScriptHelpers.formatGenericParameters(generics, builder);
        }
        
        try builder.append(" =");
        
        // Format type definition
        if (type_definition) |type_def| {
            try builder.append(" ");
            try TypeScriptHelpers.formatWithTypeScriptSpacing(type_def, builder);
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

    /// Format arrow function variable declaration using consolidated helpers
    fn formatArrowFunctionDeclaration(var_text: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
        try builder.appendIndent();
        try TypeScriptHelpers.formatArrowFunction(builder.allocator, builder, var_text, options);
        try builder.newline();
    }

    /// Format simple variable declaration using consolidated helpers
    fn formatSimpleVariableDeclaration(var_text: []const u8, builder: *LineBuilder) !void {
        try builder.appendIndent();
        try TypeScriptHelpers.formatWithTypeScriptSpacing(var_text, builder);
        try builder.newline();
    }

    /// Format type declaration using consolidated helpers
    fn formatTypeDeclaration(declaration: []const u8, builder: *LineBuilder) !void {
        try TypeScriptHelpers.formatWithTypeScriptSpacing(declaration, builder);
    }

    /// Format type definition using consolidated helpers
    fn formatTypeDefinition(type_def: []const u8, builder: *LineBuilder) !void {
        try TypeScriptHelpers.formatWithTypeScriptSpacing(type_def, builder);
    }

    /// Format block body using consolidated helpers
    fn formatTypeBlockBody(body: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
        try TypeScriptHelpers.formatWithTypeScriptSpacing(body, builder);
        _ = options;
    }

    /// Format method chain using consolidated helpers
    fn formatMethodChain(chain: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
        try TypeScriptHelpers.formatMethodChaining(builder.allocator, builder, chain, options);
    }

    /// Format arrow function expression using consolidated helpers
    fn formatArrowFunctionExpression(expr: []const u8, builder: *LineBuilder) !void {
        try TypeScriptHelpers.formatWithTypeScriptSpacing(expr, builder);
    }

    /// Format object literal using consolidated helpers
    fn formatObjectLiteral(obj: []const u8, builder: *LineBuilder) !void {
        try TypeScriptHelpers.formatWithTypeScriptSpacing(obj, builder);
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