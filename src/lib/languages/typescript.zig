const std = @import("std");
const ts = @import("tree-sitter");
const ExtractionFlags = @import("../language/flags.zig").ExtractionFlags;
const Node = @import("../tree_sitter/node.zig").Node;
const Visitor = @import("../tree_sitter/visitor.zig").Visitor;
const ExtractionContext = @import("../tree_sitter/visitor.zig").ExtractionContext;
const FormatterOptions = @import("../parsing/formatter.zig").FormatterOptions;
const LineBuilder = @import("../parsing/formatter.zig").LineBuilder;
const extractor_base = @import("../extractor_base.zig");
const line_processing = @import("../text/line_processing.zig");
const text_patterns = @import("../text/patterns.zig");
const builders = @import("../text/builders.zig");

/// TypeScript/JavaScript language implementation
pub const TypeScriptLanguage = struct {
    pub const language_name = "typescript";
    
    /// Get tree-sitter grammar for TypeScript
    pub fn grammar() *ts.Language {
        return tree_sitter_typescript();
    }
    
    /// Extract code using tree-sitter AST or patterns as fallback
    pub fn extract(_: std.mem.Allocator, source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) !void {
        // Use pattern-based extraction for now (tree-sitter integration in future)
        try extractWithPatterns(source, flags, result);
    }
    
    /// AST-based extraction visitor
    pub fn visitor(context: *ExtractionContext, node: *const Node) !void {
        const node_type = node.kind;
        
        // Functions and methods
        if (context.flags.signatures) {
            if (std.mem.eql(u8, node_type, "function_declaration") or
                std.mem.eql(u8, node_type, "method_definition") or
                std.mem.eql(u8, node_type, "arrow_function") or
                std.mem.eql(u8, node_type, "function_expression"))
            {
                try context.appendNode(node);
                return;
            }
        }
        
        // Types and interfaces
        if (context.flags.types) {
            if (std.mem.eql(u8, node_type, "interface_declaration") or
                std.mem.eql(u8, node_type, "type_alias_declaration") or
                std.mem.eql(u8, node_type, "class_declaration") or
                std.mem.eql(u8, node_type, "enum_declaration"))
            {
                try context.appendNode(node);
                return;
            }
        }
        
        // Imports and exports
        if (context.flags.imports) {
            if (std.mem.eql(u8, node_type, "import_statement") or
                std.mem.eql(u8, node_type, "import_declaration") or
                std.mem.eql(u8, node_type, "export_statement") or
                std.mem.startsWith(u8, node_type, "export_"))
            {
                try context.appendNode(node);
                return;
            }
        }
        
        // Comments and documentation
        if (context.flags.docs) {
            if (std.mem.eql(u8, node_type, "comment") or
                std.mem.startsWith(u8, node_type, "comment_"))
            {
                try context.appendNode(node);
                return;
            }
        }
        
        // Tests (common test frameworks)
        if (context.flags.tests) {
            if (std.mem.indexOf(u8, node.text, "test(") != null or
                std.mem.indexOf(u8, node.text, "it(") != null or
                std.mem.indexOf(u8, node.text, "describe(") != null or
                std.mem.indexOf(u8, node.text, "expect(") != null)
            {
                try context.appendNode(node);
                return;
            }
        }
        
        if (context.flags.full) {
            try context.appendNode(node);
        }
    }
    
    /// Format TypeScript source code (placeholder - uses prettier-style formatting)
    pub fn format(allocator: std.mem.Allocator, source: []const u8, options: FormatterOptions) ![]const u8 {
        // TODO: Implement proper TypeScript formatting with tree-sitter AST
        // For now, return formatted with basic indentation
        var builder = LineBuilder.init(allocator, options);
        defer builder.deinit();
        
        var lines = std.mem.splitScalar(u8, source, '\n');
        var brace_depth: u32 = 0;
        var in_multiline_comment = false;
        
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t");
            
            // Handle multiline comments
            if (std.mem.indexOf(u8, trimmed, "/*") != null) {
                in_multiline_comment = true;
            }
            if (std.mem.indexOf(u8, trimmed, "*/") != null) {
                in_multiline_comment = false;
                try builder.appendIndent();
                try builder.append(trimmed);
                try builder.newline();
                continue;
            }
            if (in_multiline_comment) {
                try builder.appendIndent();
                try builder.append(trimmed);
                try builder.newline();
                continue;
            }
            
            // Skip empty lines
            if (trimmed.len == 0) {
                try builder.newline();
                continue;
            }
            
            // Adjust indent before line for closing braces
            if (std.mem.startsWith(u8, trimmed, "}") and brace_depth > 0) {
                builder.dedent();
                brace_depth -= 1;
            }
            
            // Add indented line
            try builder.appendIndent();
            try builder.append(trimmed);
            try builder.newline();
            
            // Adjust indent after line for opening braces
            if (std.mem.indexOf(u8, trimmed, "{") != null) {
                builder.indent();
                brace_depth += 1;
            }
        }
        
        return builder.toOwnedSlice();
    }
    
    /// Pattern-based extraction patterns for fallback
    pub const patterns = extractor_base.LanguagePatterns{
        .functions = &text_patterns.Patterns.ts_functions,
        .types = &text_patterns.Patterns.ts_types,
        .imports = &text_patterns.Patterns.ts_imports,
        .docs = &.{
            "/**",
            "//",
        },
        .tests = &.{
            "test(",
            "it(",
            "describe(",
            "expect(",
        },
    };
};

