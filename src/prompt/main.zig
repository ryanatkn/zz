const std = @import("std");
const FilesystemInterface = @import("../lib/filesystem/interface.zig").FilesystemInterface;
const path_utils = @import("../lib/core/path.zig");
const reporting = @import("../lib/core/reporting.zig");

pub const Config = @import("config.zig").Config;
pub const PromptBuilder = @import("builder.zig").PromptBuilder;
pub const GlobExpander = @import("glob.zig").GlobExpander;

pub fn run(allocator: std.mem.Allocator, filesystem: FilesystemInterface, args: [][:0]const u8) !void {
    return runInternal(allocator, filesystem, args, false);
}

pub fn runQuiet(allocator: std.mem.Allocator, filesystem: FilesystemInterface, args: [][:0]const u8) !void {
    return runInternal(allocator, filesystem, args, true);
}

pub fn runWithConfig(config: *Config, allocator: std.mem.Allocator, filesystem: FilesystemInterface, args: [][:0]const u8) !void {
    return runWithConfigInternal(config, allocator, filesystem, args, false);
}

pub fn runWithConfigQuiet(config: *Config, allocator: std.mem.Allocator, filesystem: FilesystemInterface, args: [][:0]const u8) !void {
    return runWithConfigInternal(config, allocator, filesystem, args, true);
}

fn runInternal(allocator: std.mem.Allocator, filesystem: FilesystemInterface, args: [][:0]const u8, quiet: bool) !void {
    // Parse configuration from args
    var config = try Config.fromArgs(allocator, filesystem, args);
    defer config.deinit();

    return runWithConfigInternal(&config, allocator, filesystem, args, quiet);
}

fn runWithConfigInternal(config: *Config, allocator: std.mem.Allocator, filesystem: FilesystemInterface, args: [][:0]const u8, quiet: bool) !void {
    // Get file patterns from args
    var patterns = config.getFilePatterns(args) catch |err| {
        if (err == error.NoInputFiles) {
            if (!quiet) {
                try reporting.reportError("No input files specified. Use './zz prompt <files>' or provide --prepend/--append text", .{});
            }
            return error.PatternsNotMatched;
        }
        return err;
    };
    defer patterns.deinit();

    // Expand glob patterns to actual file paths with info
    const expander = GlobExpander{
        .allocator = allocator,
        .filesystem = filesystem,
        .config = config.shared_config,
    };
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
    var has_error = false;

    if (!quiet) {
        for (pattern_results.items) |result| {
            if (result.files.items.len == 0) {
                if (result.is_glob) {
                    // Glob pattern with no matches
                    if (config.allow_empty_glob or config.allow_missing) {
                        const prefixed = try path_utils.addRelativePrefix(allocator, result.pattern);
                        defer allocator.free(prefixed);
                        try reporting.reportWarning("No files matched pattern: {s}", .{prefixed});
                    } else {
                        const prefixed = try path_utils.addRelativePrefix(allocator, result.pattern);
                        defer allocator.free(prefixed);
                        try reporting.reportError("No files matched pattern: {s}", .{prefixed});
                        has_error = true;
                    }
                } else {
                    // Explicit file that doesn't exist
                    if (config.allow_missing) {
                        const prefixed = try path_utils.addRelativePrefix(allocator, result.pattern);
                        defer allocator.free(prefixed);
                        try reporting.reportWarning("File not found: {s}", .{prefixed});
                    } else {
                        const prefixed = try path_utils.addRelativePrefix(allocator, result.pattern);
                        defer allocator.free(prefixed);
                        try reporting.reportError("File not found: {s}", .{prefixed});
                        has_error = true;
                    }
                }
            }
        }
    } else {
        // In quiet mode, still need to check for errors but don't print messages
        for (pattern_results.items) |result| {
            if (result.files.items.len == 0) {
                if (result.is_glob) {
                    if (!(config.allow_empty_glob or config.allow_missing)) {
                        has_error = true;
                    }
                } else {
                    if (!config.allow_missing) {
                        has_error = true;
                    }
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
            if (config.shouldIgnore(path)) {
                // Check if this was an explicitly requested file (not a glob pattern)
                if (!result.is_glob) {
                    // User explicitly requested this file but it's being ignored
                    if (!quiet) {
                        const prefixed = try path_utils.addRelativePrefix(allocator, path);
                        defer allocator.free(prefixed);
                        try reporting.reportError("Explicitly requested file was ignored: {s}", .{prefixed});
                    }
                    has_error = true;
                }
                // For glob patterns, we silently ignore filtered files
                continue;
            }

            // File is not ignored, check if we've already seen this path
            if (!seen.contains(path)) {
                try seen.put(path, {});
                try filtered_paths.append(path);
            }
        }
    }

    // Check for errors after processing all files
    if (has_error) {
        return error.PatternsNotMatched;
    }

    // Build the prompt
    var builder = if (quiet)
        PromptBuilder.initQuiet(allocator, filesystem, config.extraction_flags)
    else
        PromptBuilder.init(allocator, filesystem, config.extraction_flags);
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
