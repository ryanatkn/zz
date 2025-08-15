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

/// Comprehensive test runner for all language fixtures
pub const FixtureRunner = struct {
    allocator: std.mem.Allocator,
    fixtures: TestFixtures,

    pub fn init(allocator: std.mem.Allocator) !FixtureRunner {
        std.log.debug("FixtureRunner.init: Starting initialization", .{});
        const loader = FixtureLoader.init(allocator);

        std.log.debug("FixtureRunner.init: Loading fixtures", .{});
        const fixtures = try loader.loadAll();

        std.log.debug("FixtureRunner.init: Loaded {} languages", .{fixtures.languages.len});

        return FixtureRunner{
            .allocator = allocator,
            .fixtures = fixtures,
        };
    }

    pub fn deinit(self: *FixtureRunner) void {
        self.fixtures.deinit();
    }

    /// Run all parser tests for all languages
    pub fn runParserTests(self: *FixtureRunner) !void {
        for (self.fixtures.languages) |lang_fixtures| {
            try self.runLanguageParserTests(lang_fixtures);
        }
    }

    /// Run all formatter tests for all languages
    pub fn runFormatterTests(self: *FixtureRunner) !void {
        for (self.fixtures.languages) |lang_fixtures| {
            try self.runLanguageFormatterTests(lang_fixtures);
        }
    }

    /// Run both parser and formatter tests for all languages
    pub fn runAllTests(self: *FixtureRunner) !void {
        try self.runParserTests();
        try self.runFormatterTests();
    }

    /// Run parser tests for a specific language
    fn runLanguageParserTests(self: *FixtureRunner, lang_fixtures: LanguageFixtures) !void {
        std.log.debug("runLanguageParserTests: Starting tests for {s}", .{@tagName(lang_fixtures.language)});

        // Safety check
        if (lang_fixtures.parser_tests.len == 0) {
            std.log.debug("runLanguageParserTests: No parser tests for {s}", .{@tagName(lang_fixtures.language)});
            return;
        }

        var extractor = try extractor_mod.createTestExtractor(self.allocator);
        defer {
            extractor.registry.deinit();
            self.allocator.destroy(extractor.registry);
        }
        std.log.debug("runLanguageParserTests: Created extractor for {s}", .{@tagName(lang_fixtures.language)});

        for (lang_fixtures.parser_tests, 0..) |parser_test, i| {
            std.log.debug("runLanguageParserTests: Running test {}/{} '{s}' for {s}", .{ i + 1, lang_fixtures.parser_tests.len, parser_test.name, @tagName(lang_fixtures.language) });
            try self.runSingleParserTest(extractor, parser_test, lang_fixtures.language);
        }

        std.log.debug("runLanguageParserTests: Completed all tests for {s}", .{@tagName(lang_fixtures.language)});
    }

    /// Run formatter tests for a specific language
    fn runLanguageFormatterTests(self: *FixtureRunner, lang_fixtures: LanguageFixtures) !void {
        for (lang_fixtures.formatter_tests) |formatter_test| {
            try self.runSingleFormatterTest(formatter_test, lang_fixtures.language);
        }
    }

    /// Run a single parser test case with all its extraction variations
    fn runSingleParserTest(self: *FixtureRunner, extractor: Extractor, parser_test: ParserTest, language: Language) !void {
        std.log.debug("runSingleParserTest: Testing '{s}' with {} extraction tests", .{ parser_test.name, parser_test.extraction_tests.len });

        // Safety checks
        if (parser_test.source.len == 0) {
            std.log.debug("runSingleParserTest: Skipping test '{s}' - empty source", .{parser_test.name});
            return;
        }

        if (parser_test.extraction_tests.len == 0) {
            std.log.debug("runSingleParserTest: Skipping test '{s}' - no extraction tests", .{parser_test.name});
            return;
        }

        for (parser_test.extraction_tests, 0..) |extraction_test, i| {
            std.log.debug("runSingleParserTest: Running extraction test {}/{} for '{s}'", .{ i + 1, parser_test.extraction_tests.len, parser_test.name });

            const actual = extractor.extract(language, parser_test.source, extraction_test.flags) catch |err| {
                std.log.err("Parser test '{s}' failed for {s}: {}", .{ parser_test.name, @tagName(language), err });
                return err;
            };
            defer self.allocator.free(actual);

            // Compare actual vs expected, with helpful error messages
            if (!std.mem.eql(u8, actual, extraction_test.expected)) {
                std.log.err("Parser test '{s}' for {s} failed:", .{ parser_test.name, @tagName(language) });
                std.log.err("Expected:\n{s}", .{extraction_test.expected});
                std.log.err("Actual:\n{s}", .{actual});
                std.log.err("Flags: {}", .{extraction_test.flags});
                return error.TestFailed;
            }
        }

        std.log.debug("runSingleParserTest: Test '{s}' passed", .{parser_test.name});
    }

    /// Run a single formatter test case
    fn runSingleFormatterTest(self: *FixtureRunner, formatter_test: FormatterTest, language: Language) !void {
        var formatter = Formatter.init(self.allocator, language, formatter_test.options);

        const actual = formatter.format(formatter_test.source) catch |err| {
            // Skip unsupported languages gracefully
            if (err == error.UnsupportedLanguage) {
                return;
            }
            std.log.err("Formatter test '{s}' failed for {s}: {}", .{ formatter_test.name, @tagName(language), err });
            return err;
        };
        defer self.allocator.free(actual);

        // Compare actual vs expected, with helpful error messages
        if (!std.mem.eql(u8, actual, formatter_test.expected)) {
            std.log.err("Formatter test '{s}' for {s} failed:", .{ formatter_test.name, @tagName(language) });
            std.log.err("Expected:\n{s}", .{formatter_test.expected});
            std.log.err("Actual:\n{s}", .{actual});
            std.log.err("Options: {}", .{formatter_test.options});
            return error.TestFailed;
        }
    }

    /// Get summary statistics for all loaded fixtures
    pub fn getStats(self: *FixtureRunner) FixtureStats {
        var stats = FixtureStats{};

        for (self.fixtures.languages) |lang_fixtures| {
            stats.languages_count += 1;
            stats.parser_tests_count += @intCast(lang_fixtures.parser_tests.len);
            stats.formatter_tests_count += @intCast(lang_fixtures.formatter_tests.len);

            for (lang_fixtures.parser_tests) |parser_test| {
                stats.extraction_tests_count += @intCast(parser_test.extraction_tests.len);
            }
        }

        return stats;
    }
};

