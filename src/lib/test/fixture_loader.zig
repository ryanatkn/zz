const std = @import("std");
const Language = @import("../ast.zig").Language;
const ExtractionFlags = @import("../ast.zig").ExtractionFlags;
const FormatterOptions = @import("../formatter.zig").FormatterOptions;
const IndentStyle = @import("../formatter.zig").IndentStyle;
const ZonParser = @import("../zon_parser.zig").ZonParser;

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

/// Complete test fixture collection
pub const TestFixtures = struct {
    languages: []LanguageFixtures,
    allocator: std.mem.Allocator,
    
    pub fn deinit(self: *TestFixtures) void {
        for (self.languages) |*lang_fixtures| {
            lang_fixtures.deinit(self.allocator);
        }
        self.allocator.free(self.languages);
    }
};

/// Fixture loader for ZON test files
pub const FixtureLoader = struct {
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) FixtureLoader {
        return FixtureLoader{ .allocator = allocator };
    }
    
    /// Load all language test fixtures
    pub fn loadAll(self: FixtureLoader) !TestFixtures {
        const languages = [_]Language{ .css, .html, .json, .typescript, .svelte, .zig };
        var fixtures_list = std.ArrayList(LanguageFixtures).init(self.allocator);
        defer fixtures_list.deinit();
        
        for (languages) |lang| {
            if (self.loadLanguage(lang)) |lang_fixtures| {
                try fixtures_list.append(lang_fixtures);
            } else |err| {
                // Skip languages that don't have fixture files yet
                if (err == error.FileNotFound) continue;
                return err;
            }
        }
        
        return TestFixtures{
            .languages = try fixtures_list.toOwnedSlice(),
            .allocator = self.allocator,
        };
    }
    
    /// Load fixtures for a specific language
    pub fn loadLanguage(self: FixtureLoader, language: Language) !LanguageFixtures {
        const filename = switch (language) {
            .css => "css.test.zon",
            .html => "html.test.zon",
            .json => "json.test.zon",
            .typescript => "typescript.test.zon",
            .svelte => "svelte.test.zon",
            .zig => "zig.test.zon",
            else => return error.UnsupportedLanguage,
        };
        
        var path_buf: [256]u8 = undefined;
        const fixture_path = try std.fmt.bufPrint(&path_buf, "src/lib/test/fixtures/{s}", .{filename});
        
        const file_content = try std.fs.cwd().readFileAlloc(self.allocator, fixture_path, 1024 * 1024);
        defer self.allocator.free(file_content);
        
        return self.parseZonFixture(file_content, language);
    }
    
    /// Parse a ZON fixture file into structured test data
    fn parseZonFixture(self: FixtureLoader, content: []const u8, language: Language) !LanguageFixtures {
        // Use shared ZON parser utility
        const data = try ZonParser.parseFromSlice(TestFixtureData, self.allocator, content);
        defer ZonParser.free(self.allocator, data);
        
        // Convert parsed data to our internal format
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

// ZON parsing structures (temporary for parsing)
const TestFixtureData = struct {
    language: []const u8,
    parser_tests: []const ParserTestData,
    formatter_tests: []const FormatterTestData,
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
    signatures: bool = false,
    types: bool = false,
    docs: bool = false,
    structure: bool = false,
    imports: bool = false,
    errors: bool = false,
    tests: bool = false,
    full: bool = false,
};

const FormatterTestData = struct {
    name: []const u8,
    source: []const u8,
    expected: []const u8,
    options: FormatterOptionsData = .{},
};

const FormatterOptionsData = struct {
    indent_size: u32 = 4,
    indent_style: []const u8 = "space",
    line_width: u32 = 100,
    trailing_comma: bool = false,
    sort_keys: bool = false,
};

/// Convert ZON flags to ExtractionFlags
fn parseExtractionFlags(data: ExtractionFlagsData) ExtractionFlags {
    return ExtractionFlags{
        .signatures = data.signatures,
        .types = data.types,
        .docs = data.docs,
        .structure = data.structure,
        .imports = data.imports,
        .errors = data.errors,
        .tests = data.tests,
        .full = data.full,
    };
}

/// Convert ZON options to FormatterOptions
fn parseFormatterOptions(data: FormatterOptionsData) FormatterOptions {
    const indent_style: IndentStyle = if (std.mem.eql(u8, data.indent_style, "tab"))
        .tab
    else
        .space;
    
    return FormatterOptions{
        .indent_size = @intCast(data.indent_size),
        .indent_style = indent_style,
        .line_width = data.line_width,
        .trailing_comma = data.trailing_comma,
        .sort_keys = data.sort_keys,
    };
}

test "fixture loader initialization" {
    const testing = std.testing;
    const loader = FixtureLoader.init(testing.allocator);
    
    // Basic initialization test
    try testing.expect(loader.allocator.ptr == testing.allocator.ptr);
}