/// JSON Language Module - Self-contained JSON support
///
/// SIMPLIFIED: Direct streaming architecture, no old Token infrastructure
/// Each language owns its implementation completely
const std = @import("std");

// Import JSON-specific implementations - all self-contained
const JsonParser = @import("parser.zig").JsonParser;
const JsonFormatter = @import("formatter.zig").JsonFormatter;
const linter_mod = @import("linter.zig");
const JsonLinter = linter_mod.JsonLinter;
const Diagnostic = linter_mod.Diagnostic;
const JsonRuleType = linter_mod.JsonRuleType;
const EnabledRules = linter_mod.EnabledRules;
const JsonAnalyzer = @import("analyzer.zig").JsonAnalyzer;

// Import JSON AST
const json_ast = @import("ast.zig");
pub const AST = json_ast.AST;
pub const Node = json_ast.Node;
pub const NodeKind = json_ast.NodeKind;

// Direct exports
pub const Parser = JsonParser;
pub const Formatter = JsonFormatter;
pub const Linter = JsonLinter;
pub const RuleType = JsonRuleType;
pub const Analyzer = JsonAnalyzer;
pub const AnalyzerOptions = JsonAnalyzer.AnalyzerOptions;
pub const ParserOptions = JsonParser.ParserOptions;

// Streaming lexer exports (the new way)
pub const StreamLexer = @import("stream_lexer.zig").JsonStreamLexer;
pub const StreamToken = @import("stream_token.zig").JsonToken;
pub const StreamTokenKind = @import("stream_token.zig").JsonTokenKind;

/// Parse JSON source into AST using streaming parser (convenience function)
pub fn parse(allocator: std.mem.Allocator, source: []const u8) !AST {
    var parser = try JsonParser.init(allocator, source, .{});
    defer parser.deinit();
    return parser.parse();
}

/// Parse JSON source into AST (alias for backward compatibility)
pub const parseJson = parse;

/// Validate JSON string and return diagnostics (convenience function)
pub fn validateJson(allocator: std.mem.Allocator, json_content: []const u8) ![]Diagnostic {
    var linter = JsonLinter.init(allocator, .{});
    defer linter.deinit();
    const rules = JsonLinter.getDefaultRules();
    return linter.lintSource(json_content, rules);
}

/// Format JSON string directly (convenience function)
/// This is a convenience function for cases where you have raw JSON text
/// and need to format it without first parsing to AST (e.g., CLI tools).
/// For better performance, prefer parse() → format(ast) when you need both parsing and formatting.
pub fn formatJsonString(allocator: std.mem.Allocator, json_content: []const u8) ![]u8 {
    // Use formatter directly with source for this convenience case
    const json_options = JsonFormatter.JsonFormatOptions{
        .indent_size = 4,
        .indent_style = .space,
        .line_width = 100,
        .preserve_newlines = false,
        .force_compact = false,
        .trailing_comma = false,
    };

    var formatter = JsonFormatter.init(allocator, json_options);
    defer formatter.deinit();
    const formatted = try formatter.formatSource(json_content);
    return try allocator.dupe(u8, formatted);
}

// Test support
test "JSON module tests" {
    _ = @import("test.zig");
}