/// Pattern-based extraction for TypeScript
fn extractWithPatterns(source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) !void {
    var lines = std.mem.splitScalar(u8, source, '\n');
    var block_tracker = line_processing.BlockTracker.init();

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");

        // Track block depth for multi-line interfaces/types
        if (block_tracker.isInBlock()) {
            try builders.appendLine(result, line);
            block_tracker.processLine(line);
            continue;
        }

        var should_include = false;
        var starts_block = false;

        // Functions
        if (flags.signatures) {
            if (text_patterns.startsWithAny(trimmed, &text_patterns.Patterns.ts_functions) or
                std.mem.indexOf(u8, trimmed, "=>") != null)
            {
                should_include = true;
            }
        }

        // Types and interfaces
        if (flags.types) {
            if (text_patterns.startsWithAny(trimmed, &text_patterns.Patterns.ts_types)) {
                should_include = true;
                if (std.mem.indexOf(u8, line, "{") != null) {
                    starts_block = true;
                }
            }
        }

        // Imports
        if (flags.imports) {
            if (text_patterns.startsWithAny(trimmed, &text_patterns.Patterns.ts_imports)) {
                should_include = true;
            }
        }

        // Comments/docs
        if (flags.docs) {
            if (std.mem.startsWith(u8, trimmed, "//") or
                std.mem.startsWith(u8, trimmed, "/**") or
                std.mem.startsWith(u8, trimmed, "/*"))
            {
                should_include = true;
            }
        }

        // Tests
        if (flags.tests) {
            if (std.mem.indexOf(u8, trimmed, "test(") != null or
                std.mem.indexOf(u8, trimmed, "it(") != null or
                std.mem.indexOf(u8, trimmed, "describe(") != null)
            {
                should_include = true;
                if (std.mem.indexOf(u8, line, "{") != null) {
                    starts_block = true;
                }
            }
        }

        // Full source
        if (flags.full) {
            should_include = true;
        }

        if (should_include) {
            try builders.appendLine(result, line);
            if (starts_block) {
                block_tracker.processLine(line);
            }
        }
    }
}

// External grammar function
extern fn tree_sitter_typescript() *ts.Language;

// Tests
test "TypeScriptLanguage pattern matching" {
    const allocator = std.testing.allocator;
    const source = 
        \\function test() {}
        \\interface User { name: string; }
        \\import { foo } from 'bar';
    ;
    
    // Test function extraction
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();
    
    const flags = ExtractionFlags{ .signatures = true };
    try TypeScriptLanguage.extract(allocator, source, flags, &result);
    try std.testing.expect(std.mem.indexOf(u8, result.items, "function test()") != null);
}

test "TypeScript interface extraction" {
    const allocator = std.testing.allocator;
    const source = "interface User { name: string; age: number; }";
    const flags = ExtractionFlags{ .types = true };
    
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();
    
    try TypeScriptLanguage.extract(allocator, source, flags, &result);
    try std.testing.expect(std.mem.indexOf(u8, result.items, "interface User") != null);
}