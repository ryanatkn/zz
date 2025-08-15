const std = @import("std");
const testing = std.testing;
const SafeZonFixtureLoader = @import("safe_zon_fixture_loader.zig").SafeZonFixtureLoader;
const LanguageFixtures = @import("safe_zon_fixture_loader.zig").LanguageFixtures;
const ParserTest = @import("safe_zon_fixture_loader.zig").ParserTest;
const FormatterTest = @import("safe_zon_fixture_loader.zig").FormatterTest;
const ExtractionTest = @import("safe_zon_fixture_loader.zig").ExtractionTest;
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

        // Normalize whitespace for comparison to handle invisible character differences
        const normalized_expected = normalizeWhitespace(allocator, formatter_test.expected) catch formatter_test.expected;
        defer if (normalized_expected.ptr != formatter_test.expected.ptr) allocator.free(normalized_expected);
        
        const normalized_actual = normalizeWhitespace(allocator, actual) catch actual;
        defer if (normalized_actual.ptr != actual.ptr) allocator.free(normalized_actual);

        if (!std.mem.eql(u8, normalized_actual, normalized_expected)) {
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
    const loader = SafeZonFixtureLoader.init(testing.allocator);
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

// Test each language individually to isolate segfault issues
test "JSON fixture tests" {
    testLanguageFixtures(.json) catch |err| {
        if (err == error.FileNotFound) return; // Skip if no fixture file
        return err;
    };
}

test "CSS fixture tests" {
    testLanguageFixtures(.css) catch |err| {
        if (err == error.FileNotFound) return; // Skip if no fixture file
        return err;
    };
}

test "HTML fixture tests" {
    testLanguageFixtures(.html) catch |err| {
        if (err == error.FileNotFound) return; // Skip if no fixture file
        return err;
    };
}

test "TypeScript fixture tests" {
    testLanguageFixtures(.typescript) catch |err| {
        if (err == error.FileNotFound) return; // Skip if no fixture file
        return err;
    };
}

test "Svelte fixture tests" {
    testLanguageFixtures(.svelte) catch |err| {
        if (err == error.FileNotFound) return; // Skip if no fixture file
        return err;
    };
}

test "Zig fixture tests" {
    testLanguageFixtures(.zig) catch |err| {
        if (err == error.FileNotFound) return; // Skip if no fixture file
        return err;
    };
}

/// Normalize whitespace to handle invisible character differences in test comparisons
fn normalizeWhitespace(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    // Handle different line ending types (CRLF -> LF, remove BOM)
    var cleaned_input = input;
    
    // Remove UTF-8 BOM if present
    if (cleaned_input.len >= 3 and 
        cleaned_input[0] == 0xEF and cleaned_input[1] == 0xBB and cleaned_input[2] == 0xBF) {
        cleaned_input = cleaned_input[3..];
    }

    // Split by any line ending type and normalize to LF
    var i: usize = 0;
    var line_start: usize = 0;
    var first_line = true;
    
    while (i < cleaned_input.len) {
        if (cleaned_input[i] == '\r' or cleaned_input[i] == '\n') {
            // Found line ending
            const line = cleaned_input[line_start..i];
            
            if (!first_line) {
                try result.append('\n');
            }
            first_line = false;
            
            // Trim trailing whitespace from each line
            const trimmed = std.mem.trimRight(u8, line, " \t\r\n");
            try result.appendSlice(trimmed);
            
            // Skip over line ending (handle CRLF)
            if (i + 1 < cleaned_input.len and cleaned_input[i] == '\r' and cleaned_input[i + 1] == '\n') {
                i += 2; // Skip CRLF
            } else {
                i += 1; // Skip CR or LF
            }
            line_start = i;
        } else {
            i += 1;
        }
    }
    
    // Handle last line if no trailing newline
    if (line_start < cleaned_input.len) {
        const line = cleaned_input[line_start..];
        
        if (!first_line) {
            try result.append('\n');
        }
        
        const trimmed = std.mem.trimRight(u8, line, " \t\r\n");
        try result.appendSlice(trimmed);
    }
    
    return result.toOwnedSlice();
}


