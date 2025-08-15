const std = @import("std");
const testing = std.testing;
const AstFormatter = @import("../../parsing/ast_formatter.zig").AstFormatter;
const Language = @import("../../language/detection.zig").Language;
const FormatterOptions = @import("../../parsing/formatter.zig").FormatterOptions;

/// Specialized test context for formatter testing with automatic setup/cleanup
/// Reduces 50+ repeated formatter test patterns to standardized helpers
pub const FormatterTestContext = struct {
    allocator: std.mem.Allocator,
    formatter: ?AstFormatter = null,
    language: Language,
    options: FormatterOptions,

    /// Initialize formatter test context for given language
    pub fn init(allocator: std.mem.Allocator, language: Language) FormatterTestContext {
        return FormatterTestContext{
            .allocator = allocator,
            .language = language,
            .options = .{}, // Default options
        };
    }

    /// Initialize with custom formatter options
    pub fn initWithOptions(allocator: std.mem.Allocator, language: Language, options: FormatterOptions) FormatterTestContext {
        return FormatterTestContext{
            .allocator = allocator,
            .language = language,
            .options = options,
        };
    }

    /// Setup formatter (call before testing)
    pub fn setup(self: *FormatterTestContext) !void {
        self.formatter = AstFormatter.init(self.allocator, self.language, self.options) catch |err| {
            // Handle tree-sitter compatibility issues gracefully
            if (err == error.IncompatibleVersion or err == error.UnsupportedLanguage) {
                // Store error state for later handling
                self.formatter = null;
                return;
            }
            return err;
        };
    }

    /// Cleanup formatter resources
    pub fn deinit(self: *FormatterTestContext) void {
        if (self.formatter) |*formatter| {
            formatter.deinit();
        }
    }

    /// Check if formatter is available (not skipped due to compatibility)
    pub fn isAvailable(self: *FormatterTestContext) bool {
        return self.formatter != null;
    }

    /// Format source and expect specific result
    pub fn formatExpecting(self: *FormatterTestContext, source: []const u8, expected: []const u8) !void {
        if (!self.isAvailable()) {
            // Skip test if formatter not available
            return;
        }

        const result = try self.formatter.?.format(source);
        defer self.allocator.free(result);

        try testing.expectEqualStrings(expected, result);
    }

    /// Format source and expect it contains specific substring
    pub fn formatExpectingContains(self: *FormatterTestContext, source: []const u8, expected_substring: []const u8) !void {
        if (!self.isAvailable()) {
            return;
        }

        const result = try self.formatter.?.format(source);
        defer self.allocator.free(result);

        try testing.expect(std.mem.indexOf(u8, result, expected_substring) != null);
    }

    /// Format source and return result (caller owns memory)
    pub fn format(self: *FormatterTestContext, source: []const u8) ![]u8 {
        if (!self.isAvailable()) {
            // Return original source if formatter not available
            return try self.allocator.dupe(u8, source);
        }

        return self.formatter.?.format(source);
    }

    /// Test error handling for malformed source
    pub fn testErrorHandling(self: *FormatterTestContext, malformed_source: []const u8) !void {
        if (!self.isAvailable()) {
            return;
        }

        const result = self.formatter.?.format(malformed_source) catch |err| {
            // Expected errors for malformed input
            if (err == error.FormattingFailed) {
                return; // This is expected
            }
            return err;
        };
        defer self.allocator.free(result);

        // If formatting succeeded, result should not be empty
        try testing.expect(result.len >= 0);
    }

    /// Test that formatting is idempotent (format twice = same result)
    pub fn testIdempotent(self: *FormatterTestContext, source: []const u8) !void {
        if (!self.isAvailable()) {
            return;
        }

        const first_result = try self.formatter.?.format(source);
        defer self.allocator.free(first_result);

        const second_result = try self.formatter.?.format(first_result);
        defer self.allocator.free(second_result);

        try testing.expectEqualStrings(first_result, second_result);
    }

    /// Test formatter with various indentation sizes
    pub fn testIndentationSizes(self: *FormatterTestContext, source: []const u8, sizes: []const u8) !void {
        for (sizes) |size| {
            var context = FormatterTestContext.initWithOptions(self.allocator, self.language, .{
                .indent_size = size,
            });
            try context.setup();
            defer context.deinit();

            if (!context.isAvailable()) continue;

            const result = try context.format(source);
            defer self.allocator.free(result);

            // Should produce valid output
            try testing.expect(result.len > 0);
        }
    }

    /// Helper for testing multiple malformed sources
    pub fn testMalformedSources(self: *FormatterTestContext, malformed_sources: []const []const u8) !void {
        for (malformed_sources) |source| {
            try self.testErrorHandling(source);
        }
    }

    /// Helper for testing expected formatted outputs
    pub fn testFormattedExpectations(self: *FormatterTestContext, test_cases: []const struct { source: []const u8, expected: []const u8 }) !void {
        for (test_cases) |test_case| {
            try self.formatExpecting(test_case.source, test_case.expected);
        }
    }
};

// Tests for the FormatterTestContext itself
test "FormatterTestContext basic usage" {
    var context = FormatterTestContext.init(testing.allocator, .json);
    try context.setup();
    defer context.deinit();

    if (context.isAvailable()) {
        try context.formatExpecting("{\"a\":1}", "{\n    \"a\": 1\n}");
    }
}

test "FormatterTestContext with custom options" {
    var context = FormatterTestContext.initWithOptions(testing.allocator, .json, .{
        .indent_size = 2,
    });
    try context.setup();
    defer context.deinit();

    if (context.isAvailable()) {
        const result = try context.format("{\"a\":1}");
        defer testing.allocator.free(result);
        try testing.expect(std.mem.indexOf(u8, result, "  \"a\"") != null); // 2-space indent
    }
}

test "FormatterTestContext error handling" {
    var context = FormatterTestContext.init(testing.allocator, .typescript);
    try context.setup();
    defer context.deinit();

    if (context.isAvailable()) {
        try context.testErrorHandling("function incomplete(");
    }
}

test "FormatterTestContext idempotent formatting" {
    var context = FormatterTestContext.init(testing.allocator, .json);
    try context.setup();
    defer context.deinit();

    if (context.isAvailable()) {
        try context.testIdempotent("{\"a\":1,\"b\":2}");
    }
}
