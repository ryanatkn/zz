const std = @import("std");
const ExtractionFlags = @import("../../language/flags.zig").ExtractionFlags;
const line_processing = @import("../../text/line_processing.zig");
const text_patterns = @import("../../text/patterns.zig");
const builders = @import("../../text/builders.zig");

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