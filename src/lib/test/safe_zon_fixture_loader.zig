const std = @import("std");
const Language = @import("../language/detection.zig").Language;
const ExtractionFlags = @import("../language/flags.zig").ExtractionFlags;
const FormatterOptions = @import("../parsing/formatter.zig").FormatterOptions;
const IndentStyle = @import("../parsing/formatter.zig").IndentStyle;
const zon = @import("../languages/zon/mod.zig");

/// A single test case for parser extraction
pub const ExtractionTest = struct {
    flags: ExtractionFlags,
    expected: []const u8,
};

/// A complete parser test with multiple extraction modes
pub const ParserTest = struct {
    name: []const u8,
    source: []const u8,
    extraction_tests: []const ExtractionTest,
};

/// A single formatter test case
pub const FormatterTest = struct {
    name: []const u8,
    source: []const u8,
    expected: []const u8,
    options: FormatterOptions,
};

/// Language-specific test fixtures
pub const LanguageFixtures = struct {
    language: Language,
    parser_tests: []const ParserTest,
    formatter_tests: []const FormatterTest,

    pub fn deinit(self: *LanguageFixtures, allocator: std.mem.Allocator) void {
        // Free all nested allocations
        for (self.parser_tests) |test_case| {
            // Free strings in each parser test
            allocator.free(test_case.name);
            allocator.free(test_case.source);

            // Free strings in each extraction test
            for (test_case.extraction_tests) |extraction_test| {
                allocator.free(extraction_test.expected);
            }
            allocator.free(test_case.extraction_tests);
        }
        allocator.free(self.parser_tests);

        // Free all strings in formatter tests
        for (self.formatter_tests) |test_case| {
            allocator.free(test_case.name);
            allocator.free(test_case.source);
            allocator.free(test_case.expected);
        }
        allocator.free(self.formatter_tests);
    }
};

/// Raw ZON structure for parsing test fixture files
const TestFixtureData = struct {
    language: []const u8,
    parser_tests: []const ParserTestData,
    formatter_tests: []const FormatterTestData = &[_]FormatterTestData{}, // Default empty
};

const ParserTestData = struct {
    name: []const u8,
    source: []const u8,
    extraction_tests: []const ExtractionTestData,
};

const ExtractionTestData = struct {
    flags: ExtractionFlagsData,
    expected: []const u8,
};

const ExtractionFlagsData = struct {
    full: bool = false,
    signatures: bool = false,
    types: bool = false,
    docs: bool = false,
    imports: bool = false,
    errors: bool = false,
    tests: bool = false,
    structure: bool = false,
};

const FormatterTestData = struct {
    name: []const u8,
    source: []const u8,
    expected: []const u8,
    options: FormatterOptionsData,
};

const FormatterOptionsData = struct {
    indent_size: u8 = 4,
    indent_style: IndentStyle = .space,
    line_width: u16 = 100,
    trailing_comma: bool = false,
    sort_keys: bool = false,
};

/// Safe ZON fixture loader that avoids segfault by using arena allocator
pub const SafeZonFixtureLoader = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) SafeZonFixtureLoader {
        return SafeZonFixtureLoader{ .allocator = allocator };
    }

    /// Load test fixtures for a specific language from ZON file
    pub fn loadLanguage(self: SafeZonFixtureLoader, language: Language) !LanguageFixtures {
        const language_str = @tagName(language);
        const filename = try std.fmt.allocPrint(self.allocator, "src/lib/test/fixtures/{s}.test.zon", .{language_str});
        defer self.allocator.free(filename);

        std.log.debug("loadLanguage: Loading {s} fixtures from {s}", .{ language_str, filename });

        // Read the fixture file
        const file_content = std.fs.cwd().readFileAlloc(self.allocator, filename, 1024 * 1024) catch |err| {
            if (err == error.FileNotFound) {
                std.log.debug("loadLanguage: File not found: {s}", .{filename});
                return error.FileNotFound;
            }
            return err;
        };
        defer self.allocator.free(file_content);

        return self.parseZonFixture(file_content, language);
    }

    /// Parse a ZON fixture file into structured test data
    /// Uses our ZON parser instead of std.zon to avoid segfaults
    fn parseZonFixture(self: SafeZonFixtureLoader, content: []const u8, language: Language) !LanguageFixtures {
        std.log.debug("parseZonFixture: Starting for language {}", .{language});

        // Create arena for ZON parsing - will clean up automatically
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        // Parse ZON content with our parser
        const data = try zon.parseFromSlice(TestFixtureData, arena.allocator(), content);
        // Note: Our parser handles cleanup internally

        std.log.debug("parseZonFixture: Successfully parsed ZON, copying data...", .{});

        // Convert parsed data to our internal format using main allocator
        var parser_tests = std.ArrayList(ParserTest).init(self.allocator);
        defer parser_tests.deinit();

        for (data.parser_tests) |test_data| {
            var extraction_tests = std.ArrayList(ExtractionTest).init(self.allocator);
            defer extraction_tests.deinit();

            for (test_data.extraction_tests) |extraction_data| {
                try extraction_tests.append(ExtractionTest{
                    .flags = parseExtractionFlags(extraction_data.flags),
                    .expected = try self.allocator.dupe(u8, extraction_data.expected),
                });
            }

            try parser_tests.append(ParserTest{
                .name = try self.allocator.dupe(u8, test_data.name),
                .source = try self.allocator.dupe(u8, test_data.source),
                .extraction_tests = try extraction_tests.toOwnedSlice(),
            });
        }

        var formatter_tests = std.ArrayList(FormatterTest).init(self.allocator);
        defer formatter_tests.deinit();

        for (data.formatter_tests) |test_data| {
            try formatter_tests.append(FormatterTest{
                .name = try self.allocator.dupe(u8, test_data.name),
                .source = try self.allocator.dupe(u8, test_data.source),
                .expected = try self.allocator.dupe(u8, test_data.expected),
                .options = parseFormatterOptions(test_data.options),
            });
        }

        return LanguageFixtures{
            .language = language,
            .parser_tests = try parser_tests.toOwnedSlice(),
            .formatter_tests = try formatter_tests.toOwnedSlice(),
        };
    }
};

