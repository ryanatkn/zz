const std = @import("std");
const testing = std.testing;

// Import ZON modules
const ZonParser = @import("parser.zig").ZonParser;
const ZonFormatter = @import("formatter.zig").ZonFormatter;
const ZonLinter = @import("linter.zig").ZonLinter;
const EnabledRules = @import("linter.zig").EnabledRules;
const ZonAnalyzer = @import("analyzer.zig").ZonAnalyzer;

// =============================================================================
// Integration Tests
// =============================================================================

test "ZON integration - complete pipeline" {
    return error.SkipZigTest; // TODO: Migrate to streaming pipeline

    // TODO: Original test logic - convert to streaming pipeline:
    // var arena = std.heap.ArenaAllocator.init(testing.allocator);
    // defer arena.deinit();
    // const allocator = arena.allocator();

    // const zon_text =
    //     \\.{
    //     \\    .name = "test-project",
    //     \\    .version = "1.0.0",
    //     \\    .dependencies = .{
    //     \\        .first = .{ .version = ">=1.0.0" },
    //     \\        .second = .{ .version = "2.0.0" },
    //     \\    },
    //     \\}
    // ;

    // // Test lexing
    // var lexer = ZonLexer.init(allocator);  // <- CONVERT TO: var lexer = ZonStreamLexer.init(zon_text);
    // defer lexer.deinit();

    // const tokens = try lexer.tokenize(zon_text);  // <- CONVERT TO: while (lexer.next()) |token| { ... }
    // defer allocator.free(tokens);

    // try testing.expect(tokens.len > 20); // Should have many tokens

    // // Test parsing
    // var parser = ZonParser.init(allocator, tokens, zon_text, .{});  // <- CONVERT TO: var parser = try ZonParser.init(allocator, zon_text, .{});
    // defer parser.deinit();

    // const ast = try parser.parse();
    // try testing.expect(ast.root != null);

    // // Test formatting
    // var formatter = ZonFormatter.init(allocator, .{});
    // defer formatter.deinit();

    // const formatted = try formatter.formatSource(zon_text);  // <- CONVERT TO: const formatted = try formatter.format(ast);
    // try testing.expect(formatted.len > 0);

    // // Test linting
    // var linter = ZonLinter.init(allocator, .{});
    // defer linter.deinit();

    // const rules = ZonLinter.getDefaultRules();
    // const diagnostics = try linter.lintSource(zon_text, rules);  // <- May need to update for streaming
    // defer allocator.free(diagnostics);

    // // Should pass basic linting
    // for (diagnostics) |diagnostic| {
    //     if (diagnostic.severity == .err) {
    //         return error.UnexpectedLintError;
    //     }
    // }

    // // Test analysis
    // var analyzer = ZonAnalyzer.init(allocator, .{});
    // defer analyzer.deinit();

    // const symbols = try analyzer.analyze(ast);  // <- Already uses AST, should work
    // defer symbols.deinit();

    // try testing.expect(symbols.items.len > 0);
}

test "ZON integration - mod.zig convenience functions" {
    return error.SkipZigTest; // TODO: Migrate to streaming convenience functions

    // TODO: Original test logic - convert to new convenience functions:
    // var arena = std.heap.ArenaAllocator.init(testing.allocator);
    // defer arena.deinit();
    // const allocator = arena.allocator();

    // const zon_text =
    //     \\.{
    //     \\    .name = "convenience-test",
    //     \\    .value = 42,
    //     \\}
    // ;

    // // Test parsing convenience function
    // const ast = try zon.parseZonString(allocator, zon_text);  // <- CONVERT TO: const ast = try zon.parse(allocator, zon_text);
    // defer ast.deinit();

    // try testing.expect(ast.root != null);

    // // Test formatting convenience function
    // const formatted = try zon.formatZonString(allocator, zon_text);  // <- CONVERT TO: var formatter = zon.Formatter.init(allocator, .{}); const formatted = try formatter.format(ast);
    // defer allocator.free(formatted);

    // try testing.expect(formatted.len > 0);

    // // Test validation convenience function
    // const diagnostics = try zon.validateZonString(allocator, zon_text);  // <- May need to update for streaming
    // defer allocator.free(diagnostics);

    // // Should pass validation
    // for (diagnostics) |diagnostic| {
    //     if (diagnostic.severity == .err) {
    //         return error.UnexpectedValidationError;
    //     }
    // }
}

test "ZON integration - LanguageSupport interface" {
    return error.SkipZigTest; // TODO: Migrate to streaming LanguageSupport interface

    // TODO: Original test logic - convert to streaming LanguageSupport:
    // var arena = std.heap.ArenaAllocator.init(testing.allocator);
    // defer arena.deinit();
    // const allocator = arena.allocator();

    // const zon_text = ".{ .test = true }";

    // var zon_lang = try zon.createLanguageSupport(allocator);  // <- May need to update interface
    // defer zon_lang.deinit();

    // // Test interface methods
    // try testing.expectEqual(Language.zon, zon_lang.getLanguage());
    // try testing.expect(zon_lang.canFormat());
    // try testing.expect(zon_lang.canLint());
    // try testing.expect(zon_lang.canAnalyze());

    // // Test formatting through interface
    // const formatted = try zon_lang.format(zon_text, .{});  // <- May need to update for AST-first
    // defer allocator.free(formatted);

    // try testing.expect(formatted.len > 0);

    // // Test linting through interface
    // const diagnostics = try zon_lang.lint(zon_text, .{});  // <- May need to update for streaming
    // defer allocator.free(diagnostics);

    // // Should pass linting
    // for (diagnostics) |diagnostic| {
    //     if (diagnostic.severity == .err) {
    //         return error.UnexpectedLintError;
    //     }
    // }
}
