const std = @import("std");
const ts = @import("tree-sitter");
const LineBuilder = @import("../../parsing/formatter.zig").LineBuilder;
const FormatterOptions = @import("../../parsing/formatter.zig").FormatterOptions;
const NodeUtils = @import("../../language/node_utils.zig").NodeUtils;

pub const ZigImportFormatter = struct {
    /// Format Zig @import statement
    pub fn formatImport(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
        _ = depth;
        _ = options;
        const import_text = NodeUtils.getNodeText(node, source);
        try formatImportWithSpacing(import_text, builder);
    }

    /// Format import statement with proper spacing around = and keywords
    pub fn formatImportWithSpacing(import_text: []const u8, builder: *LineBuilder) !void {
        var i: usize = 0;
        var in_string = false;
        var escape_next = false;
        var after_equals = false;

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

            if (c == '=') {
                // Ensure space before =
                if (builder.buffer.items.len > 0 and 
                    builder.buffer.items[builder.buffer.items.len - 1] != ' ') {
                    try builder.append(" ");
                }
                try builder.append("=");
                after_equals = true;
                i += 1;
                
                // Ensure space after = if next char isn't space
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

    /// Check if text represents an @import declaration
    pub fn isImportDecl(text: []const u8) bool {
        // Look for @import pattern
        return std.mem.indexOf(u8, text, "@import") != null;
    }

    /// Extract imported module name from @import statement
    pub fn extractImportPath(text: []const u8) ?[]const u8 {
        // Find @import("path") and extract the path
        if (std.mem.indexOf(u8, text, "@import(\"")) |start| {
            const path_start = start + "@import(\"".len;
            if (std.mem.indexOfPos(u8, text, path_start, "\")")) |end| {
                return text[path_start..end];
            }
        }
        return null;
    }

    /// Check if import is a standard library import
    pub fn isStdImport(text: []const u8) bool {
        if (extractImportPath(text)) |path| {
            return std.mem.eql(u8, path, "std") or std.mem.startsWith(u8, path, "std.");
        }
        return false;
    }

    /// Check if import is a relative import (starts with .)
    pub fn isRelativeImport(text: []const u8) bool {
        if (extractImportPath(text)) |path| {
            return std.mem.startsWith(u8, path, "./") or std.mem.startsWith(u8, path, "../");
        }
        return false;
    }
};