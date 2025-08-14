const std = @import("std");
const ExtractionFlags = @import("../../language/flags.zig").ExtractionFlags;
const line_processing = @import("../../text/line_processing.zig");
const text_patterns = @import("../../text/patterns.zig");
const builders = @import("../../text/builders.zig");

/// Extract code using tree-sitter AST or patterns as fallback
pub fn extract(_: std.mem.Allocator, source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) !void {
    // Use pattern-based extraction for now (tree-sitter integration in future)
    try extractWithPatterns(source, flags, result);
}

fn extractWithPatterns(source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) !void {
    var lines = std.mem.splitScalar(u8, source, '\n');
    var block_tracker = line_processing.BlockTracker.init();

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");

        // Track block depth for multi-line interfaces/types
        if (block_tracker.isInBlock()) {
            try builders.appendLine(result, line);
            block_tracker.processLine(line);
            continue;
        }

        var should_include = false;
        var starts_block = false;

        // Functions
        if (flags.signatures) {
            if (text_patterns.startsWithAny(trimmed, &text_patterns.Patterns.ts_functions) or
                std.mem.indexOf(u8, trimmed, "=>") != null)
            {
                should_include = true;
            }
        }

        // Types and interfaces
        if (flags.types) {
            if (text_patterns.startsWithAny(trimmed, &text_patterns.Patterns.ts_types)) {
                should_include = true;
                if (std.mem.indexOf(u8, line, "{") != null) {
                    starts_block = true;
                }
            }
        }

        // Imports
        if (flags.imports) {
            if (text_patterns.startsWithAny(trimmed, &text_patterns.Patterns.ts_imports)) {
                should_include = true;
            }
        }

        // Documentation comments
        if (flags.docs) {
            if (std.mem.startsWith(u8, trimmed, "/**") or
                std.mem.startsWith(u8, trimmed, "//"))
            {
                should_include = true;
            }
        }

        // Tests
        if (flags.tests) {
            if (std.mem.indexOf(u8, trimmed, "test(") != null or
                std.mem.indexOf(u8, trimmed, "it(") != null or
                std.mem.indexOf(u8, trimmed, "describe(") != null or
                std.mem.indexOf(u8, trimmed, "expect(") != null)
            {
                should_include = true;
            }
        }

        // Full source
        if (flags.full) {
            should_include = true;
        }

        if (should_include) {
            try builders.appendLine(result, line);
            if (starts_block) {
                block_tracker.processLine(line);
            }
        }
    }
}
