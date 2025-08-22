const std = @import("std");
const testing = std.testing;

// Import ZON modules
const ZonLexer = @import("lexer.zig").ZonLexer;
const ZonParser = @import("parser.zig").ZonParser;
const ZonFormatter = @import("formatter.zig").ZonFormatter;
const ZonLinter = @import("linter.zig").ZonLinter;
const EnabledRules = @import("linter.zig").EnabledRules;
const ZonAnalyzer = @import("analyzer.zig").ZonAnalyzer;
const zon_mod = @import("mod.zig");

// Import types
const interface_types = @import("../interface.zig");
const FormatOptions = interface_types.FormatOptions;
const Rule = interface_types.Rule;

// =============================================================================
// Integration Tests
// =============================================================================

test "ZON integration - complete pipeline" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const original_zon =
        \\.{
        \\    .name = "test-package",
        \\    .version = "1.0.0",
        \\    .dependencies = .{
        \\        .utils = .{
        \\            .url = "https://example.com/utils",
        \\            .hash = "1234567890abcdef1234567890abcdef12345678",
        \\        },
        \\    },
        \\    .paths = .{ "src", "test" },
        \\}
    ;

    // Test lexing
    var lexer = ZonLexer.init(allocator);
    defer lexer.deinit();

    const tokens = try lexer.tokenize(original_zon);
    defer allocator.free(tokens);

    try testing.expect(tokens.len > 0);

    // Test parsing
    var parser = ZonParser.init(allocator, tokens, original_zon, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    try testing.expect(ast.root != null);

    // Test formatting
    var formatter = ZonFormatter.init(allocator, .{});
    defer formatter.deinit();

    const formatted = try formatter.format(ast);
    defer allocator.free(formatted);

    try testing.expect(formatted.len > 0);

    // Test linting with default rules
    const enabled_rules = ZonLinter.getDefaultRules();

    var linter = ZonLinter.init(allocator, .{});
    defer linter.deinit();

    const diagnostics = try linter.lint(ast, enabled_rules);
    defer {
        for (diagnostics) |diag| {
            allocator.free(diag.message);
        }
        allocator.free(diagnostics);
    }

    // Valid ZON should have no serious errors
    for (diagnostics) |diag| {
        try testing.expect(diag.severity != .err);
    }

    // Test analysis
    var analyzer = ZonAnalyzer.init(allocator, .{});

    const symbols = try analyzer.extractSymbols(ast);
    defer {
        for (symbols) |symbol| {
            symbol.deinit(allocator);
        }
        allocator.free(symbols);
    }

    try testing.expect(symbols.len > 0);
}

test "ZON integration - mod.zig convenience functions" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = ".{ .name = \"test\", .version = \"1.0.0\" }";

    // Test parseZon function if available
    // var ast = try zon_mod.parseZon(allocator, input);
    // defer ast.deinit();

    // Test formatZonString function if available
    // const formatted = try zon_mod.formatZonString(allocator, input);
    // defer allocator.free(formatted);

    // Test validateZon function if available
    // const diagnostics = try zon_mod.validateZon(allocator, input);
    // defer {
    //     for (diagnostics) |diag| {
    //         allocator.free(diag.message);
    //     }
    //     allocator.free(diagnostics);
    // }

    _ = zon_mod;
    _ = input;
    _ = allocator;
    // Placeholder until convenience functions are implemented
}

test "ZON integration - LanguageSupport interface" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Test getSupport function if available
    // const support = try zon_mod.getSupport(allocator);

    // Test complete workflow through interface
    const input = ".{ .test = \"value\" }";

    // Tokenize
    // const tokens = try support.lexer.tokenize(allocator, input);
    // defer allocator.free(tokens);

    // Parse
    // var ast = try support.parser.parse(allocator, tokens);
    // defer ast.deinit();

    // Format
    // const options = FormatOptions{
    //     .indent_size = 4,
    //     .line_width = 100,
    // };
    // const formatted = try support.formatter.format(allocator, ast, options);
    // defer allocator.free(formatted);

    // Lint
    // if (support.linter) |linter| {
    //     const enabled_rules = &[_]Rule{
    //         Rule{ .name = "test-rule", .description = "", .severity = .warning, .enabled = true },
    //     };
    //     const diagnostics = try linter.lint(allocator, ast, enabled_rules);
    //     defer {
    //         for (diagnostics) |diag| {
    //             allocator.free(diag.message);
    //         }
    //         allocator.free(diagnostics);
    //     }
    // }

    // Analyze
    // if (support.analyzer) |analyzer| {
    //     const symbols = try analyzer.extractSymbols(ast);
    //     defer {
    //         for (symbols) |symbol| {
    //             allocator.free(symbol.name);
    //             if (symbol.signature) |sig| {
    //                 allocator.free(sig);
    //             }
    //         }
    //         allocator.free(symbols);
    //     }
    // }

    _ = input;
    _ = allocator;
    // Placeholder until interface is implemented
}
