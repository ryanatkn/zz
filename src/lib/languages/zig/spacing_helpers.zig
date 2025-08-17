const std = @import("std");
const LineBuilder = @import("../../parsing/formatter.zig").LineBuilder;

/// Zig-specific operator and punctuation spacing rules
/// Separated from formatting_helpers.zig for focused functionality
pub const ZigSpacingHelpers = struct {

    /// Format colon spacing according to Zig style guide
    /// Type annotations: `name: Type` not `name : Type` or `name:Type`
    pub fn formatColonSpacing(text: []const u8, builder: *LineBuilder) !void {
        var i: usize = 0;
        var in_string = false;
        var string_char: u8 = 0;

        while (i < text.len) {
            const c = text[i];

            // Track string boundaries
            if (!in_string and (c == '"' or c == '\'')) {
                in_string = true;
                string_char = c;
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            if (in_string and c == string_char) {
                in_string = false;
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            if (in_string) {
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            // Handle colon spacing
            if (c == ':') {
                // Remove any trailing space before colon
                while (builder.buffer.items.len > 0 and 
                       builder.buffer.items[builder.buffer.items.len - 1] == ' ') {
                    _ = builder.buffer.pop();
                }
                try builder.append(":");
                i += 1;
                
                // Ensure space after colon if next char isn't space
                if (i < text.len and text[i] != ' ') {
                    try builder.append(" ");
                }
                continue;
            }

            try builder.append(&[_]u8{c});
            i += 1;
        }
    }

    /// Format equals operator spacing
    /// Assignment: `a = b` not `a=b` or `a =b`
    /// Comparison: `a == b` not `a==b`
    pub fn formatEqualsSpacing(text: []const u8, builder: *LineBuilder) !void {
        var i: usize = 0;
        var in_string = false;
        var string_char: u8 = 0;

        while (i < text.len) {
            const c = text[i];

            // Track string boundaries
            if (!in_string and (c == '"' or c == '\'')) {
                in_string = true;
                string_char = c;
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            if (in_string and c == string_char) {
                in_string = false;
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            if (in_string) {
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            // Handle equals spacing
            if (c == '=') {
                // Check for == operator
                if (i + 1 < text.len and text[i + 1] == '=') {
                    // Ensure space before ==
                    if (builder.buffer.items.len > 0 and 
                        builder.buffer.items[builder.buffer.items.len - 1] != ' ') {
                        try builder.append(" ");
                    }
                    try builder.append("==");
                    i += 2;
                    
                    // Ensure space after == if next char isn't space
                    if (i < text.len and text[i] != ' ') {
                        try builder.append(" ");
                    }
                    continue;
                }
                
                // Regular assignment =
                // Ensure space before =
                if (builder.buffer.items.len > 0 and 
                    builder.buffer.items[builder.buffer.items.len - 1] != ' ') {
                    try builder.append(" ");
                }
                try builder.append("=");
                i += 1;
                
                // Ensure space after = if next char isn't space
                if (i < text.len and text[i] != ' ') {
                    try builder.append(" ");
                }
                continue;
            }

            try builder.append(&[_]u8{c});
            i += 1;
        }
    }

    /// Format arrow operator spacing for switch statements
    /// Switch arms: `=> "red"` not `=>"red"` or `= >"red"`
    pub fn formatArrowOperator(text: []const u8, builder: *LineBuilder) !void {
        var i: usize = 0;
        var in_string = false;
        var string_char: u8 = 0;

        while (i < text.len) {
            const c = text[i];

            // Track string boundaries
            if (!in_string and (c == '"' or c == '\'')) {
                in_string = true;
                string_char = c;
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            if (in_string and c == string_char) {
                in_string = false;
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            if (in_string) {
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            // Handle arrow operator =>
            if (c == '=' and i + 1 < text.len and text[i + 1] == '>') {
                // Ensure space before =>
                if (builder.buffer.items.len > 0 and 
                    builder.buffer.items[builder.buffer.items.len - 1] != ' ') {
                    try builder.append(" ");
                }
                try builder.append("=> ");
                i += 2;
                continue;
            }

            try builder.append(&[_]u8{c});
            i += 1;
        }
    }

    /// Format function call spacing
    /// Control flow: `switch (expr)` not `switch(expr)`
    /// Function calls: `func(arg)` not `func (arg)`
    pub fn formatFunctionCallSpacing(text: []const u8, builder: *LineBuilder) !void {
        var i: usize = 0;
        const control_keywords = [_][]const u8{ "switch", "if", "while", "for" };

        while (i < text.len) {
            const c = text[i];

            if (c == '(' and i > 0) {
                // Check if this is a control flow statement that needs space
                const needs_space = blk: {
                    for (control_keywords) |keyword| {
                        if (i >= keyword.len and 
                            std.mem.eql(u8, text[i - keyword.len..i], keyword)) {
                            break :blk true;
                        }
                    }
                    break :blk false;
                };

                if (needs_space) {
                    // Add space before parenthesis for control flow
                    if (builder.buffer.items.len > 0 and 
                        builder.buffer.items[builder.buffer.items.len - 1] != ' ') {
                        try builder.append(" ");
                    }
                }
            }

            try builder.append(&[_]u8{c});
            i += 1;
        }
    }

    /// Format comma spacing in parameter lists and structs
    /// Parameters: `(a: i32, b: f64)` not `(a: i32,b: f64)` or `(a: i32 , b: f64)`
    pub fn formatCommaSpacing(text: []const u8, builder: *LineBuilder) !void {
        var i: usize = 0;
        var in_string = false;
        var string_char: u8 = 0;

        while (i < text.len) {
            const c = text[i];

            // Track string boundaries
            if (!in_string and (c == '"' or c == '\'')) {
                in_string = true;
                string_char = c;
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            if (in_string and c == string_char) {
                in_string = false;
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            if (in_string) {
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            // Handle comma spacing
            if (c == ',') {
                // Remove any trailing space before comma
                while (builder.buffer.items.len > 0 and 
                       builder.buffer.items[builder.buffer.items.len - 1] == ' ') {
                    _ = builder.buffer.pop();
                }
                try builder.append(",");
                i += 1;
                
                // Ensure space after comma if next char isn't space or newline
                if (i < text.len and text[i] != ' ' and text[i] != '\n') {
                    try builder.append(" ");
                }
                continue;
            }

            try builder.append(&[_]u8{c});
            i += 1;
        }
    }

    /// Format arithmetic operator spacing
    /// Operations: `a + b` not `a+b`, `a - b` not `a-b`
    pub fn formatArithmeticSpacing(text: []const u8, builder: *LineBuilder) !void {
        var i: usize = 0;
        var in_string = false;
        var string_char: u8 = 0;

        while (i < text.len) {
            const c = text[i];

            // Track string boundaries
            if (!in_string and (c == '"' or c == '\'')) {
                in_string = true;
                string_char = c;
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            if (in_string and c == string_char) {
                in_string = false;
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            if (in_string) {
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            // Handle arithmetic operators
            if ((c == '+' or c == '-' or c == '*' or c == '/') and
                // Avoid double operators like ++, --, etc.
                (i + 1 >= text.len or text[i + 1] != c)) {
                
                // Ensure space before operator
                if (builder.buffer.items.len > 0 and 
                    builder.buffer.items[builder.buffer.items.len - 1] != ' ') {
                    try builder.append(" ");
                }
                try builder.append(&[_]u8{c});
                i += 1;
                
                // Ensure space after operator if next char isn't space
                if (i < text.len and text[i] != ' ') {
                    try builder.append(" ");
                }
                continue;
            }

            try builder.append(&[_]u8{c});
            i += 1;
        }
    }

    /// Format all Zig spacing rules in one pass
    /// Comprehensive formatting that applies all spacing rules efficiently
    pub fn formatAllSpacing(text: []const u8, builder: *LineBuilder) !void {
        var i: usize = 0;
        var in_string = false;
        var string_char: u8 = 0;

        while (i < text.len) {
            const c = text[i];

            // Handle string boundaries
            if (!in_string and (c == '"' or c == '\'')) {
                in_string = true;
                string_char = c;
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            if (in_string and c == string_char) {
                in_string = false;
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            if (in_string) {
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            // Apply all spacing rules in order of precedence

            // 1. Arrow operator =>
            if (c == '=' and i + 1 < text.len and text[i + 1] == '>') {
                if (builder.buffer.items.len > 0 and 
                    builder.buffer.items[builder.buffer.items.len - 1] != ' ') {
                    try builder.append(" ");
                }
                try builder.append("=> ");
                i += 2;
                continue;
            }

            // 2. Comparison operator ==
            if (c == '=' and i + 1 < text.len and text[i + 1] == '=') {
                if (builder.buffer.items.len > 0 and 
                    builder.buffer.items[builder.buffer.items.len - 1] != ' ') {
                    try builder.append(" ");
                }
                try builder.append("==");
                i += 2;
                if (i < text.len and text[i] != ' ') {
                    try builder.append(" ");
                }
                continue;
            }

            // 3. Assignment operator =
            if (c == '=') {
                if (builder.buffer.items.len > 0 and 
                    builder.buffer.items[builder.buffer.items.len - 1] != ' ') {
                    try builder.append(" ");
                }
                try builder.append("=");
                i += 1;
                if (i < text.len and text[i] != ' ') {
                    try builder.append(" ");
                }
                continue;
            }

            // 4. Colon spacing for type annotations
            if (c == ':') {
                while (builder.buffer.items.len > 0 and 
                       builder.buffer.items[builder.buffer.items.len - 1] == ' ') {
                    _ = builder.buffer.pop();
                }
                try builder.append(":");
                i += 1;
                if (i < text.len and text[i] != ' ') {
                    try builder.append(" ");
                }
                continue;
            }

            // 5. Comma spacing
            if (c == ',') {
                while (builder.buffer.items.len > 0 and 
                       builder.buffer.items[builder.buffer.items.len - 1] == ' ') {
                    _ = builder.buffer.pop();
                }
                try builder.append(",");
                i += 1;
                if (i < text.len and text[i] != ' ' and text[i] != '\n') {
                    try builder.append(" ");
                }
                continue;
            }

            // 6. Space normalization
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
};