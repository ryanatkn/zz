const std = @import("std");
const ts = @import("tree-sitter");
const LineBuilder = @import("../../parsing/formatter.zig").LineBuilder;
const FormatterOptions = @import("../../parsing/formatter.zig").FormatterOptions;
const NodeUtils = @import("../../language/node_utils.zig").NodeUtils;
const ZigFormattingHelpers = @import("formatting_helpers.zig").ZigFormattingHelpers;

pub const FormatTest = struct {
    /// Format Zig test declaration
    pub fn formatTest(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) !void {
        _ = depth;
        _ = options;
        const test_text = NodeUtils.getNodeText(node, source);
        try formatTestWithSpacing(test_text, builder);
    }

    /// Format test declaration with proper spacing and indentation
    pub fn formatTestWithSpacing(test_text: []const u8, builder: *LineBuilder) !void {
        // Find the test signature and body parts
        if (std.mem.indexOf(u8, test_text, "{")) |brace_pos| {
            const signature = std.mem.trim(u8, test_text[0..brace_pos], " \t");
            const body_start = brace_pos + 1;
            const body_end = std.mem.lastIndexOf(u8, test_text, "}") orelse test_text.len;
            const body = std.mem.trim(u8, test_text[body_start..body_end], " \t\n\r");
            
            // Use consolidated block formatting helper
            try ZigFormattingHelpers.formatBlockWithBraces(builder, signature, body, true);
        } else {
            // Test declaration without body - format signature with consolidated helper
            try ZigFormattingHelpers.formatWithZigSpacing(test_text, builder);
        }
    }

    /// Check if text represents a test declaration
    pub fn isTestDecl(text: []const u8) bool {
        // Use consolidated helper for declaration classification
        return ZigFormattingHelpers.classifyDeclaration(text) == .test_decl;
    }

    /// Extract test name from test declaration
    pub fn extractTestName(text: []const u8) ?[]const u8 {
        // Look for test "name" or test name
        if (std.mem.indexOf(u8, text, "test ")) |test_pos| {
            const after_test = text[test_pos + "test ".len..];
            
            // Handle quoted test names: test "my test"
            if (std.mem.startsWith(u8, after_test, "\"")) {
                if (std.mem.indexOfPos(u8, after_test, 1, "\"")) |end_quote| {
                    return after_test[1..end_quote];
                }
            } else {
                // Handle unquoted test names: test myTest
                var tokens = std.mem.splitSequence(u8, after_test, " ");
                if (tokens.next()) |name| {
                    return std.mem.trim(u8, name, " \t{");
                }
            }
        }
        return null;
    }

    /// Check if test is a named test (has string name)
    pub fn isNamedTest(text: []const u8) bool {
        if (std.mem.indexOf(u8, text, "test ")) |test_pos| {
            const after_test = text[test_pos + "test ".len..];
            return std.mem.startsWith(u8, std.mem.trimLeft(u8, after_test, " \t"), "\"");
        }
        return false;
    }

    /// Check if test is an identifier test
    pub fn isIdentifierTest(text: []const u8) bool {
        return isTestDecl(text) and !isNamedTest(text);
    }

    /// Format test body with proper indentation
    pub fn formatTestBody(body: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
        _ = options;
        
        var lines = std.mem.splitSequence(u8, body, "\n");
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t");
            if (trimmed.len > 0) {
                try builder.appendIndent();
                try builder.append(trimmed);
                try builder.newline();
            }
        }
    }

    /// Check if text contains test assertions
    pub fn hasAssertions(text: []const u8) bool {
        const patterns = [_][]const u8{ 
            "try std.testing.expect",
            "try expect",
            "std.testing.expectEqual",
            "expectEqual",
            "std.testing.expectError",
            "expectError"
        };
        
        for (patterns) |pattern| {
            if (std.mem.indexOf(u8, text, pattern) != null) {
                return true;
            }
        }
        return false;
    }
};