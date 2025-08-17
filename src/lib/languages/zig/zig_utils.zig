const std = @import("std");
const LineBuilder = @import("../../parsing/formatter.zig").LineBuilder;
const FormatterOptions = @import("../../parsing/formatter.zig").FormatterOptions;
const collections = @import("../../core/collections.zig");
const delimiters = @import("../../text/delimiters.zig");

/// Zig-specific utilities extracted from generic helpers
pub const ZigUtils = struct {

    /// Split text by delimiter, respecting nested structures
    /// Delegates to common language-agnostic utility
    pub fn splitByDelimiter(allocator: std.mem.Allocator, text: []const u8, delimiter: u8) ![][]const u8 {
        return delimiters.splitRespectingNesting(allocator, text, delimiter);
    }

    /// Format function signature with proper spacing
    pub fn formatFunctionSignature(allocator: std.mem.Allocator, builder: *LineBuilder, signature: []const u8, options: FormatterOptions) !void {
        _ = allocator;
        _ = options;
        // Simple signature formatting for Zig
        const trimmed = std.mem.trim(u8, signature, " \t\n\r");
        try formatDeclarationWithSpacing(trimmed, builder);
    }

    /// Format declaration with consistent spacing
    pub fn formatDeclarationWithSpacing(declaration: []const u8, builder: *LineBuilder) !void {
        // Add proper spacing around keywords and operators
        var i: usize = 0;
        while (i < declaration.len) : (i += 1) {
            const char = declaration[i];
            
            // Handle specific Zig keywords
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
            } else if (declaration.len > i + 1 and std.mem.eql(u8, declaration[i..i+2], "fn")) {
                try builder.append("fn ");
                i += 1; // Will be incremented by loop
                // Skip any following whitespace
                while (i + 1 < declaration.len and (declaration[i + 1] == ' ' or declaration[i + 1] == '\t')) {
                    i += 1;
                }
            } else if (char == '=') {
                // Add spacing around equals
                try builder.append(" = ");
                // Skip any following whitespace
                while (i + 1 < declaration.len and (declaration[i + 1] == ' ' or declaration[i + 1] == '\t')) {
                    i += 1;
                }
            } else if (char == ':') {
                // Zig-style colon spacing: no space before, space after
                try builder.append(": ");
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

    /// Check if text represents a function declaration
    pub fn isFunctionDeclaration(text: []const u8) bool {
        const trimmed = std.mem.trim(u8, text, " \t\n\r");
        return std.mem.indexOf(u8, trimmed, "fn ") != null and
               std.mem.indexOf(u8, trimmed, "@import") == null;
    }

    /// Extract return type from function signature
    pub fn extractReturnType(signature: []const u8) ?[]const u8 {
        // Find closing paren and look for return type
        if (std.mem.lastIndexOf(u8, signature, ")")) |paren_pos| {
            const after_paren = std.mem.trim(u8, signature[paren_pos + 1..], " \t");
            if (after_paren.len > 0 and !std.mem.startsWith(u8, after_paren, "{")) {
                if (std.mem.indexOf(u8, after_paren, " {")) |brace_pos| {
                    return std.mem.trim(u8, after_paren[0..brace_pos], " \t");
                } else {
                    return std.mem.trim(u8, after_paren, " \t\n\r");
                }
            }
        }
        return null;
    }

    /// Check if character is whitespace
    pub fn isWhitespace(char: u8) bool {
        return char == ' ' or char == '\t' or char == '\n' or char == '\r';
    }

    /// Format operator spacing
    pub fn formatOperatorSpacing(allocator: std.mem.Allocator, text: []const u8, operators: []const []const u8) ![]const u8 {
        var result = std.ArrayList(u8).init(allocator);
        defer result.deinit();

        var i: usize = 0;
        while (i < text.len) {
            var found_operator = false;
            
            // Check for operators
            for (operators) |op| {
                if (i + op.len <= text.len and std.mem.eql(u8, text[i..i + op.len], op)) {
                    // Add space before operator if not present
                    if (result.items.len > 0 and !isWhitespace(result.items[result.items.len - 1])) {
                        try result.append(' ');
                    }
                    try result.appendSlice(op);
                    // Add space after operator if not present
                    if (i + op.len < text.len and !isWhitespace(text[i + op.len])) {
                        try result.append(' ');
                    }
                    i += op.len;
                    found_operator = true;
                    break;
                }
            }
            
            if (!found_operator) {
                try result.append(text[i]);
                i += 1;
            }
        }

        return result.toOwnedSlice();
    }
};