const std = @import("std");
const ExtractionFlags = @import("../../language/flags.zig").ExtractionFlags;
const extractWithPatterns = @import("../../extractor_base.zig").extractWithPatterns;
const LanguagePatterns = @import("../../extractor_base.zig").LanguagePatterns;

/// Section tracking for Svelte components
const SvelteSection = enum {
    none,
    script,
    style,
    template,
};

/// Svelte extraction context
const SvelteContext = struct {
    current_section: SvelteSection = .none,
    script_depth: u32 = 0,
    style_depth: u32 = 0,
    in_script_block: bool = false,
    in_style_block: bool = false,
};

/// Extract Svelte code using section-aware patterns
pub fn extract(allocator: std.mem.Allocator, source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) !void {
    // If full flag is set, return full source
    if (flags.full) {
        try result.appendSlice(source);
        return;
    }
    
    // If no specific flags are set, return full source (backward compatibility)
    if (flags.isDefault()) {
        try result.appendSlice(source);
        return;
    }
    
    // Use section-aware extraction for better results
    try extractWithSectionTracking(allocator, source, flags, result);
}

/// Section-aware extraction with proper Svelte 5 support
fn extractWithSectionTracking(_: std.mem.Allocator, source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) !void {
    var context = SvelteContext{};
    var lines = std.mem.splitScalar(u8, source, '\n');
    var need_newline = false;
    
    while (lines.next()) |line| {
        var should_include = false;
        
        // Check for section boundaries first (before updating context)
        if (isSectionBoundary(line)) {
            if ((std.mem.indexOf(u8, line, "<script") != null and (flags.signatures or flags.imports or flags.types)) or
                (std.mem.indexOf(u8, line, "<style") != null and (flags.types or flags.structure)) or
                (std.mem.indexOf(u8, line, "</script>") != null and (flags.signatures or flags.imports or flags.types)) or
                (std.mem.indexOf(u8, line, "</style>") != null and (flags.types or flags.structure)) or
                flags.structure)
            {
                should_include = true;
            }
        }
        
        // Check content within sections (use current context before updating)
        if (!should_include) {
            switch (context.current_section) {
                .script => {
                    if (flags.signatures or flags.imports or flags.types) {
                        should_include = shouldIncludeScriptLine(line, flags);
                    }
                },
                .style => {
                    if (flags.types or flags.structure) {
                        should_include = shouldIncludeStyleLine(line, flags);
                    }
                },
                .template => {
                    if (flags.structure) {
                        should_include = shouldIncludeTemplateLine(line, flags);
                    }
                },
                .none => {
                    // Already handled section boundaries above
                },
            }
        }
        
        // Update section tracking AFTER checking inclusion
        updateSectionContext(&context, line);
        
        if (should_include) {
            if (need_newline) {
                try result.append('\n');
            }
            try result.appendSlice(line);
            need_newline = true;
        }
    }
}

/// Update section context based on current line
fn updateSectionContext(context: *SvelteContext, line: []const u8) void {
    // Check for script section boundaries
    if (std.mem.indexOf(u8, line, "<script") != null) {
        context.current_section = .script;
        context.in_script_block = true;
        context.script_depth += 1;
    } else if (std.mem.indexOf(u8, line, "</script>") != null) {
        context.script_depth -= 1;
        if (context.script_depth == 0) {
            context.current_section = .template;
            context.in_script_block = false;
        }
    }
    // Check for style section boundaries  
    else if (std.mem.indexOf(u8, line, "<style") != null) {
        context.current_section = .style;
        context.in_style_block = true;
        context.style_depth += 1;
    } else if (std.mem.indexOf(u8, line, "</style>") != null) {
        context.style_depth -= 1;
        if (context.style_depth == 0) {
            context.current_section = .template;
            context.in_style_block = false;
        }
    }
    // If we're not in a script or style block, we're in template
    else if (!context.in_script_block and !context.in_style_block) {
        context.current_section = .template;
    }
}

/// Check if a script line should be included
fn shouldIncludeScriptLine(line: []const u8, flags: ExtractionFlags) bool {
    const trimmed = std.mem.trim(u8, line, " \t");
    
    // Don't include section boundaries here - handled separately
    if (isSectionBoundary(line)) return false;
    
    if (flags.signatures) {
        // Svelte 5 runes
        if (std.mem.indexOf(u8, trimmed, "$state") != null or
            std.mem.indexOf(u8, trimmed, "$derived") != null or
            std.mem.indexOf(u8, trimmed, "$effect") != null or
            std.mem.indexOf(u8, trimmed, "$props") != null or
            std.mem.indexOf(u8, trimmed, "$bindable") != null)
        {
            return true;
        }
        
        // Function declarations
        if (std.mem.startsWith(u8, trimmed, "function ") or
            std.mem.startsWith(u8, trimmed, "export function ") or
            std.mem.startsWith(u8, trimmed, "const ") or
            std.mem.startsWith(u8, trimmed, "let ") or
            std.mem.startsWith(u8, trimmed, "export let ") or
            std.mem.startsWith(u8, trimmed, "export const "))
        {
            return true;
        }
        
        // Svelte 4 reactive statements
        if (std.mem.startsWith(u8, trimmed, "$:")) {
            return true;
        }
    }
    
    if (flags.types) {
        // Variable declarations that define types/state
        if (std.mem.startsWith(u8, trimmed, "let ") or
            std.mem.startsWith(u8, trimmed, "const ") or
            std.mem.startsWith(u8, trimmed, "export let ") or
            std.mem.startsWith(u8, trimmed, "export const "))
        {
            return true;
        }
        
        // Svelte 5 state declarations
        if (std.mem.indexOf(u8, trimmed, "$state") != null or
            std.mem.indexOf(u8, trimmed, "$derived") != null)
        {
            return true;
        }
    }
    
    if (flags.imports) {
        if (std.mem.startsWith(u8, trimmed, "import ") or
            std.mem.startsWith(u8, trimmed, "export "))
        {
            return true;
        }
    }
    
    return false;
}

