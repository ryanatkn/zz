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

/// CSS language implementation
pub const CssLanguage = struct {
    pub const language_name = "css";
    
    /// Get tree-sitter grammar for CSS
    pub fn grammar() *ts.Language {
        return tree_sitter_css();
    }
    
    /// Extract code using patterns (tree-sitter integration in future)
    pub fn extract(_: std.mem.Allocator, source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) !void {
        // For CSS, structure extraction includes entire rules
        if (flags.structure) {
            try line_processing.filterNonEmpty(source, result);
            return;
        }

        // For types flag, return full source (CSS doesn't have traditional types)
        if (flags.types) {
            try result.appendSlice(source);
            return;
        }

        // Extract selectors for signatures flag
        if (flags.signatures) {
            try extractSelectors(source, result);
            return;
        }

        // Extract imports
        if (flags.imports) {
            try extractImports(source, result);
            return;
        }

        // Full source
        if (flags.full) {
            try result.appendSlice(source);
            return;
        }

        // Default: return full source
        try result.appendSlice(source);
    }
    
    /// AST-based extraction visitor  
    pub fn visitor(context: *ExtractionContext, node: *const Node) !void {
        const node_type = node.kind;
        
        // Selectors (for signatures flag)
        if (context.flags.signatures) {
            if (std.mem.eql(u8, node_type, "rule_set") or
                std.mem.eql(u8, node_type, "selector") or
                std.mem.eql(u8, node_type, "media_query") or
                std.mem.startsWith(u8, node_type, "selector_"))
            {
                try context.appendNode(node);
                return;
            }
        }
        
        // At-rules and imports
        if (context.flags.imports) {
            if (std.mem.eql(u8, node_type, "import_statement") or
                std.mem.eql(u8, node_type, "at_rule") or
                std.mem.startsWith(u8, node_type, "import_"))
            {
                try context.appendNode(node);
                return;
            }
        }
        
        // Comments
        if (context.flags.docs) {
            if (std.mem.eql(u8, node_type, "comment"))
            {
                try context.appendNode(node);
                return;
            }
        }
        
        // Structure (rules without content)
        if (context.flags.structure) {
            if (std.mem.eql(u8, node_type, "rule_set") or
                std.mem.eql(u8, node_type, "media_statement") or
                std.mem.eql(u8, node_type, "keyframes_statement"))
            {
                // For structure, we might want just the selector part
                try context.appendNode(node);
                return;
            }
        }
        
        if (context.flags.full) {
            try context.appendNode(node);
        }
    }
    
    /// Format CSS source code
    pub fn format(allocator: std.mem.Allocator, source: []const u8, options: FormatterOptions) ![]const u8 {
        var builder = LineBuilder.init(allocator, options);
        defer builder.deinit();
        
        var lines = std.mem.splitScalar(u8, source, '\n');
        var in_rule = false;
        var brace_depth: u32 = 0;
        
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t");
            
            // Skip empty lines
            if (trimmed.len == 0) {
                try builder.newline();
                continue;
            }
            
            // Handle closing braces
            if (std.mem.startsWith(u8, trimmed, "}")) {
                if (brace_depth > 0) {
                    builder.dedent();
                    brace_depth -= 1;
                }
                in_rule = false;
                try builder.appendIndent();
                try builder.append("}");
                try builder.newline();
                if (brace_depth == 0) {
                    try builder.newline(); // Extra line after closing rule
                }
                continue;
            }
            
            // Handle selectors and at-rules
            if (std.mem.indexOf(u8, trimmed, "{") != null) {
                try builder.appendIndent();
                
                // Format selector part
                const brace_pos = std.mem.indexOf(u8, trimmed, "{").?;
                const selector_part = std.mem.trim(u8, trimmed[0..brace_pos], " \t");
                try builder.append(selector_part);
                try builder.append(" {");
                try builder.newline();
                
                builder.indent();
                brace_depth += 1;
                in_rule = true;
                continue;
            }
            
            // Handle properties inside rules
            if (in_rule and std.mem.indexOf(u8, trimmed, ":") != null) {
                try builder.appendIndent();
                
                // Format property: value;
                if (std.mem.indexOf(u8, trimmed, ":")) |colon_pos| {
                    const property = std.mem.trim(u8, trimmed[0..colon_pos], " \t");
                    const value_part = std.mem.trim(u8, trimmed[colon_pos + 1..], " \t");
                    
                    try builder.append(property);
                    try builder.append(": ");
                    try builder.append(value_part);
                    if (!std.mem.endsWith(u8, value_part, ";")) {
                        try builder.append(";");
                    }
                }
                try builder.newline();
                continue;
            }
            
            // Default: add line with proper indentation
            try builder.appendIndent();
            try builder.append(trimmed);
            try builder.newline();
        }
        
        return builder.toOwnedSlice();
    }
    
    /// Pattern-based extraction patterns
    pub const patterns = extractor_base.LanguagePatterns{
        .functions = null, // CSS doesn't have functions in the traditional sense
        .types = null,     // CSS doesn't have types
        .imports = &.{
            "@import",
            "@use",
        },
        .docs = &.{
            "/*",
            "//",
        },
        .structure = &.{
            "@media",
            "@keyframes",
            "@supports",
        },
    };
};

