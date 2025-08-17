const std = @import("std");
const ts = @import("tree-sitter");
const LineBuilder = @import("../../parsing/formatter.zig").LineBuilder;
const FormatterOptions = @import("../../parsing/formatter.zig").FormatterOptions;
const ZigUtils = @import("zig_utils.zig").ZigUtils;
const collections = @import("../../core/collections.zig");

/// Zig-specific formatting helpers for common patterns
pub const ZigFormattingHelpers = struct {

    /// Format field with Zig-style colon spacing (no space before, space after)
    pub fn formatFieldWithColon(field: []const u8, builder: *LineBuilder) !void {
        if (std.mem.indexOf(u8, field, ":")) |colon_pos| {
            const field_name = std.mem.trim(u8, field[0..colon_pos], " \t");
            const field_type = std.mem.trim(u8, field[colon_pos + 1..], " \t");
            
            try builder.append(field_name);
            try builder.append(": ");
            try builder.append(field_type);
        } else {
            try builder.append(std.mem.trim(u8, field, " \t"));
        }
    }

    /// Format content with braces and proper indentation
    pub fn formatWithBraces(allocator: std.mem.Allocator, builder: *LineBuilder, content: []const u8, formatter_fn: *const fn(std.mem.Allocator, *LineBuilder, []const u8) anyerror!void) !void {
        try builder.append("{");
        
        if (content.len > 0) {
            try builder.newline();
            builder.indent();
            try formatter_fn(allocator, builder, content);
            builder.dedent();
            try builder.appendIndent();
        }
        
        try builder.append("}");
    }

    /// Check if position is inside a string literal
    pub fn isInString(text: []const u8, pos: usize) bool {
        var in_string = false;
        var i: usize = 0;
        while (i < pos and i < text.len) {
            if (text[i] == '"' and (i == 0 or text[i-1] != '\\')) {
                in_string = !in_string;
            }
            i += 1;
        }
        return in_string;
    }

    /// Check if position is inside a comment
    pub fn isInComment(text: []const u8, pos: usize) bool {
        // Look backwards for // comment start
        var i: usize = 0;
        while (i < pos and i + 1 < text.len) {
            if (text[i] == '/' and text[i + 1] == '/') {
                // Found comment start, check if there's a newline between it and pos
                var j = i + 2;
                while (j < pos) {
                    if (text[j] == '\n') return false;
                    j += 1;
                }
                return true;
            }
            i += 1;
        }
        return false;
    }


    /// Parse container content into individual members (fields and methods)
    pub fn parseContainerMembers(allocator: std.mem.Allocator, content: []const u8) ![][]const u8 {
        var members = collections.List([]const u8).init(allocator);
        defer members.deinit();

        var pos: usize = 0;
        
        while (pos < content.len) {
            // Skip whitespace
            while (pos < content.len and (content[pos] == ' ' or content[pos] == '\t' or content[pos] == '\n')) {
                pos += 1;
            }
            
            if (pos >= content.len) break;
            
            // Check if we hit a function 
            if (std.mem.startsWith(u8, content[pos..], "pub fn") or
                std.mem.startsWith(u8, content[pos..], "fn")) {
                // Parse function - find matching braces
                const fn_start = pos;
                
                if (std.mem.indexOfPos(u8, content, pos, "{")) |fn_brace_start| {
                    var brace_depth: u32 = 1;
                    var fn_end = fn_brace_start + 1;
                    
                    while (fn_end < content.len and brace_depth > 0) {
                        if (content[fn_end] == '{') {
                            brace_depth += 1;
                        } else if (content[fn_end] == '}') {
                            brace_depth -= 1;
                        }
                        fn_end += 1;
                    }
                    
                    if (brace_depth == 0) {
                        const function = content[fn_start..fn_end];
                        try members.append(try allocator.dupe(u8, function));
                        pos = fn_end;
                    } else {
                        pos += 1;
                    }
                } else {
                    pos += 1;
                }
            } else {
                // Parse field - find next comma or function start
                const field_start = pos;
                var colon_pos: ?usize = null;
                var field_end: usize = pos;
                
                while (pos < content.len) {
                    if (content[pos] == ':' and colon_pos == null) {
                        colon_pos = pos;
                    }
                    
                    if (content[pos] == ',') {
                        field_end = pos;
                        pos += 1;
                        break;
                    }
                    
                    if (std.mem.startsWith(u8, content[pos..], "pub fn") or 
                        std.mem.startsWith(u8, content[pos..], "fn")) {
                        field_end = pos;
                        break;
                    }
                    
                    pos += 1;
                }
                
                // Accept field with colon (typed field) OR simple identifier (enum value)
                const field = std.mem.trim(u8, content[field_start..field_end], " \t\n\r,");
                if (field.len > 0) {
                    // Check if it's a valid identifier or field declaration
                    if (colon_pos != null or isValidIdentifier(field)) {
                        try members.append(try allocator.dupe(u8, field));
                    }
                }
                
                if (field_end < content.len and (std.mem.startsWith(u8, content[field_end..], "pub fn") or
                                                 std.mem.startsWith(u8, content[field_end..], "fn"))) {
                    pos = field_end;
                }
            }
        }

        return members.toOwnedSlice();
    }

    /// Check if text represents a function declaration
    pub fn isFunctionDeclaration(text: []const u8) bool {
        return std.mem.indexOf(u8, text, "fn ") != null;
    }

    /// Format struct literal field with proper spacing around = signs
    pub fn formatStructLiteralField(builder: *LineBuilder, field: []const u8) !void {
        if (std.mem.indexOf(u8, field, "=")) |equals_pos| {
            const field_name = std.mem.trim(u8, field[0..equals_pos], " \t");
            const field_value = std.mem.trim(u8, field[equals_pos + 1..], " \t");
            
            try builder.append(field_name);
            try builder.append(" = ");
            try builder.append(field_value);
        } else {
            try builder.append(field);
        }
    }

    /// Split text by delimiter while preserving strings
    pub fn splitPreservingStrings(allocator: std.mem.Allocator, text: []const u8, delimiter: u8) ![][]const u8 {
        var result = collections.List([]const u8).init(allocator);
        defer result.deinit();
        
        var start: usize = 0;
        var i: usize = 0;
        var in_string = false;
        
        while (i < text.len) {
            if (text[i] == '"' and (i == 0 or text[i-1] != '\\')) {
                in_string = !in_string;
            } else if (!in_string and text[i] == delimiter) {
                const segment = std.mem.trim(u8, text[start..i], " \t\n\r");
                if (segment.len > 0) {
                    try result.append(try allocator.dupe(u8, segment));
                }
                start = i + 1;
            }
            i += 1;
        }
        
        // Add final segment
        if (start < text.len) {
            const segment = std.mem.trim(u8, text[start..], " \t\n\r");
            if (segment.len > 0) {
                try result.append(try allocator.dupe(u8, segment));
            }
        }
        
        return result.toOwnedSlice();
    }

    /// Format simple spacing around equals
    pub fn formatEqualsSpacing(text: []const u8, builder: *LineBuilder) !void {
        var i: usize = 0;
        while (i < text.len) {
            const c = text[i];
            
            if (c == '=' and i > 0 and text[i-1] != '=' and i + 1 < text.len and text[i+1] != '=') {
                // Ensure no trailing space before equals
                if (builder.buffer.items.len > 0 and
                    builder.buffer.items[builder.buffer.items.len - 1] == ' ') {
                    _ = builder.buffer.pop();
                }
                try builder.append(" = ");
                i += 1;
                // Skip any spaces after equals in original
                while (i < text.len and text[i] == ' ') {
                    i += 1;
                }
                continue;
            }
            
            try builder.append(&[_]u8{c});
            i += 1;
        }
    }
    
    /// Check if text is a valid Zig identifier (for enum values)
    fn isValidIdentifier(text: []const u8) bool {
        if (text.len == 0) return false;
        
        // First character must be letter or underscore
        if (!std.ascii.isAlphabetic(text[0]) and text[0] != '_') {
            return false;
        }
        
        // Rest can be letters, digits, or underscores
        for (text[1..]) |c| {
            if (!std.ascii.isAlphanumeric(c) and c != '_') {
                return false;
            }
        }
        
        return true;
    }
};