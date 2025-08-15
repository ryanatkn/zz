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

/// Multi-line expression state tracking
const ExpressionState = struct {
    in_multi_line_expression: bool = false,
    expression_type: ExpressionType = .none,
    brace_depth: u32 = 0,
    paren_depth: u32 = 0,
    expression_start_patterns: []const []const u8 = &[_][]const u8{
        "$derived.by(",
        "$effect(",
        "$effect.pre(",
        "$effect.root(",
        "() => {",
        "function(",
        "() =>",
    },
    
    const ExpressionType = enum {
        none,
        derived_by,
        effect,
        arrow_function,
        regular_function,
    };
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

/// Section-aware extraction with proper Svelte 5 support and multi-line expression handling
fn extractWithSectionTracking(_: std.mem.Allocator, source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) !void {
    var context = SvelteContext{};
    var lines = std.mem.splitScalar(u8, source, '\n');
    var need_newline = false;
    
    // Multi-line expression tracking
    var expression_state = ExpressionState{};

    while (lines.next()) |line| {
        var should_include = false;

        // Check for section boundaries first (before updating context)
        if (isSectionBoundary(line)) {
            if (flags.structure) {
                // Structure extraction includes all section boundaries
                should_include = true;
            }
            // For signatures/imports/types, we don't include section tags - just the content
        }

        // Check content within sections (use current context before updating)
        if (!should_include) {
            switch (context.current_section) {
                .script => {
                    if (flags.structure) {
                        // For structure extraction, include ALL script content except empty lines
                        should_include = !isSectionBoundary(line) and std.mem.trim(u8, line, " \t").len > 0;
                    } else if (flags.signatures or flags.imports or flags.types) {
                        should_include = shouldIncludeScriptLineWithExpressions(line, flags, &expression_state);
                    }
                },
                .style => {
                    if (flags.structure) {
                        // For structure extraction, include ALL style content except empty lines
                        should_include = !isSectionBoundary(line) and std.mem.trim(u8, line, " \t").len > 0;
                    } else if (flags.types) {
                        should_include = shouldIncludeStyleLine(line, flags);
                    }
                },
                .template => {
                    if (flags.structure) {
                        should_include = shouldIncludeTemplateLine(line, flags);
                    }
                },
                .none => {
                    // For structure extraction, skip empty lines between sections
                    if (flags.structure and std.mem.trim(u8, line, " \t").len == 0) {
                        should_include = false;
                    }
                },
            }
        }

        // Update section tracking AFTER checking inclusion
        updateSectionContext(&context, line);

        if (should_include) {
            if (need_newline) {
                try result.append('\n');
            }

            // For signatures, imports, and similar extractions, trim indentation and clean up syntax
            if ((flags.signatures or flags.imports) and !flags.structure) {
                var trimmed = std.mem.trim(u8, line, " \t");

                // For function signatures, remove opening brace if present (but not for multi-line expressions)
                if (flags.signatures and !expression_state.in_multi_line_expression and
                    ((std.mem.startsWith(u8, trimmed, "function ") or
                    std.mem.startsWith(u8, trimmed, "async function ") or
                    std.mem.startsWith(u8, trimmed, "export function ") or
                    std.mem.startsWith(u8, trimmed, "export async function ")) and
                    std.mem.endsWith(u8, trimmed, " {")))
                {
                    // Remove the " {" suffix to get just the signature
                    trimmed = trimmed[0 .. trimmed.len - 2];
                } else if (flags.signatures and !expression_state.in_multi_line_expression and
                    ((std.mem.startsWith(u8, trimmed, "function ") or
                    std.mem.startsWith(u8, trimmed, "async function ") or
                    std.mem.startsWith(u8, trimmed, "export function ") or
                    std.mem.startsWith(u8, trimmed, "export async function ")) and
                    std.mem.endsWith(u8, trimmed, "{")))
                {
                    // Remove the "{" suffix (no space before brace)
                    trimmed = trimmed[0 .. trimmed.len - 1];
                    // Also trim any trailing whitespace
                    trimmed = std.mem.trimRight(u8, trimmed, " \t");
                }

                try result.appendSlice(trimmed);
            } else {
                try result.appendSlice(line);
            }
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

/// Check if a script line should be included with multi-line expression support
fn shouldIncludeScriptLineWithExpressions(line: []const u8, flags: ExtractionFlags, expression_state: *ExpressionState) bool {
    const trimmed = std.mem.trim(u8, line, " \t");

    // Don't include section boundaries here - handled separately
    if (isSectionBoundary(line)) return false;

    // Update expression tracking
    updateExpressionState(expression_state, trimmed);

    // If we're in a multi-line expression, include all lines until it ends
    if (expression_state.in_multi_line_expression) {
        return true;
    }

    // Use the regular single-line logic for other cases
    return shouldIncludeScriptLine(line, flags);
}

/// Check if a script line should be included (original single-line logic)
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

        // Function signatures
        if (std.mem.startsWith(u8, trimmed, "function ") or
            std.mem.startsWith(u8, trimmed, "async function ") or
            std.mem.startsWith(u8, trimmed, "export function ") or
            std.mem.startsWith(u8, trimmed, "export async function "))
        {
            return true;
        }

        // Variable declarations (these are always single-line signatures)
        if (std.mem.startsWith(u8, trimmed, "const ") or
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
        if (std.mem.startsWith(u8, trimmed, "import ")) {
            return true;
        }
        // Only include re-export statements, not variable exports
        if (std.mem.startsWith(u8, trimmed, "export ") and 
            !std.mem.startsWith(u8, trimmed, "export let ") and
            !std.mem.startsWith(u8, trimmed, "export const ") and
            !std.mem.startsWith(u8, trimmed, "export function ")) {
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
        if (trimmed.len > 0 and (std.mem.indexOf(u8, trimmed, "{") != null or
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
        // Include ALL non-empty lines in template for structure extraction
        if (trimmed.len > 0) {
            return true;
        }
    }

    return false;
}

/// Update expression state for multi-line tracking
fn updateExpressionState(state: *ExpressionState, line: []const u8) void {
    // First count brackets on current line
    var line_brace_count: i32 = 0;
    var line_paren_count: i32 = 0;
    
    for (line) |char| {
        switch (char) {
            '{' => line_brace_count += 1,
            '}' => line_brace_count -= 1,
            '(' => line_paren_count += 1,
            ')' => line_paren_count -= 1,
            else => {},
        }
    }
    
    // Check if we're starting a multi-line expression
    if (!state.in_multi_line_expression) {
        // Check for Svelte 5 runes with function bodies that likely span multiple lines
        if (std.mem.indexOf(u8, line, "$derived.by(") != null and line_brace_count > 0) {
            state.in_multi_line_expression = true;
            state.expression_type = .derived_by;
            state.brace_depth = @intCast(line_brace_count);
            state.paren_depth = @intCast(line_paren_count);
        } else if (std.mem.indexOf(u8, line, "$effect(") != null and line_brace_count > 0) {
            state.in_multi_line_expression = true;
            state.expression_type = .effect;
            state.brace_depth = @intCast(line_brace_count);
            state.paren_depth = @intCast(line_paren_count);
        }
    } else {
        // Update bracket depth based on current line
        state.brace_depth = @intCast(@max(0, @as(i32, @intCast(state.brace_depth)) + line_brace_count));
        state.paren_depth = @intCast(@max(0, @as(i32, @intCast(state.paren_depth)) + line_paren_count));
        
        // Check if expression is complete (all brackets closed)
        if (state.brace_depth == 0 and state.paren_depth == 0) {
            // For $derived.by and $effect, expression ends when brackets are balanced
            if (state.expression_type == .derived_by or state.expression_type == .effect) {
                state.in_multi_line_expression = false;
                state.expression_type = .none;
            }
        }
    }
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
    const function_patterns = [_][]const u8{ "function ", "export function ", "const ", "let ", "export let ", "export const ", "$state", "$derived", "$effect", "$props", "$bindable", "$:" };
    const type_patterns = [_][]const u8{ "<style", "</style>", ":global", "@media", "@import", ".", "#" };
    const import_patterns = [_][]const u8{ "import ", "export " };
    const doc_patterns = [_][]const u8{ "<!--", "//" };
    const test_patterns: []const []const u8 = &[_][]const u8{}; // No tests in Svelte
    const structure_patterns = [_][]const u8{ "<script", "</script>", "<style", "</style>", "<div", "<p", "<section", "<main", "<header", "<footer", "<nav", "<article", "<aside", "<h1", "<h2", "<h3", "<h4", "<h5", "<h6", "<button", "<input", "<form", "<ul", "<ol", "<li", "<table", "<tr", "<td", "<th", "{#if", "{:else", "{/if", "{#each", "{/each", "{#await", "{/await", "{#snippet", "{@render", "<slot", "bind:", "on:", "onclick" };

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
