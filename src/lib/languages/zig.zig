const std = @import("std");
const ts = @import("tree-sitter");
const ExtractionFlags = @import("../language/flags.zig").ExtractionFlags;
const Node = @import("../tree_sitter/node.zig").Node;
const Visitor = @import("../tree_sitter/visitor.zig").Visitor;
const ExtractionContext = @import("../tree_sitter/visitor.zig").ExtractionContext;
const FormatterOptions = @import("../parsing/formatter.zig").FormatterOptions;
const LineBuilder = @import("../parsing/formatter.zig").LineBuilder;
const extractWithPatterns = @import("../extractor_base.zig").extractWithPatterns;
const LanguagePatterns = @import("../extractor_base.zig").LanguagePatterns;

/// Zig language implementation combining extraction, parsing, and formatting
pub const ZigLanguage = struct {
    pub const language_name = "zig";
    
    /// Get tree-sitter grammar for Zig
    pub fn grammar() *ts.Language {
        return tree_sitter_zig();
    }
    
    /// Extract Zig code using patterns or AST
    pub fn extract(allocator: std.mem.Allocator, source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) !void {
        _ = allocator; // Not needed for pattern-based extraction
        
        // If full flag is set, return full source
        if (flags.full) {
            try result.appendSlice(source);
            return;
        }
        
        // If no specific flags are set, return full source (backward compatibility)
        if (!flags.signatures and !flags.types and !flags.imports and !flags.docs and !flags.tests and !flags.errors and !flags.structure) {
            try result.appendSlice(source);
            return;
        }
        
        // Use pattern-based extraction for Zig
        const patterns = getZigPatterns();
        try extractWithPatterns(source, flags, result, patterns);
    }
    
    /// AST-based extraction visitor
    pub fn visitor(context: *ExtractionContext, node: *const Node) !void {
        // Extract based on node type and flags
        if (context.flags.signatures or context.flags.structure) {
            // Extract function definitions
            if (isFunctionNode(node.kind)) {
                try context.appendNode(node);
            }
        }
        
        if (context.flags.types or context.flags.structure) {
            // Extract type definitions (struct, enum, union, etc.)
            if (isTypeNode(node.kind)) {
                try context.appendNode(node);
            }
        }
        
        if (context.flags.imports) {
            // Extract @import statements
            if (isImportNode(node.kind)) {
                try context.appendNode(node);
            }
        }
        
        if (context.flags.docs) {
            // Extract documentation comments
            if (isDocNode(node.kind)) {
                try context.appendNode(node);
            }
        }
        
        if (context.flags.tests) {
            // Extract test blocks
            if (isTestNode(node.kind)) {
                try context.appendNode(node);
            }
        }
        
        if (context.flags.errors) {
            // Extract error definitions and error handling
            if (isErrorNode(node.kind)) {
                try context.appendNode(node);
            }
        }
    }
    
    /// Format Zig source code (delegate to external zig fmt)
    pub fn format(allocator: std.mem.Allocator, source: []const u8, options: FormatterOptions) ![]const u8 {
        // For now, return source unchanged since external zig fmt integration is complex
        _ = options; // Zig fmt doesn't use our custom options
        return allocator.dupe(u8, source);
    }
};

/// Get Zig-specific extraction patterns
fn getZigPatterns() LanguagePatterns {
    const function_patterns = [_][]const u8{ "pub fn ", "fn ", "export fn ", "extern fn " };
    const type_patterns = [_][]const u8{ "const ", "var ", "struct {", "enum {", "union {", "error{" };
    const import_patterns = [_][]const u8{ "@import(", "@cImport(" };
    const doc_patterns = [_][]const u8{ "///" };
    const test_patterns = [_][]const u8{ "test " };
    const structure_patterns = [_][]const u8{ "pub const ", "pub var ", "pub fn ", "struct", "enum", "union" };
    
    return LanguagePatterns{
        .functions = &function_patterns,
        .types = &type_patterns,
        .imports = &import_patterns,
        .docs = &doc_patterns,
        .tests = &test_patterns,
        .structure = &structure_patterns,
        .custom_extract = zigCustomExtract,
    };
}

