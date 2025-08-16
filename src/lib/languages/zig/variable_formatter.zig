const std = @import("std");
const ts = @import("tree-sitter");
const LineBuilder = @import("../../parsing/formatter.zig").LineBuilder;
const FormatterOptions = @import("../../parsing/formatter.zig").FormatterOptions;
const NodeUtils = @import("../../language/node_utils.zig").NodeUtils;

pub const ZigVariableFormatter = struct {
    /// Format Zig variable declaration
    pub fn formatVariable(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
        _ = depth;
        _ = options;
        const var_text = NodeUtils.getNodeText(node, source);
        try formatVariableWithSpacing(var_text, builder);
    }

    /// Format variable declaration with proper spacing around = and keywords
    pub fn formatVariableWithSpacing(var_text: []const u8, builder: *LineBuilder) !void {
        var i: usize = 0;
        var in_string = false;
        var escape_next = false;
        var in_comment = false;
        var after_colon = false;

        while (i < var_text.len) {
            const c = var_text[i];

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

            if (c == '"' and !in_comment) {
                in_string = !in_string;
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            if (!in_string and i + 1 < var_text.len and var_text[i] == '/' and var_text[i + 1] == '/') {
                in_comment = true;
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            if (in_comment and c == '\n') {
                in_comment = false;
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            if (in_string or in_comment) {
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            if (c == ':') {
                // Handle type annotations - remove space before colon, ensure space after
                while (builder.buffer.items.len > 0 and 
                       builder.buffer.items[builder.buffer.items.len - 1] == ' ') {
                    _ = builder.buffer.pop();
                }
                try builder.append(":");
                after_colon = true;
                i += 1;
                
                // Ensure space after colon if next char isn't space
                if (i < var_text.len and var_text[i] != ' ') {
                    try builder.append(" ");
                }
                continue;
            }

            if (c == '=') {
                // Ensure space before =
                if (builder.buffer.items.len > 0 and 
                    builder.buffer.items[builder.buffer.items.len - 1] != ' ') {
                    try builder.append(" ");
                }
                try builder.append("=");
                i += 1;
                
                // Ensure space after = if next char isn't space
                if (i < var_text.len and var_text[i] != ' ') {
                    try builder.append(" ");
                }
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
    }

    /// Check if text represents a variable declaration
    pub fn isVariableDecl(text: []const u8) bool {
        // Check for const, var, or comptime patterns
        const patterns = [_][]const u8{ "const ", "var ", "comptime " };
        for (patterns) |pattern| {
            if (std.mem.startsWith(u8, text, pattern)) {
                return true;
            }
        }
        return false;
    }

    /// Extract variable name from declaration
    pub fn extractVariableName(text: []const u8) ?[]const u8 {
        // Look for pattern: (const|var|comptime) name
        var tokens = std.mem.splitSequence(u8, text, " ");
        _ = tokens.next(); // Skip const/var/comptime
        
        if (tokens.next()) |name_part| {
            // Find the name (before : or =)
            if (std.mem.indexOf(u8, name_part, ":")) |colon_pos| {
                return std.mem.trim(u8, name_part[0..colon_pos], " \t");
            }
            if (std.mem.indexOf(u8, name_part, "=")) |equals_pos| {
                return std.mem.trim(u8, name_part[0..equals_pos], " \t");
            }
            return std.mem.trim(u8, name_part, " \t");
        }
        return null;
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