const std = @import("std");
const LineBuilder = @import("../../parsing/formatter.zig").LineBuilder;

/// Zig-specific declaration formatting functionality
pub const ZigDeclarationFormatter = struct {

    /// Format Zig declaration with proper spacing around keywords
    pub fn formatDeclaration(declaration: []const u8, builder: *LineBuilder) !void {
        var i: usize = 0;
        while (i < declaration.len) : (i += 1) {
            const char = declaration[i];
            
            // Handle "pub const" or "const"
            if (declaration.len > i + 2 and std.mem.eql(u8, declaration[i..i+3], "pub")) {
                try builder.append("pub ");
                i += 2; // Will be incremented by loop
                // Skip any following whitespace
                while (i + 1 < declaration.len and (declaration[i + 1] == ' ' or declaration[i + 1] == '\t')) {
                    i += 1;
                }
            } else if (declaration.len > i + 4 and std.mem.eql(u8, declaration[i..i+5], "const")) {
                try builder.append("const ");
                i += 4; // Will be incremented by loop
                // Skip any following whitespace
                while (i + 1 < declaration.len and (declaration[i + 1] == ' ' or declaration[i + 1] == '\t')) {
                    i += 1;
                }
            } else if (char != ' ' and char != '\t') {
                // Regular character, append as-is
                try builder.append(&[_]u8{char});
            } else if (char == ' ') {
                // Preserve single spaces, skip multiple
                if (i == 0 or declaration[i-1] != ' ') {
                    try builder.append(" ");
                }
            }
        }
    }

    /// Format struct declaration with proper spacing
    pub fn formatStructDeclaration(struct_text: []const u8, builder: *LineBuilder) !void {
        const trimmed = std.mem.trim(u8, struct_text, " \t\n\r");
        
        // Find "=struct" to separate declaration from body
        if (std.mem.indexOf(u8, trimmed, "=struct")) |struct_pos| {
            const declaration = std.mem.trim(u8, trimmed[0..struct_pos], " \t");
            // Add proper spacing around keywords and identifiers
            try formatDeclaration(declaration, builder);
        } else {
            // Fallback: just append the text
            try builder.append(trimmed);
        }
    }

    /// Format enum declaration with proper spacing
    pub fn formatEnumDeclaration(enum_text: []const u8, builder: *LineBuilder) !void {
        const trimmed = std.mem.trim(u8, enum_text, " \t\n\r");
        
        // Find "=enum" or "enum" to separate declaration from body
        if (std.mem.indexOf(u8, trimmed, "=enum")) |enum_pos| {
            const declaration = std.mem.trim(u8, trimmed[0..enum_pos], " \t");
            // Add proper spacing around keywords and identifiers
            try formatDeclaration(declaration, builder);
        } else if (std.mem.indexOf(u8, trimmed, "enum")) |enum_pos| {
            const declaration = std.mem.trim(u8, trimmed[0..enum_pos], " \t");
            if (declaration.len > 0) {
                try formatDeclaration(declaration, builder);
            }
        } else {
            // Fallback: just append the text
            try builder.append(trimmed);
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
            try formatDeclaration(declaration, builder);
            // Add the union part with proper spacing
            try builder.append(" = union(enum)");
        } else if (std.mem.indexOf(u8, trimmed, "=union")) |union_pos| {
            // Regular union: const Value=union{...
            const declaration = std.mem.trim(u8, trimmed[0..union_pos], " \t");
            try formatDeclaration(declaration, builder);
            // Add the union part with proper spacing
            try builder.append(" = union");
        } else if (std.mem.indexOf(u8, trimmed, " union(")) |union_pos| {
            // Space before union(
            const declaration = std.mem.trim(u8, trimmed[0..union_pos], " \t");
            if (declaration.len > 0) {
                try formatDeclaration(declaration, builder);
            }
            try builder.append(" union(enum)");
        } else if (std.mem.indexOf(u8, trimmed, " union")) |union_pos| {
            // Space before union
            const declaration = std.mem.trim(u8, trimmed[0..union_pos], " \t");
            if (declaration.len > 0) {
                try formatDeclaration(declaration, builder);
            }
            try builder.append(" union");
        } else {
            // Fallback: just output const Name if we can extract it
            if (std.mem.indexOf(u8, trimmed, "const ")) |_| {
                // Extract the name between const and = or {
                if (std.mem.indexOf(u8, trimmed, "=")) |eq_pos| {
                    const decl = std.mem.trim(u8, trimmed[0..eq_pos], " \t");
                    try formatDeclaration(decl, builder);
                } else {
                    try builder.append(trimmed);
                }
            } else {
                try builder.append(trimmed);
            }
        }
    }

    /// Extract name from Zig declaration
    pub fn extractName(text: []const u8) ?[]const u8 {
        const trimmed = std.mem.trim(u8, text, " \t\n\r");
        
        // Handle both "const Name = struct" and "pub const Name = struct"
        var start_pos: usize = 0;
        if (std.mem.startsWith(u8, trimmed, "pub const ")) {
            start_pos = 10; // length of "pub const "
        } else if (std.mem.startsWith(u8, trimmed, "const ")) {
            start_pos = 6; // length of "const "
        } else if (std.mem.startsWith(u8, trimmed, "pub fn ")) {
            start_pos = 7; // length of "pub fn "
        } else if (std.mem.startsWith(u8, trimmed, "fn ")) {
            start_pos = 3; // length of "fn "
        } else {
            return null;
        }
        
        // Find the end of the name (before " =" or "(")
        var end_pos: usize = trimmed.len;
        if (std.mem.indexOfPos(u8, trimmed, start_pos, " =")) |equals_pos| {
            end_pos = equals_pos;
        } else if (std.mem.indexOfPos(u8, trimmed, start_pos, "(")) |paren_pos| {
            end_pos = paren_pos;
        }
        
        if (end_pos > start_pos) {
            const name = std.mem.trim(u8, trimmed[start_pos..end_pos], " \t");
            if (name.len > 0) {
                return name;
            }
        }
        
        return null;
    }

    /// Check if declaration is a function
    pub fn isFunctionDecl(text: []const u8) bool {
        const contains_fn = std.mem.indexOf(u8, text, "fn ") != null;
        const not_import = std.mem.indexOf(u8, text, "@import") == null;
        
        // Check if this starts with a function declaration pattern
        // Functions can contain struct/enum/union in their return statements
        const trimmed = std.mem.trim(u8, text, " \t\n\r");
        const starts_with_fn = std.mem.startsWith(u8, trimmed, "fn ") or
                               std.mem.startsWith(u8, trimmed, "pub fn ");
        
        // If it doesn't start with fn, then check for type definitions
        const not_type_def = if (!starts_with_fn) 
            std.mem.indexOf(u8, text, "struct") == null and
            std.mem.indexOf(u8, text, "enum") == null and
            std.mem.indexOf(u8, text, "union") == null
        else
            true; // If it starts with fn, it's a function regardless of content
        
        return contains_fn and not_import and not_type_def;
    }

    /// Check if declaration is a type definition
    pub fn isTypeDecl(text: []const u8) bool {
        const trimmed = std.mem.trim(u8, text, " \t\n\r");
        if (std.mem.startsWith(u8, trimmed, "const ") or std.mem.startsWith(u8, trimmed, "pub const ")) {
            return std.mem.indexOf(u8, text, "struct") != null or
                   std.mem.indexOf(u8, text, "enum") != null or
                   std.mem.indexOf(u8, text, "union") != null;
        }
        return false;
    }

    /// Check if declaration is an import
    pub fn isImportDecl(text: []const u8) bool {
        return std.mem.indexOf(u8, text, "@import") != null;
    }

    /// Check if declaration is a variable
    pub fn isVariableDecl(text: []const u8) bool {
        const trimmed = std.mem.trim(u8, text, " \t\n\r");
        return (std.mem.startsWith(u8, trimmed, "const ") or 
                std.mem.startsWith(u8, trimmed, "var ") or
                std.mem.startsWith(u8, trimmed, "pub const ") or
                std.mem.startsWith(u8, trimmed, "pub var ")) and
               !isFunctionDecl(text) and !isTypeDecl(text) and !isImportDecl(text);
    }
};