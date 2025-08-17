const std = @import("std");
const ts = @import("tree-sitter");
const LineBuilder = @import("../../parsing/formatter.zig").LineBuilder;
const FormatterOptions = @import("../../parsing/formatter.zig").FormatterOptions;
const NodeUtils = @import("../../language/node_utils.zig").NodeUtils;

pub const FormatImport = struct {
    /// Format TypeScript import statement
    pub fn formatImportStatement(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
        _ = depth;
        _ = options;
        
        const import_text = NodeUtils.getNodeText(node, source);
        try builder.appendIndent();
        try formatImportWithSpacing(import_text, builder);
        try builder.newline();
    }

    /// Format export statement
    pub fn formatExportStatement(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
        _ = depth;
        _ = options;
        
        const export_text = NodeUtils.getNodeText(node, source);
        try builder.appendIndent();
        try formatExportWithSpacing(export_text, builder);
        try builder.newline();
    }

    /// Format import statement with proper spacing
    fn formatImportWithSpacing(import_text: []const u8, builder: *LineBuilder) !void {
        var i: usize = 0;
        var in_string = false;
        var string_char: u8 = 0;
        var escape_next = false;
        var in_braces = false;
        var brace_depth: u32 = 0;

        while (i < import_text.len) {
            const c = import_text[i];

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

            if (!in_string and (c == '"' or c == '\'' or c == '`')) {
                in_string = true;
                string_char = c;
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            if (in_string and c == string_char) {
                in_string = false;
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            if (in_string) {
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            if (c == '{') {
                in_braces = true;
                brace_depth += 1;
                try builder.append(&[_]u8{c});
                i += 1;
                
                // Add space after opening brace if next char isn't space
                if (i < import_text.len and import_text[i] != ' ') {
                    try builder.append(" ");
                }
                continue;
            }

            if (c == '}') {
                if (brace_depth > 0) {
                    brace_depth -= 1;
                    if (brace_depth == 0) {
                        in_braces = false;
                    }
                }
                
                // Add space before closing brace if previous char isn't space
                if (builder.buffer.items.len > 0 and 
                    builder.buffer.items[builder.buffer.items.len - 1] != ' ') {
                    try builder.append(" ");
                }
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            if (c == ',' and in_braces) {
                try builder.append(&[_]u8{c});
                i += 1;
                
                // Add space after comma
                if (i < import_text.len and import_text[i] != ' ') {
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

    /// Format export statement with proper spacing
    fn formatExportWithSpacing(export_text: []const u8, builder: *LineBuilder) !void {
        var i: usize = 0;
        var in_string = false;
        var string_char: u8 = 0;
        var escape_next = false;
        var in_braces = false;
        var brace_depth: u32 = 0;

        while (i < export_text.len) {
            const c = export_text[i];

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

            if (!in_string and (c == '"' or c == '\'' or c == '`')) {
                in_string = true;
                string_char = c;
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            if (in_string and c == string_char) {
                in_string = false;
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            if (in_string) {
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            if (c == '{') {
                in_braces = true;
                brace_depth += 1;
                try builder.append(&[_]u8{c});
                i += 1;
                
                // Add space after opening brace if next char isn't space
                if (i < export_text.len and export_text[i] != ' ') {
                    try builder.append(" ");
                }
                continue;
            }

            if (c == '}') {
                if (brace_depth > 0) {
                    brace_depth -= 1;
                    if (brace_depth == 0) {
                        in_braces = false;
                    }
                }
                
                // Add space before closing brace if previous char isn't space
                if (builder.buffer.items.len > 0 and 
                    builder.buffer.items[builder.buffer.items.len - 1] != ' ') {
                    try builder.append(" ");
                }
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            if (c == ',' and in_braces) {
                try builder.append(&[_]u8{c});
                i += 1;
                
                // Add space after comma
                if (i < export_text.len and export_text[i] != ' ') {
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

    /// Check if statement is an import
    pub fn isImportStatement(node_type: []const u8) bool {
        return std.mem.eql(u8, node_type, "import_statement") or
               std.mem.eql(u8, node_type, "import_declaration");
    }

    /// Check if statement is an export
    pub fn isExportStatement(node_type: []const u8) bool {
        return std.mem.eql(u8, node_type, "export_statement") or
               std.mem.eql(u8, node_type, "export_declaration");
    }

    /// Extract module path from import/export statement
    pub fn extractModulePath(statement: []const u8) ?[]const u8 {
        // Look for from "path" or import "path"
        if (std.mem.indexOf(u8, statement, "from ")) |from_pos| {
            const after_from = statement[from_pos + 5..];
            return extractQuotedString(after_from);
        } else if (std.mem.indexOf(u8, statement, "import ")) |import_pos| {
            const after_import = statement[import_pos + 7..];
            return extractQuotedString(after_import);
        }
        return null;
    }

    /// Extract quoted string (for module paths)
    fn extractQuotedString(text: []const u8) ?[]const u8 {
        const trimmed = std.mem.trim(u8, text, " \t");
        
        // Find first quote
        var quote_start: ?usize = null;
        var quote_char: u8 = 0;
        
        for (trimmed, 0..) |c, i| {
            if (c == '"' or c == '\'' or c == '`') {
                quote_start = i;
                quote_char = c;
                break;
            }
        }
        
        if (quote_start) |start| {
            // Find matching closing quote
            for (trimmed[start + 1..], 0..) |c, i| {
                if (c == quote_char) {
                    return trimmed[start + 1..start + 1 + i];
                }
            }
        }
        
        return null;
    }

    /// Check if import is a default import
    pub fn isDefaultImport(statement: []const u8) bool {
        // Look for patterns like: import Name from "module"
        if (std.mem.indexOf(u8, statement, "import ")) |import_pos| {
            const after_import = statement[import_pos + 7..];
            if (std.mem.indexOf(u8, after_import, " from ")) |from_pos| {
                const import_part = std.mem.trim(u8, after_import[0..from_pos], " \t");
                // Default import doesn't have braces
                return std.mem.indexOf(u8, import_part, "{") == null;
            }
        }
        return false;
    }

    /// Check if import is a named import
    pub fn isNamedImport(statement: []const u8) bool {
        return std.mem.indexOf(u8, statement, "{") != null and
               std.mem.indexOf(u8, statement, "}") != null;
    }

    /// Check if import is a namespace import
    pub fn isNamespaceImport(statement: []const u8) bool {
        return std.mem.indexOf(u8, statement, "* as ") != null;
    }

    /// Extract imported names from named import
    pub fn extractImportedNames(statement: []const u8) ?[]const u8 {
        if (std.mem.indexOf(u8, statement, "{")) |start| {
            if (std.mem.indexOf(u8, statement, "}")) |end| {
                return std.mem.trim(u8, statement[start + 1..end], " \t");
            }
        }
        return null;
    }
};