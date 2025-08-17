const std = @import("std");
const ts = @import("tree-sitter");
const LineBuilder = @import("../../parsing/formatter.zig").LineBuilder;
const FormatterOptions = @import("../../parsing/formatter.zig").FormatterOptions;
const NodeUtils = @import("../../language/node_utils.zig").NodeUtils;

// Import all formatters
const FormatFunction = @import("format_function.zig").FormatFunction;
const FormatDeclaration = @import("format_declaration.zig").FormatDeclaration;
const FormatImport = @import("format_import.zig").FormatImport;
const FormatVariable = @import("format_variable.zig").FormatVariable;
const FormatTest = @import("format_test.zig").FormatTest;
const FormatContainer = @import("format_container.zig").FormatContainer;

pub const ZigNodeDispatcher = struct {
    /// Main entry point for formatting any Zig node
    pub fn formatNode(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) anyerror!void {
        const node_type = node.kind();

        // Node type dispatching logic

        // Dispatch based on node type and content
        if (std.mem.eql(u8, node_type, "VarDecl")) {
            try handleVarDecl(node, source, builder, depth, options);
        } else if (std.mem.eql(u8, node_type, "TestDecl")) {
            try FormatTest.formatTest(node, source, builder, depth, options);
        } else if (std.mem.eql(u8, node_type, "Decl")) {
            try handleDecl(node, source, builder, depth, options);
        } else if (std.mem.eql(u8, node_type, "source_file")) {
            try handleSourceFile(node, source, builder, depth, options);
        } else {
            // For unknown nodes, just append text without recursion
            try NodeUtils.appendNodeText(node, source, builder);
        }
    }

    /// Handle VarDecl nodes by analyzing content
    fn handleVarDecl(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
        const node_text = NodeUtils.getNodeText(node, source);

        if (FormatFunction.isFunctionDecl(node_text)) {
            try FormatFunction.formatFunction(node, source, builder, depth, options);
        } else if (FormatDeclaration.isTypeDecl(node_text)) {
            try handleTypeDecl(node, source, builder, depth, options, node_text);
        } else if (FormatImport.isImportDecl(node_text)) {
            try FormatImport.formatImport(node, source, builder, depth, options);
        } else {
            try FormatVariable.formatVariable(node, source, builder, depth, options);
        }
    }

    /// Handle Decl nodes (similar to VarDecl but different tree-sitter node type)
    fn handleDecl(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
        const node_text = NodeUtils.getNodeText(node, source);

        if (FormatFunction.isFunctionDecl(node_text)) {
            try FormatFunction.formatFunction(node, source, builder, depth, options);
        } else if (FormatDeclaration.isTypeDecl(node_text)) {
            try handleTypeDecl(node, source, builder, depth, options, node_text);
        } else if (FormatImport.isImportDecl(node_text)) {
            try FormatImport.formatImport(node, source, builder, depth, options);
        } else {
            try FormatVariable.formatVariable(node, source, builder, depth, options);
        }
    }

    /// Handle type declarations (struct/enum/union)
    fn handleTypeDecl(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions, node_text: []const u8) !void {
        if (isStructDecl(node_text)) {
            try FormatContainer.formatStruct(node, source, builder, depth, options);
        } else if (isEnumDecl(node_text)) {
            try FormatContainer.formatEnum(node, source, builder, depth, options);
        } else if (isUnionDecl(node_text)) {
            try FormatContainer.formatUnion(node, source, builder, depth, options);
        } else {
            // Generic type declaration
            try FormatDeclaration.formatDeclaration(node_text, builder);
        }
    }

    /// Handle source file (top-level container)
    fn handleSourceFile(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
        const child_count = node.childCount();
        var i: u32 = 0;
        var prev_was_decl = false;
        
        while (i < child_count) : (i += 1) {
            if (node.child(i)) |child| {
                const child_type = child.kind();
                const child_text = NodeUtils.getNodeText(child, source);
                
                // Handle pub + following declaration as a single unit
                if (std.mem.eql(u8, child_type, "pub") and i + 1 < child_count) {
                    if (node.child(i + 1)) |next_child| {
                        const next_type = next_child.kind();
                        const next_text = NodeUtils.getNodeText(next_child, source);
                        
                        // Add spacing before pub declaration
                        if (prev_was_decl) {
                            try builder.newline();
                        }
                        
                        // Combine pub + declaration
                        try formatPubDecl(child_text, next_text, next_type, source, builder, depth, options);
                        try builder.newline();
                        
                        prev_was_decl = true;
                        i += 1; // Skip the next node since we processed it
                        continue;
                    }
                }
                
                // Add spacing between top-level declarations
                if (prev_was_decl and isTopLevelDecl(child_type, child_text)) {
                    try builder.newline();
                }
                
                try formatNode(child, source, builder, depth, options);
                
                if (isTopLevelDecl(child_type, child_text)) {
                    try builder.newline();
                    prev_was_decl = true;
                } else {
                    prev_was_decl = false;
                }
            }
        }
    }

    /// Format pub + declaration combination
    fn formatPubDecl(pub_text: []const u8, decl_text: []const u8, decl_type: []const u8, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
        _ = source; // Unused parameter
        
        // Create a synthetic node for the declaration part
        var pub_decl_text = std.ArrayList(u8).init(std.heap.page_allocator);
        defer pub_decl_text.deinit();
        
        try pub_decl_text.appendSlice(pub_text);
        try pub_decl_text.appendSlice(" ");
        try pub_decl_text.appendSlice(decl_text);
        
        // Dispatch based on declaration type
        if (FormatFunction.isFunctionDecl(decl_text)) {
            try FormatFunction.formatFunctionWithSpacing(pub_decl_text.items, builder, options);
        } else if (FormatDeclaration.isTypeDecl(decl_text)) {
            try FormatDeclaration.formatDeclaration(pub_decl_text.items, builder);
        } else if (FormatImport.isImportDecl(decl_text)) {
            try FormatImport.formatImportWithSpacing(pub_decl_text.items, builder);
        } else {
            try FormatVariable.formatVariableWithSpacing(pub_decl_text.items, builder);
        }
        
        _ = decl_type; // Unused but kept for future use
        _ = depth; // Unused but kept for API consistency
    }

    /// Check if this is a top-level declaration that needs spacing
    fn isTopLevelDecl(node_type: []const u8, text: []const u8) bool {
        // Check node type first
        if (std.mem.eql(u8, node_type, "VarDecl") or 
            std.mem.eql(u8, node_type, "Decl") or
            std.mem.eql(u8, node_type, "TestDecl")) {
            return true;
        }
        
        // Check text content for declarations that might be missed
        const patterns = [_][]const u8{
            "const ", "var ", "pub ", "test ", "fn ", "struct", "enum", "union"
        };
        
        for (patterns) |pattern| {
            if (std.mem.indexOf(u8, text, pattern) != null) {
                return true;
            }
        }
        
        return false;
    }

    /// Check if text represents a struct declaration
    fn isStructDecl(text: []const u8) bool {
        return std.mem.indexOf(u8, text, "struct") != null;
    }

    /// Check if text represents an enum declaration
    fn isEnumDecl(text: []const u8) bool {
        return std.mem.indexOf(u8, text, "enum") != null;
    }

    /// Check if text represents a union declaration
    fn isUnionDecl(text: []const u8) bool {
        return std.mem.indexOf(u8, text, "union") != null;
    }
};