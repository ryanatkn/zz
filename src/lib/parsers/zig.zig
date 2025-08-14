const std = @import("std");
const ts = @import("tree-sitter");
const ExtractionFlags = @import("../parser.zig").ExtractionFlags;
const AstNode = @import("../ast.zig").AstNode;

extern fn tree_sitter_zig() callconv(.C) *ts.Language;

pub fn extractSimple(source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) !void {
    var lines = std.mem.tokenizeScalar(u8, source, '\n');
    
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        
        // Extract based on flags
        if (flags.signatures) {
            if (std.mem.startsWith(u8, trimmed, "pub fn") or 
                std.mem.startsWith(u8, trimmed, "fn")) {
                // Extract until the opening brace or semicolon
                if (std.mem.indexOf(u8, line, "{")) |brace_pos| {
                    try result.appendSlice(line[0..brace_pos + 1]);
                    try result.append('\n');
                } else {
                    try result.appendSlice(line);
                    try result.append('\n');
                }
            }
        }
        
        if (flags.types) {
            if (std.mem.startsWith(u8, trimmed, "pub const") or
                std.mem.startsWith(u8, trimmed, "const") or
                std.mem.startsWith(u8, trimmed, "pub var") or
                std.mem.startsWith(u8, trimmed, "var")) {
                try result.appendSlice(line);
                try result.append('\n');
            }
        }
        
        if (flags.docs) {
            if (std.mem.startsWith(u8, trimmed, "///") or
                std.mem.startsWith(u8, trimmed, "//!")) {
                try result.appendSlice(line);
                try result.append('\n');
            }
        }
        
        if (flags.imports) {
            if (std.mem.indexOf(u8, trimmed, "@import") != null) {
                try result.appendSlice(line);
                try result.append('\n');
            }
        }
        
        if (flags.errors) {
            if (std.mem.indexOf(u8, line, "error") != null or
                std.mem.indexOf(u8, line, "catch") != null or
                std.mem.indexOf(u8, line, "try") != null) {
                try result.appendSlice(line);
                try result.append('\n');
            }
        }
        
        if (flags.tests) {
            if (std.mem.startsWith(u8, trimmed, "test")) {
                try result.appendSlice(line);
                try result.append('\n');
            }
        }
    }
}

/// AST-based extraction using tree-sitter
pub fn walkNode(allocator: std.mem.Allocator, root: *const AstNode, source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) !void {
    _ = allocator;
    try walkNodeRecursive(root.ts_node, source, flags, result);
}

pub fn extractWithTreeSitter(
    allocator: std.mem.Allocator,
    source: []const u8,
    flags: ExtractionFlags
) ![]const u8 {
    const parser = ts.Parser.create();
    defer parser.destroy();
    
    try parser.setLanguage(tree_sitter_zig());
    const tree = parser.parseString(source, null) orelse return error.ParseFailed;
    defer tree.destroy();
    
    const root = tree.rootNode();
    
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();
    
    try walkNodeRecursive(root, source, flags, &result);
    
    return result.toOwnedSlice();
}

fn walkNodeRecursive(node: ts.Node, source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) !void {
    const node_type = node.kind();
    
    // Extract based on node type and flags
    if (flags.signatures) {
        if (std.mem.eql(u8, node_type, "function_declaration")) {
            const start = node.startByte();
            const end = node.endByte();
            try result.appendSlice(source[start..end]);
            try result.append('\n');
            return; // Don't recurse into function bodies for signatures
        }
    }
    
    if (flags.types) {
        if (std.mem.eql(u8, node_type, "struct_declaration") or 
            std.mem.eql(u8, node_type, "enum_declaration") or
            std.mem.eql(u8, node_type, "union_declaration")) {
            const start = node.startByte();
            const end = node.endByte();
            try result.appendSlice(source[start..end]);
            try result.append('\n');
            return; // Don't recurse into type bodies
        }
    }
    
    if (flags.docs) {
        if (std.mem.eql(u8, node_type, "doc_comment") or
            std.mem.eql(u8, node_type, "container_doc_comment")) {
            const start = node.startByte();
            const end = node.endByte();
            try result.appendSlice(source[start..end]);
            try result.append('\n');
        }
    }
    
    if (flags.tests) {
        if (std.mem.eql(u8, node_type, "test_declaration")) {
            const start = node.startByte();
            const end = node.endByte();
            try result.appendSlice(source[start..end]);
            try result.append('\n');
            return; // Don't recurse into test bodies
        }
    }
    
    // Recurse into children
    const child_count = node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.child(i) orelse continue;
        try walkNodeRecursive(child, source, flags, result);
    }
}