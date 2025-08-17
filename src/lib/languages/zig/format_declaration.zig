const std = @import("std");
const LineBuilder = @import("../../parsing/formatter.zig").LineBuilder;
const ZigFormattingHelpers = @import("formatting_helpers.zig").ZigFormattingHelpers;

/// Zig-specific declaration formatting functionality
pub const FormatDeclaration = struct {

    /// Format Zig declaration with proper spacing around keywords
    pub fn formatDeclaration(declaration: []const u8, builder: *LineBuilder) !void {
        // Use consolidated Zig spacing helper instead of manual character iteration
        try ZigFormattingHelpers.formatWithZigSpacing(declaration, builder);
    }

    /// Format struct declaration with proper spacing
    pub fn formatStructDeclaration(struct_text: []const u8, builder: *LineBuilder) !void {
        const trimmed = std.mem.trim(u8, struct_text, " \t\n\r");
        
        // Find "=struct" to separate declaration from body
        if (std.mem.indexOf(u8, trimmed, "=struct")) |struct_pos| {
            const declaration = std.mem.trim(u8, trimmed[0..struct_pos], " \t");
            // Use consolidated helper for proper spacing
            try ZigFormattingHelpers.formatWithZigSpacing(declaration, builder);
        } else {
            // Fallback: use consolidated helper
            try ZigFormattingHelpers.formatWithZigSpacing(trimmed, builder);
        }
    }

    /// Format enum declaration with proper spacing
    pub fn formatEnumDeclaration(enum_text: []const u8, builder: *LineBuilder) !void {
        const trimmed = std.mem.trim(u8, enum_text, " \t\n\r");
        
        // Find "=enum" or "enum" to separate declaration from body
        if (std.mem.indexOf(u8, trimmed, "=enum")) |enum_pos| {
            const declaration = std.mem.trim(u8, trimmed[0..enum_pos], " \t");
            // Use consolidated helper for proper spacing
            try ZigFormattingHelpers.formatWithZigSpacing(declaration, builder);
        } else if (std.mem.indexOf(u8, trimmed, "enum")) |enum_pos| {
            const declaration = std.mem.trim(u8, trimmed[0..enum_pos], " \t");
            if (declaration.len > 0) {
                try ZigFormattingHelpers.formatWithZigSpacing(declaration, builder);
            }
        } else {
            // Fallback: use consolidated helper
            try ZigFormattingHelpers.formatWithZigSpacing(trimmed, builder);
        }
    }

    /// Format union declaration with proper spacing
    pub fn formatUnionDeclaration(union_text: []const u8, builder: *LineBuilder) !void {
        const trimmed = std.mem.trim(u8, union_text, " \t\n\r");
        
        // Find the union keyword - could be =union or just union
        // Need to handle union(enum) specially
        if (std.mem.indexOf(u8, trimmed, "=union(")) |union_pos| {
            // Tagged union case: const Value=union(enum){...
            const declaration = std.mem.trim(u8, trimmed[0..union_pos], " \t");
            try ZigFormattingHelpers.formatWithZigSpacing(declaration, builder);
            // Add the union part with proper spacing
            try builder.append(" = union(enum)");
        } else if (std.mem.indexOf(u8, trimmed, "=union")) |union_pos| {
            // Regular union: const Value=union{...
            const declaration = std.mem.trim(u8, trimmed[0..union_pos], " \t");
            try ZigFormattingHelpers.formatWithZigSpacing(declaration, builder);
            // Add the union part with proper spacing
            try builder.append(" = union");
        } else if (std.mem.indexOf(u8, trimmed, " union(")) |union_pos| {
            // Space before union(
            const declaration = std.mem.trim(u8, trimmed[0..union_pos], " \t");
            if (declaration.len > 0) {
                try ZigFormattingHelpers.formatWithZigSpacing(declaration, builder);
            }
            try builder.append(" union(enum)");
        } else if (std.mem.indexOf(u8, trimmed, " union")) |union_pos| {
            // Space before union
            const declaration = std.mem.trim(u8, trimmed[0..union_pos], " \t");
            if (declaration.len > 0) {
                try ZigFormattingHelpers.formatWithZigSpacing(declaration, builder);
            }
            try builder.append(" union");
        } else {
            // Fallback: use consolidated helper
            if (std.mem.indexOf(u8, trimmed, "const ")) |_| {
                // Extract the name between const and = or {
                if (std.mem.indexOf(u8, trimmed, "=")) |eq_pos| {
                    const decl = std.mem.trim(u8, trimmed[0..eq_pos], " \t");
                    try ZigFormattingHelpers.formatWithZigSpacing(decl, builder);
                } else {
                    try ZigFormattingHelpers.formatWithZigSpacing(trimmed, builder);
                }
            } else {
                try ZigFormattingHelpers.formatWithZigSpacing(trimmed, builder);
            }
        }
    }

    /// Extract name from Zig declaration
    pub fn extractName(text: []const u8) ?[]const u8 {
        // Use consolidated helper for name extraction
        return ZigFormattingHelpers.extractDeclarationName(text);
    }

    /// Check if declaration is a function
    pub fn isFunctionDecl(text: []const u8) bool {
        // Use consolidated helper for declaration classification
        return ZigFormattingHelpers.classifyDeclaration(text) == .function;
    }

    /// Check if declaration is a type definition
    pub fn isTypeDecl(text: []const u8) bool {
        // Use consolidated helper for declaration classification
        return ZigFormattingHelpers.classifyDeclaration(text) == .type_definition;
    }

    /// Check if declaration is an import
    pub fn isImportDecl(text: []const u8) bool {
        // Use consolidated helper for declaration classification
        return ZigFormattingHelpers.classifyDeclaration(text) == .import;
    }

    /// Check if declaration is a variable
    pub fn isVariableDecl(text: []const u8) bool {
        // Use consolidated helper for declaration classification
        const decl_type = ZigFormattingHelpers.classifyDeclaration(text);
        return decl_type == .variable or decl_type == .constant;
    }
};