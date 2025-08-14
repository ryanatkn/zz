const std = @import("std");
const ts = @import("tree-sitter");
const ExtractionFlags = @import("../language/flags.zig").ExtractionFlags;
const Node = @import("../tree_sitter/node.zig").Node;
const ExtractionContext = @import("../tree_sitter/visitor.zig").ExtractionContext;
const FormatterOptions = @import("../parsing/formatter.zig").FormatterOptions;
const LineBuilder = @import("../parsing/formatter.zig").LineBuilder;
const extractWithPatterns = @import("../extractor_base.zig").extractWithPatterns;
const LanguagePatterns = @import("../extractor_base.zig").LanguagePatterns;

/// Svelte language implementation combining extraction, parsing, and formatting
/// Svelte files have three sections: script, style, and template
pub const SvelteLanguage = struct {
    pub const language_name = "svelte";
    
    /// Get tree-sitter grammar for Svelte
    pub fn grammar() *ts.Language {
        return tree_sitter_svelte();
    }
    
    /// Extract Svelte code using patterns or AST
    pub fn extract(allocator: std.mem.Allocator, source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) !void {
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
        
        // Svelte has multiple sections, handle them separately
        try extractSvelteSections(allocator, source, flags, result);
    }
    
    /// AST-based extraction visitor
    pub fn visitor(context: *ExtractionContext, node: *const Node) !void {
        // TODO: Implement proper tree-sitter extraction
        // For now, trigger fallback to pattern-based extraction
        _ = context;
        _ = node;
        return error.UnsupportedLanguage;
    }
    
    /// Format Svelte source code
    pub fn format(allocator: std.mem.Allocator, source: []const u8, options: FormatterOptions) ![]const u8 {
        var builder = LineBuilder.init(allocator, options);
        defer builder.deinit();
        
        // Parse Svelte sections and format each appropriately
        const sections = try parseSvelteSections(allocator, source);
        defer {
            if (sections.script) |script| allocator.free(script);
            if (sections.style) |style| allocator.free(style);
            if (sections.template) |template| allocator.free(template);
        }
        
        // Format script section
        if (sections.script) |script| {
            try builder.append("<script");
            if (sections.script_lang) |lang| {
                try builder.append(" lang=\"");
                try builder.append(lang);
                try builder.append("\"");
            }
            try builder.append(">");
            try builder.newline();
            
            // Format JavaScript/TypeScript content
            const formatted_script = try formatJavaScript(allocator, script, options);
            defer allocator.free(formatted_script);
            
            var script_lines = std.mem.splitScalar(u8, formatted_script, '\n');
            while (script_lines.next()) |line| {
                if (std.mem.trim(u8, line, " \t").len > 0) {
                    try builder.append(line);
                }
                try builder.newline();
            }
            
            try builder.append("</script>");
            try builder.newline();
            try builder.newline();
        }
        
        // Format style section
        if (sections.style) |style| {
            try builder.append("<style");
            if (sections.style_lang) |lang| {
                try builder.append(" lang=\"");
                try builder.append(lang);
                try builder.append("\"");
            }
            try builder.append(">");
            try builder.newline();
            
            // Format CSS content with indentation
            var style_lines = std.mem.splitScalar(u8, style, '\n');
            while (style_lines.next()) |line| {
                const trimmed = std.mem.trim(u8, line, " \t");
                if (trimmed.len > 0) {
                    try builder.append(line);
                }
                try builder.newline();
            }
            
            try builder.append("</style>");
            try builder.newline();
            try builder.newline();
        }
        
        // Format template section (HTML-like)
        if (sections.template) |template| {
            var template_lines = std.mem.splitScalar(u8, template, '\n');
            while (template_lines.next()) |line| {
                const trimmed = std.mem.trim(u8, line, " \t\r\n");
                if (trimmed.len == 0) {
                    if (options.preserve_newlines) {
                        try builder.newline();
                    }
                    continue;
                }
                
                // Simple HTML-like formatting
                if (std.mem.startsWith(u8, trimmed, "<") and !std.mem.startsWith(u8, trimmed, "</")) {
                    try builder.appendIndent();
                    try builder.append(trimmed);
                    try builder.newline();
                    if (!std.mem.endsWith(u8, trimmed, "/>") and !isSvelteVoidElement(trimmed)) {
                        builder.indent();
                    }
                } else if (std.mem.startsWith(u8, trimmed, "</")) {
                    builder.dedent();
                    try builder.appendIndent();
                    try builder.append(trimmed);
                    try builder.newline();
                } else {
                    try builder.appendIndent();
                    try builder.append(trimmed);
                    try builder.newline();
                }
            }
        }
        
        return builder.toOwnedSlice();
    }
};