/// Custom extraction logic for Zig-specific patterns
fn zigCustomExtract(line: []const u8, flags: ExtractionFlags) bool {
    const trimmed = std.mem.trim(u8, line, " \t");
    
    // Extract error definitions
    if (flags.errors) {
        if (std.mem.startsWith(u8, trimmed, "error{") or
            std.mem.indexOf(u8, trimmed, "error.") != null or
            std.mem.indexOf(u8, trimmed, "try ") != null or
            std.mem.indexOf(u8, trimmed, "catch") != null or
            std.mem.indexOf(u8, trimmed, "orelse") != null) 
        {
            return true;
        }
    }
    
    // Extract comptime blocks for structure
    if (flags.structure) {
        if (std.mem.startsWith(u8, trimmed, "comptime") or
            std.mem.indexOf(u8, trimmed, "@") != null)
        {
            return true;
        }
    }
    
    return false;
}

/// Check if node represents a function
fn isFunctionNode(kind: []const u8) bool {
    return std.mem.eql(u8, kind, "function") or
           std.mem.eql(u8, kind, "fn_decl") or
           std.mem.eql(u8, kind, "function_declaration");
}

/// Check if node represents a type definition
fn isTypeNode(kind: []const u8) bool {
    return std.mem.eql(u8, kind, "struct_decl") or
           std.mem.eql(u8, kind, "enum_decl") or
           std.mem.eql(u8, kind, "union_decl") or
           std.mem.eql(u8, kind, "error_set_decl") or
           std.mem.eql(u8, kind, "var_decl") or
           std.mem.eql(u8, kind, "const_decl");
}

/// Check if node represents an import
fn isImportNode(kind: []const u8) bool {
    return std.mem.eql(u8, kind, "builtin_call") or
           std.mem.eql(u8, kind, "@import") or
           std.mem.eql(u8, kind, "@cImport");
}

/// Check if node represents documentation
fn isDocNode(kind: []const u8) bool {
    return std.mem.eql(u8, kind, "doc_comment") or
           std.mem.eql(u8, kind, "comment");
}

/// Check if node represents a test
fn isTestNode(kind: []const u8) bool {
    return std.mem.eql(u8, kind, "test_decl") or
           std.mem.eql(u8, kind, "test");
}

/// Check if node represents error handling
fn isErrorNode(kind: []const u8) bool {
    return std.mem.eql(u8, kind, "error_set_decl") or
           std.mem.eql(u8, kind, "try_expr") or
           std.mem.eql(u8, kind, "catch_expr") or
           std.mem.eql(u8, kind, "orelse_expr");
}

// External tree-sitter function (to be linked)
extern fn tree_sitter_zig() *ts.Language;

// Tests
test "Zig extraction with function flags" {
    const allocator = std.testing.allocator;
    const source = 
        \\pub fn main() void {
        \\    std.debug.print("Hello, World!\n", .{});
        \\}
        \\
        \\fn privateFunction() u32 {
        \\    return 42;
        \\}
        \\
        \\test "example test" {
        \\    try std.testing.expect(true);
        \\}
    ;
    
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();
    
    const flags = ExtractionFlags{ .signatures = true };
    try ZigLanguage.extract(allocator, source, flags, &result);
    
    const output = result.items;
    try std.testing.expect(std.mem.indexOf(u8, output, "pub fn main()") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "fn privateFunction()") != null);
}

test "Zig extraction with type flags" {
    const allocator = std.testing.allocator;
    const source = 
        \\const MyStruct = struct {
        \\    field: u32,
        \\};
        \\
        \\const MyEnum = enum {
        \\    option1,
        \\    option2,
        \\};
        \\
        \\var global_var: u32 = 0;
    ;
    
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();
    
    const flags = ExtractionFlags{ .types = true };
    try ZigLanguage.extract(allocator, source, flags, &result);
    
    const output = result.items;
    try std.testing.expect(std.mem.indexOf(u8, output, "const MyStruct") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "const MyEnum") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "var global_var") != null);
}

test "Zig extraction with test flags" {
    const allocator = std.testing.allocator;
    const source = 
        \\pub fn regularFunction() void {}
        \\
        \\test "first test" {
        \\    try std.testing.expect(true);
        \\}
        \\
        \\test "second test" {
        \\    try std.testing.expect(false);
        \\}
    ;
    
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();
    
    const flags = ExtractionFlags{ .tests = true };
    try ZigLanguage.extract(allocator, source, flags, &result);
    
    const output = result.items;
    try std.testing.expect(std.mem.indexOf(u8, output, "test \"first test\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "test \"second test\"") != null);
    // Should not include regular function
    try std.testing.expect(std.mem.indexOf(u8, output, "pub fn regularFunction") == null);
}