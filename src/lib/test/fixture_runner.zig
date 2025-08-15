const std = @import("std");
const testing = std.testing;
const FixtureLoader = @import("fixture_loader.zig").FixtureLoader;
const TestFixtures = @import("fixture_loader.zig").TestFixtures;
const LanguageFixtures = @import("fixture_loader.zig").LanguageFixtures;
const ParserTest = @import("fixture_loader.zig").ParserTest;
const FormatterTest = @import("fixture_loader.zig").FormatterTest;
const ExtractionTest = @import("fixture_loader.zig").ExtractionTest;
const extractor_mod = @import("../language/extractor.zig");
const Extractor = extractor_mod.Extractor;
const Language = @import("../language/detection.zig").Language;
const Formatter = @import("../parsing/formatter.zig").Formatter;


/// Simple test utilities for fixture-based testing
pub const TestUtils = struct {
    /// Run a parser test case with all its extraction variations
    pub fn runParserTest(allocator: std.mem.Allocator, extractor: Extractor, parser_test: ParserTest, language: Language) !void {
        if (parser_test.source.len == 0 or parser_test.extraction_tests.len == 0) {
            return;
        }

        for (parser_test.extraction_tests) |extraction_test| {
            const actual = extractor.extract(language, parser_test.source, extraction_test.flags) catch |err| {
                std.log.err("Parser test '{s}' failed for {s}: {}", .{ parser_test.name, @tagName(language), err });
                return err;
            };
            defer allocator.free(actual);

            if (!std.mem.eql(u8, actual, extraction_test.expected)) {
                std.log.err("Parser test '{s}' for {s} failed:", .{ parser_test.name, @tagName(language) });
                std.log.err("Expected:\n{s}", .{extraction_test.expected});
                std.log.err("Actual:\n{s}", .{actual});
                std.log.err("Flags: {}", .{extraction_test.flags});
                return error.TestFailed;
            }
        }
    }

    /// Run a formatter test case
    pub fn runFormatterTest(allocator: std.mem.Allocator, formatter_test: FormatterTest, language: Language) !void {
        var formatter = Formatter.init(allocator, language, formatter_test.options);

        const actual = formatter.format(formatter_test.source) catch |err| {
            if (err == error.UnsupportedLanguage) {
                return; // Skip unsupported languages gracefully
            }
            std.log.err("Formatter test '{s}' failed for {s}: {}", .{ formatter_test.name, @tagName(language), err });
            return err;
        };
        defer allocator.free(actual);

        if (!std.mem.eql(u8, actual, formatter_test.expected)) {
            std.log.err("Formatter test '{s}' for {s} failed:", .{ formatter_test.name, @tagName(language) });
            std.log.err("Expected:\n{s}", .{formatter_test.expected});
            std.log.err("Actual:\n{s}", .{actual});
            std.log.err("Options: {}", .{formatter_test.options});
            return error.TestFailed;
        }
    }
};



/// Generic function to test all fixtures for a specific language
fn testLanguageFixtures(language: Language) !void {
    const loader = FixtureLoader.init(testing.allocator);
    var fixtures = loader.loadLanguage(language) catch |err| {
        std.log.err("Failed to load {s} fixtures: {}", .{ @tagName(language), err });
        return err;
    };
    defer fixtures.deinit(testing.allocator);

    var extractor = try extractor_mod.createTestExtractor(testing.allocator);
    defer {
        extractor.registry.deinit();
        testing.allocator.destroy(extractor.registry);
    }

    // Run all parser tests with proper validation
    for (fixtures.parser_tests) |parser_test| {
        try TestUtils.runParserTest(testing.allocator, extractor, parser_test, language);
    }

    // Run all formatter tests with proper validation
    for (fixtures.formatter_tests) |formatter_test| {
        try TestUtils.runFormatterTest(testing.allocator, formatter_test, language);
    }
}

// All supported languages for fixture testing
const test_languages = [_]Language{ .json, .css, .html, .typescript, .svelte, .zig };

// Generate tests for all languages  
test "all language fixture tests" {
    var success_count: u32 = 0;
    var skip_count: u32 = 0;
    
    inline for (test_languages) |language| {
        if (testLanguageFixtures(language)) {
            success_count += 1;
        } else |err| {
            // Skip languages that don't have fixture files
            if (err == error.FileNotFound or err == error.UnsupportedLanguage) {
                skip_count += 1;
            } else {
                return err;
            }
        }
    }
    
    // Ensure at least some tests ran successfully
    try testing.expect(success_count > 0);
}


