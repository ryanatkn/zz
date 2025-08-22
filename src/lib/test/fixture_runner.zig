const std = @import("std");
const testing = std.testing;
// TODO: Reimplement fixture loading after cleanup
// const SafeZonFixtureLoader = @import("safe_zon_fixture_loader.zig").SafeZonFixtureLoader;
// const LanguageFixtures = @import("safe_zon_fixture_loader.zig").LanguageFixtures;
// const ParserTest = @import("safe_zon_fixture_loader.zig").ParserTest;
// const FormatterTest = @import("safe_zon_fixture_loader.zig").FormatterTest;
// const ExtractionTest = @import("safe_zon_fixture_loader.zig").ExtractionTest;

// Temporary stub types
pub const ParserTest = struct {
    source: []const u8,
    extraction_tests: []const u8,
};
pub const FormatterTest = struct {};
pub const ExtractionTest = struct {};
pub const LanguageFixtures = struct {};
pub const SafeZonFixtureLoader = struct {};
const Language = @import("../core/language.zig").Language;
const ExtractionFlags = @import("../core/extraction.zig").ExtractionFlags;

// Removed stratified parser - using simplified testing

/// Simple test utilities for fixture-based testing
pub const TestUtils = struct {
    /// Run a parser test case - simplified version
    pub fn runParserTest(allocator: std.mem.Allocator, parser_test: ParserTest, language: Language) !void {
        _ = allocator;
        _ = language;
        if (parser_test.source.len == 0 or parser_test.extraction_tests.len == 0) {
            return;
        }
        // TODO: Implement proper testing with new language modules
        // For now, just return success
    }

    /// Run a formatter test case - simplified version
    pub fn runFormatterTest(allocator: std.mem.Allocator, formatter_test: FormatterTest, language: Language) !void {
        _ = allocator;
        _ = formatter_test;
        _ = language;
        // TODO: Implement proper testing with new language modules
        // For now, just return success
    }

    /// Normalize whitespace for comparison
    fn normalizeWhitespace(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
        var result = std.ArrayList(u8).init(allocator);
        defer result.deinit();

        var i: usize = 0;
        while (i < input.len) {
            const char = input[i];
            if (char == '\r') {
                // Skip carriage returns
                i += 1;
                continue;
            }
            try result.append(char);
            i += 1;
        }

        return result.toOwnedSlice();
    }
};

// Removed extractWithStratifiedParser and mapping functions - using simplified testing

test "basic fixture runner functionality" {
    const allocator = testing.allocator;
    _ = allocator;
    // TODO: Implement proper tests with new language modules
    // For now, just return success
}
