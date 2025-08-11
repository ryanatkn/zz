const std = @import("std");

pub const Config = @import("config.zig").Config;
pub const PromptBuilder = @import("builder.zig").PromptBuilder;
pub const GlobExpander = @import("glob.zig").GlobExpander;

pub fn run(allocator: std.mem.Allocator, args: [][:0]const u8) !void {
    // Parse configuration from args
    var config = try Config.fromArgs(allocator, args);
    defer config.deinit();
    
    // Get file patterns from args
    var patterns = try config.getFilePatterns(args);
    defer patterns.deinit();
    
    // Expand glob patterns to actual file paths with info
    var expander = GlobExpander.init(allocator);
    var pattern_results = try expander.expandPatternsWithInfo(patterns.items);
    defer {
        for (pattern_results.items) |*result| {
            for (result.files.items) |path| {
                allocator.free(path);
            }
            result.files.deinit();
        }
        pattern_results.deinit();
    }
    
    // Check for patterns that matched no files
    const stderr = std.io.getStdErr().writer();
    var has_error = false;
    
    for (pattern_results.items) |result| {
        if (result.files.items.len == 0) {
            if (result.is_glob) {
                // Glob pattern with no matches
                if (config.allow_empty_glob or config.allow_missing) {
                    try stderr.print("Warning: No files matched pattern: {s}\n", .{result.pattern});
                } else {
                    try stderr.print("Error: No files matched pattern: {s}\n", .{result.pattern});
                    has_error = true;
                }
            } else {
                // Explicit file that doesn't exist
                if (config.allow_missing) {
                    try stderr.print("Warning: File not found: {s}\n", .{result.pattern});
                } else {
                    try stderr.print("Error: File not found: {s}\n", .{result.pattern});
                    has_error = true;
                }
            }
        }
    }
    
    if (has_error) {
        return error.PatternsNotMatched;
    }
    
    // Collect all files and deduplicate
    var seen = std.StringHashMap(void).init(allocator);
    defer seen.deinit();
    
    var filtered_paths = std.ArrayList([]u8).init(allocator);
    defer filtered_paths.deinit();
    
    for (pattern_results.items) |result| {
        for (result.files.items) |path| {
            if (!config.shouldIgnore(path)) {
                // Check if we've already seen this path
                if (!seen.contains(path)) {
                    try seen.put(path, {});
                    try filtered_paths.append(path);
                }
            }
        }
    }
    
    // Build the prompt
    var builder = PromptBuilder.init(allocator);
    defer builder.deinit();
    
    // Add prepend text if provided
    if (config.prepend_text) |text| {
        try builder.addText(text);
    }
    
    // Add all files
    try builder.addFiles(filtered_paths.items);
    
    // Add append text if provided
    if (config.append_text) |text| {
        try builder.addText(text);
    }
    
    // Write to stdout
    const stdout = std.io.getStdOut().writer();
    try builder.write(stdout);
}