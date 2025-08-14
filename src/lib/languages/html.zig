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

/// HTML language implementation combining extraction, parsing, and formatting
pub const HtmlLanguage = struct {
    pub const language_name = "html";
    
    /// Get tree-sitter grammar for HTML
    pub fn grammar() *ts.Language {
        return tree_sitter_html();
    }
    
    /// Extract HTML code using patterns or AST
    pub fn extract(allocator: std.mem.Allocator, source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) !void {
        _ = allocator; // Not needed for pattern-based extraction
        
        // If full flag is set, return full source
        if (flags.full) {
            try result.appendSlice(source);
            return;
        }
        
        // If no specific flags are set, return full source (backward compatibility)
        if (!flags.signatures and !flags.types and !flags.imports and !flags.docs and !flags.tests and !flags.structure) {
            try result.appendSlice(source);
            return;
        }
        
        // Use pattern-based extraction for HTML
        const patterns = getHtmlPatterns();
        try extractWithPatterns(source, flags, result, patterns);
    }
    
    /// AST-based extraction visitor  
    pub fn visitor(context: *ExtractionContext, node: *const Node) !void {
        // Extract based on node type and flags
        if (context.flags.structure or context.flags.types) {
            // Extract HTML elements, attributes, and structure
            if (isStructuralNode(node.kind)) {
                try context.appendNode(node);
            }
        }
        
        if (context.flags.signatures) {
            // Extract element definitions and attributes
            if (isElementNode(node.kind)) {
                try context.appendNode(node);
            }
        }
        
        if (context.flags.imports) {
            // Extract script src, link href, etc.
            if (isImportNode(node.kind)) {
                try context.appendNode(node);
            }
        }
        
        if (context.flags.docs) {
            // Extract HTML comments
            if (isCommentNode(node.kind)) {
                try context.appendNode(node);
            }
        }
    }
    
    /// Format HTML source code
    pub fn format(allocator: std.mem.Allocator, source: []const u8, options: FormatterOptions) ![]const u8 {
        var builder = LineBuilder.init(allocator, options);
        defer builder.deinit();
        
        // Parse HTML and format with indentation
        var lines = std.mem.splitScalar(u8, source, '\n');
        var in_comment = false;
        
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r\n");
            
            if (trimmed.len == 0) {
                if (options.preserve_newlines) {
                    try builder.newline();
                }
                continue;
            }
            
            // Handle HTML comments
            if (std.mem.startsWith(u8, trimmed, "<!--")) {
                in_comment = true;
                try builder.appendIndent();
                try builder.append(trimmed);
                try builder.newline();
                if (std.mem.endsWith(u8, trimmed, "-->")) {
                    in_comment = false;
                }
                continue;
            }
            
            if (in_comment) {
                try builder.appendIndent();
                try builder.append(trimmed);
                try builder.newline();
                if (std.mem.endsWith(u8, trimmed, "-->")) {
                    in_comment = false;
                }
                continue;
            }
            
            // Handle DOCTYPE
            if (std.mem.startsWith(u8, trimmed, "<!DOCTYPE")) {
                try builder.append(trimmed);
                try builder.newline();
                continue;
            }
            
            // Handle opening tags
            if (std.mem.startsWith(u8, trimmed, "<") and !std.mem.startsWith(u8, trimmed, "</")) {
                try builder.appendIndent();
                try builder.append(trimmed);
                try builder.newline();
                
                // Check if it's a self-closing tag or void element
                if (!std.mem.endsWith(u8, trimmed, "/>") and !isVoidElement(trimmed)) {
                    builder.indent();
                }
                continue;
            }
            
            // Handle closing tags
            if (std.mem.startsWith(u8, trimmed, "</")) {
                builder.dedent();
                try builder.appendIndent();
                try builder.append(trimmed);
                try builder.newline();
                continue;
            }
            
            // Handle text content
            try builder.appendIndent();
            try builder.append(trimmed);
            try builder.newline();
        }
        
        return builder.toOwnedSlice();
    }
};

/// Get HTML-specific extraction patterns
fn getHtmlPatterns() LanguagePatterns {
    const element_patterns = [_][]const u8{ "<", "</" };
    const import_patterns = [_][]const u8{ "<script", "<link", "<style", "src=", "href=" };
    const doc_patterns = [_][]const u8{ "<!--" };
    const structure_patterns = [_][]const u8{ "<html", "<head", "<body", "<div", "<section", "<article", "<nav", "<main" };
    
    return LanguagePatterns{
        .functions = null, // HTML doesn't have functions
        .types = &element_patterns,
        .imports = &import_patterns,
        .docs = &doc_patterns,
        .tests = null, // HTML doesn't have tests
        .structure = &structure_patterns,
        .custom_extract = null,
    };
}

/// Check if node represents HTML structure
fn isStructuralNode(kind: []const u8) bool {
    return std.mem.eql(u8, kind, "element") or
           std.mem.eql(u8, kind, "start_tag") or
           std.mem.eql(u8, kind, "end_tag") or
           std.mem.eql(u8, kind, "attribute");
}

/// Check if node is an HTML element
fn isElementNode(kind: []const u8) bool {
    return std.mem.eql(u8, kind, "element") or
           std.mem.eql(u8, kind, "start_tag") or
           std.mem.eql(u8, kind, "self_closing_tag");
}

/// Check if node represents imports (scripts, links, etc.)
fn isImportNode(kind: []const u8) bool {
    return std.mem.eql(u8, kind, "script_element") or
           std.mem.eql(u8, kind, "style_element") or
           std.mem.eql(u8, kind, "link_element");
}

/// Check if node is a comment
fn isCommentNode(kind: []const u8) bool {
    return std.mem.eql(u8, kind, "comment");
}

/// Check if element is a void element (self-closing)
fn isVoidElement(tag: []const u8) bool {
    const void_elements = [_][]const u8{
        "area", "base", "br", "col", "embed", "hr", "img", "input",
        "link", "meta", "param", "source", "track", "wbr",
    };
    
    for (void_elements) |element| {
        if (std.mem.indexOf(u8, tag, element) != null) {
            return true;
        }
    }
    return false;
}

// External tree-sitter function (to be linked)
extern fn tree_sitter_html() *ts.Language;

// Tests
test "HTML extraction with structure flags" {
    const allocator = std.testing.allocator;
    const source = 
        \\<!DOCTYPE html>
        \\<html>
        \\<head>
        \\  <title>Test</title>
        \\</head>
        \\<body>
        \\  <div class="container">Content</div>
        \\</body>
        \\</html>
    ;
    
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();
    
    const flags = ExtractionFlags{ .structure = true };
    try HtmlLanguage.extract(allocator, source, flags, &result);
    
    const output = result.items;
    try std.testing.expect(std.mem.indexOf(u8, output, "<html>") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "<div") != null);
}

test "HTML formatting basic" {
    const allocator = std.testing.allocator;
    const source = "<div><p>Hello</p></div>";
    
    const options = FormatterOptions{};
    const formatted = try HtmlLanguage.format(allocator, source, options);
    defer allocator.free(formatted);
    
    // Should have proper indentation
    try std.testing.expect(std.mem.indexOf(u8, formatted, "<div>") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "    <p>") != null);
}