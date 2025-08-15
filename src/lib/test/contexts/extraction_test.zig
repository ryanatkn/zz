const std = @import("std");
const testing = std.testing;
const Language = @import("../../language/detection.zig").Language;
const ExtractionFlags = @import("../../language/flags.zig").ExtractionFlags;
const ZigExtractor = @import("../../extractors/zig.zig");
const TypeScriptExtractor = @import("../../extractors/typescript.zig");
const CssExtractor = @import("../../extractors/css.zig");
const HtmlExtractor = @import("../../extractors/html.zig");
const JsonExtractor = @import("../../extractors/json.zig");
const SvelteExtractor = @import("../../extractors/svelte.zig");

/// Specialized test context for code extraction testing
/// Reduces 40+ repeated extraction test patterns to standardized helpers
pub const ExtractionTestContext = struct {
    allocator: std.mem.Allocator,
    language: Language,
    flags: ExtractionFlags,

    /// Initialize extraction test context for given language
    pub fn init(allocator: std.mem.Allocator, language: Language) ExtractionTestContext {
        return ExtractionTestContext{
            .allocator = allocator,
            .language = language,
            .flags = .{}, // Default flags
        };
    }

    /// Initialize with custom extraction flags
    pub fn initWithFlags(allocator: std.mem.Allocator, language: Language, flags: ExtractionFlags) ExtractionTestContext {
        return ExtractionTestContext{
            .allocator = allocator,
            .language = language,
            .flags = flags,
        };
    }

    /// Extract code using appropriate language extractor
    pub fn extract(self: *ExtractionTestContext, source: []const u8) ![]u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        errdefer result.deinit();

        // Dispatch to appropriate extractor based on language
        switch (self.language) {
            .zig => try ZigExtractor.extract(self.allocator, source, self.flags, &result),
            .typescript => try TypeScriptExtractor.extract(self.allocator, source, self.flags, &result),
            .css => try CssExtractor.extract(self.allocator, source, self.flags, &result),
            .html => try HtmlExtractor.extract(self.allocator, source, self.flags, &result),
            .json => try JsonExtractor.extract(self.allocator, source, self.flags, &result),
            .svelte => try SvelteExtractor.extract(self.allocator, source, self.flags, &result),
            else => {
                // For unsupported languages, return empty extraction
                return try self.allocator.dupe(u8, "");
            },
        }

        return result.toOwnedSlice();
    }

    /// Extract and expect specific result
    pub fn extractExpecting(self: *ExtractionTestContext, source: []const u8, expected: []const u8) !void {
        const result = try self.extract(source);
        defer self.allocator.free(result);

        try testing.expectEqualStrings(expected, result);
    }

    /// Extract and expect result contains specific parts
    pub fn expectStructure(self: *ExtractionTestContext, source: []const u8, expected_parts: []const []const u8) !void {
        const result = try self.extract(source);
        defer self.allocator.free(result);

        for (expected_parts) |part| {
            try testing.expect(std.mem.indexOf(u8, result, part) != null);
        }
    }

    /// Extract with signatures flag and expect specific signatures
    pub fn expectSignatures(self: *ExtractionTestContext, source: []const u8, expected_signatures: []const []const u8) !void {
        var context = ExtractionTestContext.initWithFlags(self.allocator, self.language, .{
            .signatures = true,
            .structure = false,
            .full = false,
        });

        const result = try context.extract(source);
        defer self.allocator.free(result);

        for (expected_signatures) |signature| {
            try testing.expect(std.mem.indexOf(u8, result, signature) != null);
        }
    }

    /// Extract with types flag and expect specific type definitions
    pub fn expectTypes(self: *ExtractionTestContext, source: []const u8, expected_types: []const []const u8) !void {
        var context = ExtractionTestContext.initWithFlags(self.allocator, self.language, .{
            .types = true,
            .structure = false,
            .full = false,
        });

        const result = try context.extract(source);
        defer self.allocator.free(result);

        for (expected_types) |type_def| {
            try testing.expect(std.mem.indexOf(u8, result, type_def) != null);
        }
    }

    /// Extract with docs flag and expect documentation comments
    pub fn expectDocs(self: *ExtractionTestContext, source: []const u8, expected_docs: []const []const u8) !void {
        var context = ExtractionTestContext.initWithFlags(self.allocator, self.language, .{
            .docs = true,
            .structure = false,
            .full = false,
        });

        const result = try context.extract(source);
        defer self.allocator.free(result);

        for (expected_docs) |doc| {
            try testing.expect(std.mem.indexOf(u8, result, doc) != null);
        }
    }

    /// Extract with imports flag and expect import statements
    pub fn expectImports(self: *ExtractionTestContext, source: []const u8, expected_imports: []const []const u8) !void {
        var context = ExtractionTestContext.initWithFlags(self.allocator, self.language, .{
            .imports = true,
            .structure = false,
            .full = false,
        });

        const result = try context.extract(source);
        defer self.allocator.free(result);

        for (expected_imports) |import| {
            try testing.expect(std.mem.indexOf(u8, result, import) != null);
        }
    }

    /// Extract and expect empty result (no matching content)
    pub fn expectEmpty(self: *ExtractionTestContext, source: []const u8) !void {
        const result = try self.extract(source);
        defer self.allocator.free(result);

        const trimmed = std.mem.trim(u8, result, " \t\n\r");
        try testing.expect(trimmed.len == 0);
    }

    /// Extract and expect non-empty result
    pub fn expectNonEmpty(self: *ExtractionTestContext, source: []const u8) !void {
        const result = try self.extract(source);
        defer self.allocator.free(result);

        const trimmed = std.mem.trim(u8, result, " \t\n\r");
        try testing.expect(trimmed.len > 0);
    }

    /// Test that extraction doesn't contain unexpected content
    pub fn expectExcludes(self: *ExtractionTestContext, source: []const u8, excluded_parts: []const []const u8) !void {
        const result = try self.extract(source);
        defer self.allocator.free(result);

        for (excluded_parts) |part| {
            try testing.expect(std.mem.indexOf(u8, result, part) == null);
        }
    }

    /// Test extraction with multiple flag combinations
    pub fn testFlagCombinations(self: *ExtractionTestContext, source: []const u8, test_cases: []const struct {
        flags: ExtractionFlags,
        expected_contains: []const []const u8,
        expected_excludes: []const []const u8,
    }) !void {
        for (test_cases) |test_case| {
            var context = ExtractionTestContext.initWithFlags(self.allocator, self.language, test_case.flags);

            const result = try context.extract(source);
            defer self.allocator.free(result);

            // Check expected content is present
            for (test_case.expected_contains) |part| {
                try testing.expect(std.mem.indexOf(u8, result, part) != null);
            }

            // Check excluded content is not present
            for (test_case.expected_excludes) |part| {
                try testing.expect(std.mem.indexOf(u8, result, part) == null);
            }
        }
    }

    /// Helper for testing line count in extraction results
    pub fn expectLineCount(self: *ExtractionTestContext, source: []const u8, expected_lines: usize) !void {
        const result = try self.extract(source);
        defer self.allocator.free(result);

        var line_count: usize = 0;
        var iter = std.mem.splitScalar(u8, result, '\n');
        while (iter.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len > 0) {
                line_count += 1;
            }
        }

        try testing.expectEqual(expected_lines, line_count);
    }

    /// Helper for testing extraction with malformed input
    pub fn testMalformedInput(self: *ExtractionTestContext, malformed_sources: []const []const u8) !void {
        for (malformed_sources) |source| {
            // Should not crash or panic on malformed input
            const result = self.extract(source) catch |err| {
                // Some extraction errors are acceptable
                if (err == error.OutOfMemory) {
                    return err; // Propagate memory errors
                }
                continue; // Other errors are acceptable for malformed input
            };
            defer self.allocator.free(result);

            // Result should be valid (even if empty)
            try testing.expect(result.len >= 0);
        }
    }
};

