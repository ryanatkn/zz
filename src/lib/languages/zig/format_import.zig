const std = @import("std");
const ts = @import("tree-sitter");
const LineBuilder = @import("../../parsing/formatter.zig").LineBuilder;
const FormatterOptions = @import("../../parsing/formatter.zig").FormatterOptions;
const NodeUtils = @import("../../language/node_utils.zig").NodeUtils;
const ZigFormattingHelpers = @import("formatting_helpers.zig").ZigFormattingHelpers;

pub const FormatImport = struct {
    /// Format Zig @import statement
    pub fn formatImport(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
        _ = depth;
        _ = options;
        const import_text = NodeUtils.getNodeText(node, source);
        try formatImportWithSpacing(import_text, builder);
    }

    /// Format import statement with proper spacing around = and keywords
    pub fn formatImportWithSpacing(import_text: []const u8, builder: *LineBuilder) !void {
        // Use consolidated Zig spacing helper instead of duplicate logic
        try ZigFormattingHelpers.formatWithZigSpacing(import_text, builder);
    }

    /// Check if text represents an @import declaration
    pub fn isImportDecl(text: []const u8) bool {
        return ZigFormattingHelpers.classifyDeclaration(text) == .import;
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