/// Svelte file sections
const SvelteSections = struct {
    script: ?[]const u8 = null,
    script_lang: ?[]const u8 = null,
    style: ?[]const u8 = null,
    style_lang: ?[]const u8 = null,
    template: ?[]const u8 = null,
};

/// Extract code from different Svelte sections based on flags
fn extractSvelteSections(allocator: std.mem.Allocator, source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) !void {
    const sections = try parseSvelteSections(allocator, source);
    defer {
        if (sections.script) |script| allocator.free(script);
        if (sections.style) |style| allocator.free(style);
        if (sections.template) |template| allocator.free(template);
    }
    
    // Extract from script section (JavaScript/TypeScript)
    if (sections.script) |script| {
        if (flags.signatures or flags.types or flags.imports or flags.tests) {
            // Use JavaScript/TypeScript patterns for script section
            const js_patterns = getJavaScriptPatterns();
            var script_result = std.ArrayList(u8).init(allocator);
            defer script_result.deinit();
            
            try extractWithPatterns(script, flags, &script_result, js_patterns);
            
            if (script_result.items.len > 0) {
                // Include full script tags for test compatibility
                try result.appendSlice("<script");
                if (sections.script_lang) |lang| {
                    try result.appendSlice(" lang=\"");
                    try result.appendSlice(lang);
                    try result.appendSlice("\"");
                }
                try result.appendSlice(">\n");
                try result.appendSlice(script_result.items);
                try result.appendSlice("</script>\n\n");
            }
        } else if (flags.structure) {
            // For structure flag, include the full script section
            try result.appendSlice("<script");
            if (sections.script_lang) |lang| {
                try result.appendSlice(" lang=\"");
                try result.appendSlice(lang);
                try result.appendSlice("\"");
            }
            try result.appendSlice(">\n");
            try result.appendSlice(script);
            try result.appendSlice("</script>\n\n");
        }
    }
    
    // Extract from style section (CSS)
    if (sections.style) |style| {
        if (flags.types or flags.structure) {
            // Include full style tags
            try result.appendSlice("<style");
            if (sections.style_lang) |lang| {
                try result.appendSlice(" lang=\"");
                try result.appendSlice(lang);
                try result.appendSlice("\"");
            }
            try result.appendSlice(">");
            if (style.len > 0 and style[0] != '\n') {
                try result.appendSlice("\n");
            }
            try result.appendSlice(style);
            if (style.len > 0 and style[style.len - 1] != '\n') {
                try result.appendSlice("\n");
            }
            try result.appendSlice("</style>\n\n");
        }
    }
    
    // Extract from template section (HTML-like)
    if (sections.template) |template| {
        if (flags.structure) {
            try result.appendSlice(template);
        }
    }
}

