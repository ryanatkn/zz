const std = @import("std");
const ts = @import("tree-sitter");
const LineBuilder = @import("../../parsing/formatter.zig").LineBuilder;
const FormatterOptions = @import("../../parsing/formatter.zig").FormatterOptions;
const NodeUtils = @import("../../language/node_utils.zig").NodeUtils;
const ZigFormattingHelpers = @import("formatting_helpers.zig").ZigFormattingHelpers;
const ZigSpacingHelpers = @import("spacing_helpers.zig").ZigSpacingHelpers;

pub const FormatVariable = struct {
    /// Format Zig variable declaration
    pub fn formatVariable(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
        _ = depth;
        _ = options;
        const var_text = NodeUtils.getNodeText(node, source);
        try formatVariableWithSpacing(var_text, builder);
    }

    /// Format variable declaration with proper spacing around = and keywords
    pub fn formatVariableWithSpacing(var_text: []const u8, builder: *LineBuilder) !void {
        // Use consolidated Zig spacing helper instead of duplicate logic
        try ZigFormattingHelpers.formatWithZigSpacing(var_text, builder);
    }

    /// Check if text represents a variable declaration
    pub fn isVariableDecl(text: []const u8) bool {
        const decl_type = ZigFormattingHelpers.classifyDeclaration(text);
        return decl_type == .variable or decl_type == .constant;
    }

    /// Extract variable name from declaration
    pub fn extractVariableName(text: []const u8) ?[]const u8 {
        return ZigFormattingHelpers.extractDeclarationName(text);
    }

    /// Check if variable is a constant
    pub fn isConstant(text: []const u8) bool {
        return std.mem.startsWith(u8, text, "const ");
    }

    /// Check if variable is comptime
    pub fn isComptime(text: []const u8) bool {
        return std.mem.startsWith(u8, text, "comptime ") or 
               std.mem.indexOf(u8, text, " comptime ") != null;
    }

    /// Check if variable has type annotation
    pub fn hasTypeAnnotation(text: []const u8) bool {
        return std.mem.indexOf(u8, text, ":") != null;
    }

    /// Extract type from variable declaration if present
    pub fn extractType(text: []const u8) ?[]const u8 {
        if (std.mem.indexOf(u8, text, ":")) |colon_pos| {
            const after_colon = text[colon_pos + 1..];
            if (std.mem.indexOf(u8, after_colon, "=")) |equals_pos| {
                return std.mem.trim(u8, after_colon[0..equals_pos], " \t");
            } else {
                return std.mem.trim(u8, after_colon, " \t");
            }
        }
        return null;
    }
};