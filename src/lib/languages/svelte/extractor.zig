const std = @import("std");
const ExtractionFlags = @import("../../language/flags.zig").ExtractionFlags;
const extractWithPatterns = @import("../../extractor_base.zig").extractWithPatterns;
const LanguagePatterns = @import("../../extractor_base.zig").LanguagePatterns;

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
                try result.appendSlice("<!-- Script Section -->\n");
                try result.appendSlice(script_result.items);
                try result.appendSlice("\n");
            }
        }
    }
    
    // Extract from style section (CSS)
    if (sections.style) |style| {
        if (flags.types or flags.structure) {
            try result.appendSlice("<!-- Style Section -->\n");
            try result.appendSlice(style);
            try result.appendSlice("\n");
        }
    }
    
    // Extract from template section (HTML-like)
    if (sections.template) |template| {
        if (flags.structure or flags.docs) {
            try result.appendSlice("<!-- Template Section -->\n");
            try result.appendSlice(template);
            try result.appendSlice("\n");
        }
    }
}

/// Svelte file sections
const SvelteSections = struct {
    script: ?[]const u8 = null,
    script_lang: ?[]const u8 = null,
    style: ?[]const u8 = null,
    style_lang: ?[]const u8 = null,
    template: ?[]const u8 = null,
};

/// Parse Svelte file into sections (simplified version)
fn parseSvelteSections(allocator: std.mem.Allocator, source: []const u8) !SvelteSections {
    var sections = SvelteSections{};
    
    // Find script section
    if (std.mem.indexOf(u8, source, "<script")) |script_start| {
        const script_tag_end = std.mem.indexOf(u8, source[script_start..], ">") orelse return sections;
        const script_content_start = script_start + script_tag_end + 1;
        
        if (std.mem.indexOf(u8, source[script_content_start..], "</script>")) |script_content_length| {
            const script_content = source[script_content_start..script_content_start + script_content_length];
            sections.script = try allocator.dupe(u8, script_content);
        }
    }
    
    // Find style section
    if (std.mem.indexOf(u8, source, "<style")) |style_start| {
        const style_tag_end = std.mem.indexOf(u8, source[style_start..], ">") orelse return sections;
        const style_content_start = style_start + style_tag_end + 1;
        
        if (std.mem.indexOf(u8, source[style_content_start..], "</style>")) |style_content_length| {
            const style_content = source[style_content_start..style_content_start + style_content_length];
            sections.style = try allocator.dupe(u8, style_content);
        }
    }
    
    // Template is everything else (simplified)
    sections.template = try allocator.dupe(u8, source);
    
    return sections;
}

/// Get JavaScript/TypeScript patterns for script sections
fn getJavaScriptPatterns() LanguagePatterns {
    const function_patterns = [_][]const u8{ "function ", "const ", "let ", "var ", "export " };
    const type_patterns = [_][]const u8{ "interface ", "type ", "class " };
    const import_patterns = [_][]const u8{ "import ", "export " };
    const doc_patterns = [_][]const u8{ "/**", "//" };
    const test_patterns = [_][]const u8{ "test(", "it(", "describe(" };
    
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