/// Parse Svelte file into sections
fn parseSvelteSections(allocator: std.mem.Allocator, source: []const u8) !SvelteSections {
    var sections = SvelteSections{};
    
    // Find script section
    if (std.mem.indexOf(u8, source, "<script")) |script_start| {
        if (std.mem.indexOf(u8, source[script_start..], ">")) |tag_end| {
            const script_tag_start = script_start + tag_end + 1;
            if (std.mem.indexOf(u8, source[script_tag_start..], "</script>")) |script_end| {
                sections.script = try allocator.dupe(u8, source[script_tag_start .. script_tag_start + script_end]);
                
                // Extract language if specified
                const tag = source[script_start .. script_start + tag_end + 1];
                if (std.mem.indexOf(u8, tag, "lang=\"")) |lang_start| {
                    const lang_content_start = lang_start + 6;
                    if (std.mem.indexOf(u8, tag[lang_content_start..], "\"")) |lang_end| {
                        sections.script_lang = tag[lang_content_start .. lang_content_start + lang_end];
                    }
                }
            }
        }
    }
    
    // Find style section
    if (std.mem.indexOf(u8, source, "<style")) |style_start| {
        if (std.mem.indexOf(u8, source[style_start..], ">")) |tag_end| {
            const style_tag_start = style_start + tag_end + 1;
            if (std.mem.indexOf(u8, source[style_tag_start..], "</style>")) |style_end| {
                sections.style = try allocator.dupe(u8, source[style_tag_start .. style_tag_start + style_end]);
                
                // Extract language if specified
                const tag = source[style_start .. style_start + tag_end + 1];
                if (std.mem.indexOf(u8, tag, "lang=\"")) |lang_start| {
                    const lang_content_start = lang_start + 6;
                    if (std.mem.indexOf(u8, tag[lang_content_start..], "\"")) |lang_end| {
                        sections.style_lang = tag[lang_content_start .. lang_content_start + lang_end];
                    }
                }
            }
        }
    }
    
    // Template is everything outside script and style
    var template_parts = std.ArrayList(u8).init(allocator);
    defer template_parts.deinit();
    
    var current_pos: usize = 0;
    
    // Add content before script
    if (std.mem.indexOf(u8, source, "<script")) |script_start| {
        try template_parts.appendSlice(source[current_pos..script_start]);
        // Skip script section
        if (std.mem.indexOf(u8, source[script_start..], "</script>")) |script_end| {
            current_pos = script_start + script_end + "</script>".len;
        }
    }
    
    // Add content before style (if after script)
    if (std.mem.indexOf(u8, source[current_pos..], "<style")) |style_start| {
        const abs_style_start = current_pos + style_start;
        try template_parts.appendSlice(source[current_pos..abs_style_start]);
        // Skip style section
        if (std.mem.indexOf(u8, source[abs_style_start..], "</style>")) |style_end| {
            current_pos = abs_style_start + style_end + "</style>".len;
        }
    }
    
    // Add remaining content
    if (current_pos < source.len) {
        try template_parts.appendSlice(source[current_pos..]);
    }
    
    if (template_parts.items.len > 0) {
        sections.template = try template_parts.toOwnedSlice();
    }
    
    return sections;
}

/// Get JavaScript/TypeScript patterns for script sections
fn getJavaScriptPatterns() LanguagePatterns {
    const function_patterns = [_][]const u8{ "function ", "const ", "let ", "var ", "export ", "async ", "=>" };
    const type_patterns = [_][]const u8{ "interface ", "type ", "class ", "enum ", "let ", "const ", "var " };
    const import_patterns = [_][]const u8{ "import ", "from ", "require(" };
    const doc_patterns = [_][]const u8{ "/**", "///" };
    const test_patterns = [_][]const u8{ "test(", "describe(", "it(" };
    
    return LanguagePatterns{
        .functions = &function_patterns,
        .types = &type_patterns,
        .imports = &import_patterns,
        .docs = &doc_patterns,
        .tests = &test_patterns,
        .structure = &function_patterns,
        .custom_extract = null,
    };
}