/// Check if a style line should be included  
fn shouldIncludeStyleLine(line: []const u8, flags: ExtractionFlags) bool {
    const trimmed = std.mem.trim(u8, line, " \t");
    
    // Don't include section boundaries here - handled separately
    if (isSectionBoundary(line)) return false;
    
    if (flags.types) {
        // CSS selectors and rules
        if (trimmed.len > 0 and (
            std.mem.indexOf(u8, trimmed, "{") != null or
            std.mem.indexOf(u8, trimmed, "}") != null or
            std.mem.indexOf(u8, trimmed, ":global") != null or
            std.mem.indexOf(u8, trimmed, "@media") != null or
            std.mem.indexOf(u8, trimmed, "@import") != null or
            std.mem.indexOf(u8, trimmed, ".") != null or
            std.mem.indexOf(u8, trimmed, "#") != null))
        {
            return true;
        }
    }
    
    return flags.structure; // Include all for structure
}

/// Check if a template line should be included
fn shouldIncludeTemplateLine(line: []const u8, flags: ExtractionFlags) bool {
    const trimmed = std.mem.trim(u8, line, " \t");
    
    if (flags.structure) {
        // HTML elements and Svelte control flow
        if (trimmed.len > 0 and (
            std.mem.indexOf(u8, trimmed, "<") != null or
            std.mem.indexOf(u8, trimmed, "{#") != null or  // Control flow blocks
            std.mem.indexOf(u8, trimmed, "{:") != null or  // Else blocks  
            std.mem.indexOf(u8, trimmed, "{/") != null or  // End blocks
            std.mem.indexOf(u8, trimmed, "{@") != null or  // Render statements
            std.mem.indexOf(u8, trimmed, "bind:") != null or
            std.mem.indexOf(u8, trimmed, "on:") != null or
            std.mem.indexOf(u8, trimmed, "onclick") != null))
        {
            return true;
        }
    }
    
    return false;
}

/// Check if line is a section boundary
fn isSectionBoundary(line: []const u8) bool {
    return std.mem.indexOf(u8, line, "<script") != null or
           std.mem.indexOf(u8, line, "</script>") != null or
           std.mem.indexOf(u8, line, "<style") != null or
           std.mem.indexOf(u8, line, "</style>") != null;
}

/// Get Svelte-specific extraction patterns (legacy support)
fn getSveltePatterns() LanguagePatterns {
    // Enhanced patterns for comprehensive Svelte 5 support
    const function_patterns = [_][]const u8{ 
        "function ", "export function ", "const ", "let ", "export let ", "export const ",
        "$state", "$derived", "$effect", "$props", "$bindable", "$:"
    };
    const type_patterns = [_][]const u8{ 
        "<style", "</style>", ":global", "@media", "@import", ".", "#"
    };
    const import_patterns = [_][]const u8{ "import ", "export " };
    const doc_patterns = [_][]const u8{ "<!--", "//" };
    const test_patterns: []const []const u8 = &[_][]const u8{}; // No tests in Svelte
    const structure_patterns = [_][]const u8{ 
        "<script", "</script>", "<style", "</style>", "<div", "<p", "<section", "<main",
        "<header", "<footer", "<nav", "<article", "<aside", "<h1", "<h2", "<h3", "<h4", "<h5", "<h6",
        "<button", "<input", "<form", "<ul", "<ol", "<li", "<table", "<tr", "<td", "<th",
        "{#if", "{:else", "{/if", "{#each", "{/each", "{#await", "{/await", 
        "{#snippet", "{@render", "<slot", "bind:", "on:", "onclick"
    };
    
    return LanguagePatterns{
        .functions = function_patterns[0..],
        .types = type_patterns[0..],
        .imports = import_patterns[0..],
        .docs = doc_patterns[0..],
        .tests = test_patterns,
        .structure = structure_patterns[0..],
        .custom_extract = svelteCustomExtract,
    };
}

/// Legacy custom extraction logic for fallback
fn svelteCustomExtract(line: []const u8, flags: ExtractionFlags) bool {
    const trimmed = std.mem.trim(u8, line, " \t");
    
    // Svelte 5 runes
    if (flags.signatures) {
        if (std.mem.indexOf(u8, trimmed, "$state") != null or
            std.mem.indexOf(u8, trimmed, "$derived") != null or
            std.mem.indexOf(u8, trimmed, "$effect") != null or
            std.mem.indexOf(u8, trimmed, "$props") != null or
            std.mem.indexOf(u8, trimmed, "$bindable") != null)
        {
            return true;
        }
    }
    
    // Control flow blocks
    if (flags.structure) {
        if (std.mem.indexOf(u8, trimmed, "{#") != null or
            std.mem.indexOf(u8, trimmed, "{:") != null or
            std.mem.indexOf(u8, trimmed, "{/") != null or
            std.mem.indexOf(u8, trimmed, "{@") != null)
        {
            return true;
        }
    }
    
    return false;
}