/// Convert ZON extraction flags to internal representation
fn parseExtractionFlags(flags_data: ExtractionFlagsData) ExtractionFlags {
    return ExtractionFlags{
        .full = flags_data.full,
        .signatures = flags_data.signatures,
        .types = flags_data.types,
        .docs = flags_data.docs,
        .imports = flags_data.imports,
        .errors = flags_data.errors,
        .tests = flags_data.tests,
        .structure = flags_data.structure,
    };
}

/// Convert ZON formatter options to internal representation
fn parseFormatterOptions(options_data: FormatterOptionsData) FormatterOptions {
    return FormatterOptions{
        .indent_size = options_data.indent_size,
        .indent_style = options_data.indent_style,
        .line_width = @as(u32, options_data.line_width), // Convert u16 to u32
        .preserve_newlines = true, // Default value
        .trailing_comma = options_data.trailing_comma,
        .sort_keys = options_data.sort_keys,
        .quote_style = .preserve, // Default value
        .use_ast = true, // Default value for tests
    };
}

test "SafeZonFixtureLoader basic parsing" {
    const testing = std.testing;

    const test_zon =
        \\.{
        \\    .language = "json",
        \\    .parser_tests = .{
        \\        .{
        \\            .name = "simple_test",
        \\            .source = "{ \"test\": true }",
        \\            .extraction_tests = .{
        \\                .{
        \\                    .flags = .{ .full = true },
        \\                    .expected = "{ \"test\": true }",
        \\                },
        \\            },
        \\        },
        \\    },
        \\    .formatter_tests = .{
        \\        .{
        \\            .name = "basic_format",
        \\            .source = "{\"a\":1}",
        \\            .expected = "{\n  \"a\": 1\n}",
        \\            .options = .{
        \\                .indent_size = 2,
        \\                .indent_style = .space,
        \\            },
        \\        },
        \\    },
        \\}
    ;

    const loader = SafeZonFixtureLoader.init(testing.allocator);
    var fixtures = try loader.parseZonFixture(test_zon, .json);
    defer fixtures.deinit(testing.allocator);

    try testing.expectEqual(Language.json, fixtures.language);
    try testing.expectEqual(@as(usize, 1), fixtures.parser_tests.len);
    try testing.expectEqual(@as(usize, 1), fixtures.formatter_tests.len);

    const parser_test = fixtures.parser_tests[0];
    try testing.expectEqualStrings("simple_test", parser_test.name);
    try testing.expectEqualStrings("{ \"test\": true }", parser_test.source);
    try testing.expectEqual(@as(usize, 1), parser_test.extraction_tests.len);

    const extraction_test = parser_test.extraction_tests[0];
    try testing.expect(extraction_test.flags.full);
    try testing.expectEqualStrings("{ \"test\": true }", extraction_test.expected);

    const formatter_test = fixtures.formatter_tests[0];
    try testing.expectEqualStrings("basic_format", formatter_test.name);
    try testing.expectEqualStrings("{\"a\":1}", formatter_test.source);
    try testing.expectEqualStrings("{\n  \"a\": 1\n}", formatter_test.expected);
    try testing.expectEqual(@as(u8, 2), formatter_test.options.indent_size);
    try testing.expectEqual(IndentStyle.space, formatter_test.options.indent_style);
}

test "parseExtractionFlags" {
    const testing = std.testing;

    const flags_data = ExtractionFlagsData{
        .full = true,
        .signatures = true,
        .types = false,
    };

    const flags = parseExtractionFlags(flags_data);
    try testing.expect(flags.full);
    try testing.expect(flags.signatures);
    try testing.expect(!flags.types);
    try testing.expect(!flags.docs);
}

test "parseFormatterOptions" {
    const testing = std.testing;

    const options_data = FormatterOptionsData{
        .indent_size = 2,
        .indent_style = .tab,
        .line_width = 120,
        .trailing_comma = true,
    };

    const options = parseFormatterOptions(options_data);
    try testing.expectEqual(@as(u8, 2), options.indent_size);
    try testing.expectEqual(IndentStyle.tab, options.indent_style);
    try testing.expectEqual(@as(u32, 120), options.line_width); // Changed to u32
    try testing.expect(options.trailing_comma);
}