/// Simple JavaScript formatter (basic indentation)
fn formatJavaScript(allocator: std.mem.Allocator, source: []const u8, options: FormatterOptions) ![]const u8 {
    var builder = LineBuilder.init(allocator, options);
    defer builder.deinit();
    
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r\n");
        
        if (trimmed.len == 0) {
            if (options.preserve_newlines) {
                try builder.newline();
            }
            continue;
        }
        
        // Simple indentation logic
        if (std.mem.endsWith(u8, trimmed, "{")) {
            try builder.appendIndent();
            try builder.append(trimmed);
            try builder.newline();
            builder.indent();
        } else if (std.mem.startsWith(u8, trimmed, "}")) {
            builder.dedent();
            try builder.appendIndent();
            try builder.append(trimmed);
            try builder.newline();
        } else {
            try builder.appendIndent();
            try builder.append(trimmed);
            try builder.newline();
        }
    }
    
    return builder.toOwnedSlice();
}

/// Check if element is a Svelte void element
fn isSvelteVoidElement(tag: []const u8) bool {
    // Include HTML void elements plus Svelte-specific void elements
    const void_elements = [_][]const u8{
        "area", "base", "br", "col", "embed", "hr", "img", "input",
        "link", "meta", "param", "source", "track", "wbr",
        "svelte:self", "svelte:component", "svelte:window", "svelte:body", "svelte:head",
    };
    
    for (void_elements) |element| {
        if (std.mem.indexOf(u8, tag, element) != null) {
            return true;
        }
    }
    return false;
}

/// Node type checkers for AST extraction
fn isComponentNode(kind: []const u8) bool {
    return std.mem.eql(u8, kind, "component") or
           std.mem.eql(u8, kind, "svelte_element") or
           std.mem.eql(u8, kind, "svelte_component");
}

fn isTypeNode(kind: []const u8) bool {
    return std.mem.eql(u8, kind, "interface_declaration") or
           std.mem.eql(u8, kind, "type_alias_declaration") or
           std.mem.eql(u8, kind, "class_declaration") or
           std.mem.eql(u8, kind, "enum_declaration");
}

fn isImportNode(kind: []const u8) bool {
    return std.mem.eql(u8, kind, "import_statement") or
           std.mem.eql(u8, kind, "import_declaration");
}

fn isDocNode(kind: []const u8) bool {
    return std.mem.eql(u8, kind, "comment") or
           std.mem.eql(u8, kind, "doc_comment");
}

fn isTestNode(kind: []const u8) bool {
    return std.mem.eql(u8, kind, "call_expression") and
           std.mem.indexOf(u8, kind, "test") != null;
}

// External tree-sitter function
extern fn tree_sitter_svelte() *ts.Language;

// Tests
test "Svelte section parsing" {
    const allocator = std.testing.allocator;
    const source = 
        \\<script lang="ts">
        \\  import { onMount } from 'svelte';
        \\  let count = 0;
        \\</script>
        \\
        \\<style>
        \\  .button { color: red; }
        \\</style>
        \\
        \\<button on:click={() => count++}>
        \\  Count: {count}
        \\</button>
    ;
    
    const sections = try parseSvelteSections(allocator, source);
    defer {
        if (sections.script) |script| allocator.free(script);
        if (sections.style) |style| allocator.free(style);
        if (sections.template) |template| allocator.free(template);
    }
    
    try std.testing.expect(sections.script != null);
    try std.testing.expect(sections.style != null);
    try std.testing.expect(sections.template != null);
    try std.testing.expect(std.mem.eql(u8, sections.script_lang.?, "ts"));
}

test "Svelte extraction with structure flags" {
    const allocator = std.testing.allocator;
    const source = 
        \\<script>
        \\  let name = 'World';
        \\  function greet() { return 'Hello'; }
        \\</script>
        \\
        \\<h1>{greet()} {name}!</h1>
    ;
    
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();
    
    const flags = ExtractionFlags{ .structure = true };
    try SvelteLanguage.extract(allocator, source, flags, &result);
    
    const output = result.items;
    try std.testing.expect(std.mem.indexOf(u8, output, "<script>") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "<h1>") != null);
}