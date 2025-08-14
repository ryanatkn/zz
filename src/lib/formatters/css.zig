const std = @import("std");
const FormatterOptions = @import("../formatter.zig").FormatterOptions;
const LineBuilder = @import("../formatter.zig").LineBuilder;

pub fn format(allocator: std.mem.Allocator, source: []const u8, options: FormatterOptions) ![]const u8 {
    var builder = LineBuilder.init(allocator, options);
    defer builder.deinit();
    
    var i: usize = 0;
    var in_comment = false;
    var in_string = false;
    var string_char: ?u8 = null;
    
    while (i < source.len) {
        const char = source[i];
        
        // Handle strings
        if (!in_comment) {
            if ((char == '"' or char == '\'') and (i == 0 or source[i - 1] != '\\')) {
                if (!in_string) {
                    in_string = true;
                    string_char = char;
                } else if (char == string_char) {
                    in_string = false;
                    string_char = null;
                }
            }
        }
        
        // Handle comments
        if (!in_string and i + 1 < source.len) {
            if (source[i] == '/' and source[i + 1] == '*') {
                in_comment = true;
                try builder.append("/*");
                i += 2;
                continue;
            }
            if (in_comment and source[i] == '*' and source[i + 1] == '/') {
                in_comment = false;
                try builder.append("*/");
                i += 2;
                if (i < source.len and source[i] == '\n') {
                    try builder.newline();
                    i += 1;
                }
                continue;
            }
        }
        
        if (in_comment or in_string) {
            try builder.append(&[_]u8{char});
            i += 1;
            continue;
        }
        
        // Format CSS
        switch (char) {
            '{' => {
                try builder.append(" {");
                try builder.newline();
                builder.indent();
                i += 1;
                // Skip whitespace after {
                while (i < source.len and isWhitespace(source[i])) : (i += 1) {}
                continue;
            },
            '}' => {
                // Remove trailing whitespace
                while (builder.buffer.items.len > 0 and isWhitespace(builder.buffer.items[builder.buffer.items.len - 1])) {
                    _ = builder.buffer.pop();
                }
                if (builder.buffer.items.len > 0 and builder.buffer.items[builder.buffer.items.len - 1] != '\n') {
                    try builder.newline();
                }
                builder.dedent();
                try builder.appendIndent();
                try builder.append("}");
                try builder.newline();
                i += 1;
                // Add blank line after rule blocks
                if (i < source.len and source[i] != '}') {
                    try builder.newline();
                }
                // Skip whitespace after }
                while (i < source.len and isWhitespace(source[i])) : (i += 1) {}
                continue;
            },
            ';' => {
                try builder.append(";");
                try builder.newline();
                i += 1;
                // Skip whitespace after ;
                while (i < source.len and isWhitespace(source[i])) : (i += 1) {}
                continue;
            },
            ':' => {
                // Add space after colon in property values
                try builder.append(": ");
                i += 1;
                // Skip whitespace after :
                while (i < source.len and isWhitespace(source[i])) : (i += 1) {}
                continue;
            },
            ',' => {
                try builder.append(",");
                // Add space after comma in selectors
                if (i + 1 < source.len and !isNewline(source[i + 1])) {
                    try builder.append(" ");
                }
                i += 1;
                continue;
            },
            '\n', '\r' => {
                // Skip extra newlines
                i += 1;
                continue;
            },
            ' ', '\t' => {
                // Collapse multiple spaces
                if (builder.buffer.items.len > 0 and !isWhitespace(builder.buffer.items[builder.buffer.items.len - 1])) {
                    try builder.append(" ");
                }
                i += 1;
                while (i < source.len and (source[i] == ' ' or source[i] == '\t')) : (i += 1) {}
                continue;
            },
            else => {
                // Start of property or selector
                if (builder.current_line_length == 0 and builder.indent_level > 0) {
                    try builder.appendIndent();
                }
                try builder.append(&[_]u8{char});
                i += 1;
            },
        }
    }
    
    return builder.toOwnedSlice();
}

fn isWhitespace(char: u8) bool {
    return char == ' ' or char == '\t' or char == '\n' or char == '\r';
}

fn isNewline(char: u8) bool {
    return char == '\n' or char == '\r';
}