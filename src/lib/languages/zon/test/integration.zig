const std = @import("std");
const testing = std.testing;

// Import ZON modules
const zon_mod = @import("../mod.zig");
const Parser = @import("../parser/mod.zig").Parser;
const Formatter = @import("../format/mod.zig").Formatter;
const Linter = @import("../linter/mod.zig").Linter;
const EnabledRules = @import("../linter/mod.zig").EnabledRules;
const Analyzer = @import("../analyzer/mod.zig").Analyzer;

// =============================================================================
// Integration Tests
// =============================================================================

test "ZON integration - complete pipeline" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const zon_text =
        \\.{
        \\    .name = "test-project",
        \\    .version = "1.0.0",
        \\    .dependencies = .{
        \\        .first = .{ .version = ">=1.0.0" },
        \\        .second = .{ .version = "2.0.0" },
        \\    },
        \\}
    ;

    // Test parsing with streaming parser
    var parser = try Parser.init(allocator, zon_text, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    // AST root should be successfully parsed
    try testing.expect(ast.root != null);
    try testing.expect(ast.root.?.* == .object);

    // Test formatting
    var formatter = Formatter.init(allocator, .{});
    defer formatter.deinit();

    const formatted = try formatter.format(ast);
    defer allocator.free(formatted);
    try testing.expect(formatted.len > 0);

    // Test linting
    var linter = Linter.init(allocator, .{});
    defer linter.deinit();

    const rules = Linter.getDefaultRules();
    const diagnostics = try linter.lint(ast, rules);
    defer {
        for (diagnostics) |diag| {
            allocator.free(diag.message);
        }
        allocator.free(diagnostics);
    }

    // Should pass basic linting
    for (diagnostics) |diagnostic| {
        if (diagnostic.severity == .err) {
            return error.UnexpectedLintError;
        }
    }

    // Test analysis
    var analyzer = Analyzer.init(allocator, .{});
    defer analyzer.deinit();

    const symbols = try analyzer.extractSymbols(ast);
    defer allocator.free(symbols);

    try testing.expect(symbols.len > 0);
}

test "ZON integration - mod.zig convenience functions" {
    // Use the already imported zon_mod

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const zon_text =
        \\.{
        \\    .name = "convenience-test",
        \\    .value = 42,
        \\}
    ;

    // Test parsing convenience function
    var ast = try zon_mod.parse(allocator, zon_text);
    defer ast.deinit();

    // AST root should be successfully parsed
    try testing.expect(ast.root != null);
    try testing.expect(ast.root.?.* == .object);

    // Test formatting convenience function
    const formatted = try zon_mod.formatString(allocator, zon_text);
    defer allocator.free(formatted);

    try testing.expect(formatted.len > 0);

    // Test validation convenience function
    const diagnostics = try zon_mod.validateString(allocator, zon_text);
    defer {
        for (diagnostics) |diag| {
            allocator.free(diag.message);
        }
        allocator.free(diagnostics);
    }

    // Should pass validation
    for (diagnostics) |diagnostic| {
        if (diagnostic.severity == .err) {
            return error.UnexpectedValidationError;
        }
    }
}

test "ZON integration - LanguageSupport interface" {
    // Use the already imported zon_mod
    const Language = @import("../../../core/language.zig").Language;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const zon_text = ".{ .test = true }";

    const zon_lang = try zon_mod.getSupport(allocator);

    // Test interface properties
    try testing.expectEqual(Language.zon, zon_lang.language);

    // Parse ZON for AST-based operations
    var ast = try zon_mod.parse(allocator, zon_text);
    defer ast.deinit();

    // Test formatting through interface (requires AST)
    const format_options = @import("../../interface.zig").FormatOptions{
        .indent_size = 2,
        .indent_style = .space,
        .line_width = 80,
        .preserve_newlines = false,
        .trailing_comma = false,
    };

    const formatted = try zon_lang.formatter.formatFn(allocator, ast, format_options);
    defer allocator.free(formatted);

    try testing.expect(formatted.len > 0);

    // Test linting through interface (uses AST)
    if (zon_lang.linter) |linter| {
        const default_rules = linter.getDefaultRulesFn();
        const diagnostics = try linter.lintFn(allocator, ast, default_rules);
        defer {
            for (diagnostics) |diag| {
                allocator.free(diag.message);
            }
            allocator.free(diagnostics);
        }

        // Should pass linting
        for (diagnostics) |diagnostic| {
            if (diagnostic.severity == .err) {
                return error.UnexpectedLintError;
            }
        }
    }

    // Test analysis through interface
    if (zon_lang.analyzer) |analyzer| {
        const symbols = try analyzer.extractSymbolsFn(allocator, ast);
        defer {
            for (symbols) |symbol| {
                allocator.free(symbol.name);
                if (symbol.signature) |sig| {
                    allocator.free(sig);
                }
                if (symbol.documentation) |doc| {
                    allocator.free(doc);
                }
            }
            allocator.free(symbols);
        }

        try testing.expect(symbols.len > 0);
    }
}
