const std = @import("std");

/// Demo step configuration
pub const DemoStep = struct {
    title: []const u8,
    description: []const u8,
    command: []const u8,
    args: []const []const u8,
    max_lines: ?usize = null,
    show_file_preview: bool = false,
    file_to_preview: ?[]const u8 = null,
    preview_lines: usize = 15,
};

/// All demo steps in order
pub const demo_steps = [_]DemoStep{
    .{
        .title = "Directory Tree Visualization",
        .description = "Display the structure of the examples directory",
        .command = "tree",
        .args = &.{ "examples", "--no-gitignore" },
    },
    .{
        .title = "List Format Output",
        .description = "Show files in a flat list format",
        .command = "tree",
        .args = &.{ "examples", "--format=list" },
    },
    .{
        .title = "TypeScript Code Extraction",
        .description = "Extract signatures and types from TypeScript",
        .command = "prompt",
        .args = &.{ "examples/app.ts", "--signatures", "--types" },
        .show_file_preview = true,
        .file_to_preview = "examples/app.ts",
        .preview_lines = 15,
    },
    .{
        .title = "CSS Structure Extraction",
        .description = "Extract CSS selectors and properties",
        .command = "prompt",
        .args = &.{ "examples/styles.css", "--types" },
        .max_lines = 30,
    },
    .{
        .title = "HTML Structure Analysis",
        .description = "Extract HTML document structure",
        .command = "prompt",
        .args = &.{ "examples/index.html", "--structure" },
        .max_lines = 30,
    },
    .{
        .title = "Svelte Component Parsing",
        .description = "Parse multi-section Svelte components",
        .command = "prompt",
        .args = &.{ "examples/component.svelte", "--signatures", "--types" },
        .max_lines = 40,
    },
    .{
        .title = "Svelte 5 Runes (TypeScript)",
        .description = "Parse modern reactive Svelte with TypeScript",
        .command = "prompt",
        .args = &.{ "examples/runes.svelte.ts", "--signatures", "--types" },
        .max_lines = 40,
    },
    .{
        .title = "JSON Structure Extraction",
        .description = "Extract JSON keys and structure",
        .command = "prompt",
        .args = &.{ "examples/config.json", "--structure" },
    },
    .{
        .title = "Glob Pattern Processing",
        .description = "Process multiple file types with glob patterns",
        .command = "prompt",
        .args = &.{ "examples/*.{ts,css,html,svelte}", "--signatures" },
        .max_lines = 40,
    },
    .{
        .title = "Performance Benchmarks",
        .description = "Run performance benchmarks with pretty output",
        .command = "benchmark",
        .args = &.{"--format=pretty"},
    },
};

/// Get a specific step by index
pub fn getStep(index: usize) ?DemoStep {
    if (index >= demo_steps.len) return null;
    return demo_steps[index];
}

/// Get total number of steps
pub fn getStepCount() usize {
    return demo_steps.len;
}

/// Demo summary information for the end
pub const summary = struct {
    pub const features = [_][]const u8{
        "Terminal-only rendering with clean output",
        "Fast directory traversal with pattern matching",
        "Language-aware code extraction (TS, CSS, HTML, JSON, Svelte, Svelte+TS)",
        "Multiple extraction modes (signatures, types, structure)",
        "Glob pattern support for file selection",
        "Performance benchmarking capabilities",
    };
    
    pub const performance = [_]struct {
        name: []const u8,
        value: []const u8,
    }{
        .{ .name = "Path operations", .value = "~47μs per operation (20-30% faster than stdlib)" },
        .{ .name = "String pooling", .value = "~145ns per operation" },
        .{ .name = "Pattern matching", .value = "~25ns per operation" },
    };
    
    pub const repository = "https://github.com/ryanatkn/zz";
};

/// Format step number for display
pub fn formatStepNumber(step_num: usize) [32]u8 {
    var buf: [32]u8 = undefined;
    const slice = std.fmt.bufPrint(&buf, "Step {}/{}", .{ step_num, demo_steps.len }) catch "";
    var result: [32]u8 = undefined;
    @memcpy(result[0..slice.len], slice);
    return result;
}

/// Check if a step should show output truncation message
pub fn shouldTruncate(step: DemoStep) bool {
    return step.max_lines != null;
}

/// Get truncation message for a step
pub fn getTruncationMessage(step: DemoStep) []const u8 {
    _ = step;
    return "... (output truncated for demo)";
}