/// Extract CSS selectors
fn extractSelectors(source: []const u8, result: *std.ArrayList(u8)) !void {
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");

        // Skip empty lines and comments
        if (trimmed.len == 0 or std.mem.startsWith(u8, trimmed, "/*") or std.mem.startsWith(u8, trimmed, "//")) {
            continue;
        }

        // Check for @rules (media queries, keyframes, etc.)
        if (std.mem.startsWith(u8, trimmed, "@")) {
            if (line_processing.extractBeforeBrace(trimmed)) |selector| {
                try builders.appendLine(result, selector);
            } else {
                try builders.appendLine(result, trimmed);
            }
            continue;
        }

        // Check for CSS selectors (lines ending with { or containing selector patterns)
        if (std.mem.indexOf(u8, trimmed, "{") != null) {
            if (line_processing.extractBeforeBrace(trimmed)) |selector| {
                try builders.appendLine(result, selector);
            }
            continue;
        }

        // Check if line starts with selector patterns
        if (text_patterns.startsWithAny(trimmed, &text_patterns.Patterns.css_selectors)) {
            try builders.appendLine(result, trimmed);
        }
    }
}

/// Extract CSS imports and at-rules
fn extractImports(source: []const u8, result: *std.ArrayList(u8)) !void {
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");

        if (text_patterns.startsWithAny(trimmed, &text_patterns.Patterns.css_at_rules) or
            std.mem.startsWith(u8, trimmed, "@use") or
            std.mem.startsWith(u8, trimmed, "@forward")) {
            try builders.appendLine(result, line);
        }
    }
}

// External grammar function
extern fn tree_sitter_css() *ts.Language;

// Tests
test "CssLanguage selector extraction" {
    const allocator = std.testing.allocator;
    const source = 
        \\.class { color: red; }
        \\#id { background: blue; }
        \\@media screen { .mobile { font-size: 12px; } }
    ;
    
    const flags = ExtractionFlags{ .signatures = true };
    
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();
    
    try CssLanguage.extract(allocator, source, flags, &result);
    try std.testing.expect(std.mem.indexOf(u8, result.items, ".class") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.items, "#id") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.items, "@media") != null);
}

test "CSS import extraction" {
    const allocator = std.testing.allocator;
    const source = 
        \\@import "reset.css";
        \\@use "variables" as vars;
        \\.class { color: red; }
    ;
    
    const flags = ExtractionFlags{ .imports = true };
    
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();
    
    try CssLanguage.extract(allocator, source, flags, &result);
    try std.testing.expect(std.mem.indexOf(u8, result.items, "@import") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.items, "@use") != null);
    // Should not include regular CSS rules
    try std.testing.expect(std.mem.indexOf(u8, result.items, ".class") == null);
}