// Tests for the ExtractionTestContext itself
test "ExtractionTestContext basic usage" {
    var context = ExtractionTestContext.init(testing.allocator, .zig);

    const source = "pub fn test() void {}";
    try context.expectNonEmpty(source);
}

test "ExtractionTestContext signature extraction" {
    var context = ExtractionTestContext.init(testing.allocator, .zig);

    const source = "pub fn add(a: i32, b: i32) i32 { return a + b; }";
    const expected_signatures = [_][]const u8{"pub fn add(a: i32, b: i32) i32"};

    try context.expectSignatures(source, &expected_signatures);
}

test "ExtractionTestContext structure expectations" {
    var context = ExtractionTestContext.init(testing.allocator, .zig);

    const source = "const std = @import(\"std\");\npub fn test() void {}";
    const expected_parts = [_][]const u8{ "@import", "pub fn test" };

    try context.expectStructure(source, &expected_parts);
}

test "ExtractionTestContext flag combinations" {
    var context = ExtractionTestContext.init(testing.allocator, .zig);

    const source = "/// Documentation\npub fn test() void { const x = 42; }";
    const test_cases = [_]struct {
        flags: ExtractionFlags,
        expected_contains: []const []const u8,
        expected_excludes: []const []const u8,
    }{
        .{
            .flags = .{ .signatures = true, .docs = true },
            .expected_contains = &[_][]const u8{ "/// Documentation", "pub fn test" },
            .expected_excludes = &[_][]const u8{"const x = 42"},
        },
    };

    try context.testFlagCombinations(source, &test_cases);
}
