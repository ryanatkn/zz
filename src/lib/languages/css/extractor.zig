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

    // For types flag, extract selectors and rules (CSS "types" are selectors)
    if (flags.types) {
        // Simple approach: include lines with { or starting with CSS selector characters
        var lines = std.mem.splitScalar(u8, source, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t");
            if (trimmed.len == 0) continue;
            
            // Include lines with { (rules) or starting with ., #, @, etc.
            if (std.mem.indexOf(u8, trimmed, "{") != null or
                std.mem.startsWith(u8, trimmed, ".") or
                std.mem.startsWith(u8, trimmed, "#") or
                std.mem.startsWith(u8, trimmed, "@")) {
                try result.appendSlice(line);
                try result.append('\n');
            }
        }
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

        var should_include = false;

        // Check for @rules (media queries, keyframes, etc.)
        if (std.mem.startsWith(u8, trimmed, "@")) {
            should_include = true;
        }

        // Check for CSS selectors (lines containing { or starting with selector patterns)
        if (std.mem.indexOf(u8, trimmed, "{") != null) {
            should_include = true;
        } else if (text_patterns.startsWithAny(trimmed, &text_patterns.Patterns.css_selectors)) {
            should_include = true;
        }

        if (should_include) {
            try builders.appendLine(result, line);
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