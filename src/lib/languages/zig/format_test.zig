const std = @import("std");
const ts = @import("tree-sitter");
const LineBuilder = @import("../../parsing/formatter.zig").LineBuilder;
const FormatterOptions = @import("../../parsing/formatter.zig").FormatterOptions;
const NodeUtils = @import("../../language/node_utils.zig").NodeUtils;

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
        var i: usize = 0;
        var in_string = false;
        var escape_next = false;
        var in_comment = false;
        var brace_depth: u32 = 0;
        var in_test_body = false;

        while (i < test_text.len) {
            const c = test_text[i];

            if (escape_next) {
                try builder.append(&[_]u8{c});
                escape_next = false;
                i += 1;
                continue;
            }

            if (c == '\\' and in_string) {
                escape_next = true;
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            if (c == '"' and !in_comment) {
                in_string = !in_string;
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            if (!in_string and i + 1 < test_text.len and test_text[i] == '/' and test_text[i + 1] == '/') {
                in_comment = true;
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            if (in_comment and c == '\n') {
                in_comment = false;
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            if (in_string or in_comment) {
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            if (c == '{') {
                brace_depth += 1;
                if (brace_depth == 1) {
                    in_test_body = true;
                    try builder.append(&[_]u8{c});
                    try builder.newline();
                    builder.indent();
                } else {
                    try builder.append(&[_]u8{c});
                }
                i += 1;
                continue;
            }

            if (c == '}') {
                if (brace_depth == 1 and in_test_body) {
                    builder.dedent();
                    try builder.appendIndent();
                    try builder.append(&[_]u8{c});
                    in_test_body = false;
                } else {
                    try builder.append(&[_]u8{c});
                }
                if (brace_depth > 0) {
                    brace_depth -= 1;
                }
                i += 1;
                continue;
            }

            if (c == '\n' and in_test_body) {
                try builder.newline();
                try builder.appendIndent();
                i += 1;
                continue;
            }

            if (c == ' ') {
                // Only add space if we haven't just added one
                if (builder.buffer.items.len > 0 and
                    builder.buffer.items[builder.buffer.items.len - 1] != ' ') {
                    try builder.append(" ");
                }
                i += 1;
                continue;
            }

            try builder.append(&[_]u8{c});
            i += 1;
        }
    }

    /// Check if text represents a test declaration
    pub fn isTestDecl(text: []const u8) bool {
        return std.mem.startsWith(u8, text, "test ") or 
               std.mem.indexOf(u8, text, " test ") != null;
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