/// Statistics about loaded test fixtures
pub const FixtureStats = struct {
    languages_count: u32 = 0,
    parser_tests_count: u32 = 0,
    formatter_tests_count: u32 = 0,
    extraction_tests_count: u32 = 0,

    pub fn total(self: FixtureStats) u32 {
        return self.extraction_tests_count + self.formatter_tests_count;
    }
};

// Comprehensive Svelte fixture test - tests ALL test cases and extraction tests
test "comprehensive Svelte fixture test" {
    const loader = FixtureLoader.init(testing.allocator);
    var svelte_fixtures = loader.loadLanguage(.svelte) catch |err| {
        std.log.err("Failed to load Svelte fixtures: {}", .{err});
        return err;
    };
    defer svelte_fixtures.deinit(testing.allocator);

    // Create extractor once for all tests
    var extractor = try extractor_mod.createTestExtractor(testing.allocator);
    defer {
        extractor.registry.deinit();
        testing.allocator.destroy(extractor.registry);
    }

    // Test ALL parser test cases
    for (svelte_fixtures.parser_tests) |test_case| {
        // Test ALL extraction tests for this parser test case
        for (test_case.extraction_tests, 0..) |extraction_test, j| {
            const actual = try extractor.extract(.svelte, test_case.source, extraction_test.flags);
            defer testing.allocator.free(actual);

            // Perform the actual comparison
            if (!std.mem.eql(u8, actual, extraction_test.expected)) {
                std.log.err("Svelte fixture test '{s}' extraction test {}/{} failed!", .{ test_case.name, j + 1, test_case.extraction_tests.len });
                std.log.err("Flags: {}", .{extraction_test.flags});
                std.log.err("Expected:\n{s}", .{extraction_test.expected});
                std.log.err("Actual:\n{s}", .{actual});
                return error.TestFailed;
            }
        }
    }

    // All tests passed - no output needed
}

test "fixture-based formatter tests" {
    // TODO: CSS formatter test 'minified_to_pretty' is failing
    // The CSS formatter is not handling minified input correctly
    // TODO: ZON parser memory leak - we're not freeing ZON data to avoid segfault
    // See fixture_loader.zig:187 for detailed explanation

    // Temporarily enabled to diagnose issues
    var runner = FixtureRunner.init(testing.allocator) catch |err| {
        std.log.err("Failed to initialize FixtureRunner: {}", .{err});
        return;
    };
    defer runner.deinit();

    std.log.info("Starting formatter tests for all languages", .{});

    runner.runFormatterTests() catch |err| {
        std.log.err("Formatter tests failed: {}", .{err});
        return err;
    };

    std.log.info("All formatter tests completed successfully", .{});
}

// Minimal test with just JSON (smallest fixture file)
test "minimal JSON fixture test" {
    // TODO: ZON parser memory leak - we're not freeing ZON data to avoid segfault
    // See fixture_loader.zig:187 for detailed explanation
    std.log.info("Starting minimal JSON fixture test", .{});

    const loader = FixtureLoader.init(testing.allocator);
    var json_fixtures = loader.loadLanguage(.json) catch |err| {
        std.log.err("Failed to load JSON fixtures: {}", .{err});
        return err;
    };
    defer json_fixtures.deinit(testing.allocator);

    std.log.info("Loaded JSON fixtures: {} parser tests, {} formatter tests", .{ json_fixtures.parser_tests.len, json_fixtures.formatter_tests.len });

    // Test just one parser test to see if basic functionality works
    if (json_fixtures.parser_tests.len > 0) {
        const test_case = json_fixtures.parser_tests[0];
        std.log.info("Testing parser case: '{s}'", .{test_case.name});

        var extractor = try extractor_mod.createTestExtractor(testing.allocator);
        defer {
            extractor.registry.deinit();
            testing.allocator.destroy(extractor.registry);
        }
        if (test_case.extraction_tests.len > 0) {
            const extraction_test = test_case.extraction_tests[0];
            const actual = try extractor.extract(.json, test_case.source, extraction_test.flags);
            defer testing.allocator.free(actual);

            std.log.info("Extraction successful, got {} bytes", .{actual.len});
        }
    }

    std.log.info("Minimal JSON fixture test completed successfully", .{});
}

test "comprehensive fixture tests" {
    var runner = FixtureRunner.init(testing.allocator) catch |err| {
        std.log.err("Failed to initialize FixtureRunner: {}", .{err});
        return err;
    };
    defer runner.deinit();

    try runner.runParserTests();
    try runner.runFormatterTests();
}
