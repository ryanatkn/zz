const std = @import("std");
const FormatterOptions = @import("../../parsing/formatter.zig").FormatterOptions;
const LineBuilder = @import("../../parsing/formatter.zig").LineBuilder;
const visitor_mod = @import("visitor.zig");

/// Format HTML source code
pub fn format(allocator: std.mem.Allocator, source: []const u8, options: FormatterOptions) ![]const u8 {
    var builder = LineBuilder.init(allocator, options);
    defer builder.deinit();
    
    // Parse HTML and format with indentation
    var lines = std.mem.splitScalar(u8, source, '\n');
    var in_comment = false;
    
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r\n");
        
        if (trimmed.len == 0) {
            if (options.preserve_newlines) {
                try builder.newline();
            }
            continue;
        }
        
        // Handle HTML comments
        if (std.mem.startsWith(u8, trimmed, "<!--")) {
            in_comment = true;
            try builder.appendIndent();
            try builder.append(trimmed);
            try builder.newline();
            if (std.mem.endsWith(u8, trimmed, "-->")) {
                in_comment = false;
            }
            continue;
        }
        
        if (in_comment) {
            try builder.appendIndent();
            try builder.append(trimmed);
            try builder.newline();
            if (std.mem.endsWith(u8, trimmed, "-->")) {
                in_comment = false;
            }
            continue;
        }
        
        // Handle DOCTYPE
        if (std.mem.startsWith(u8, trimmed, "<!DOCTYPE")) {
            try builder.append(trimmed);
            try builder.newline();
            continue;
        }
        
        // Handle opening tags
        if (std.mem.startsWith(u8, trimmed, "<") and !std.mem.startsWith(u8, trimmed, "</")) {
            try builder.appendIndent();
            try builder.append(trimmed);
            try builder.newline();
            
            // Check if it's a self-closing tag or void element
            if (!std.mem.endsWith(u8, trimmed, "/>") and !visitor_mod.isVoidElement(trimmed)) {
                builder.indent();
            }
            continue;
        }
        
        // Handle closing tags
        if (std.mem.startsWith(u8, trimmed, "</")) {
            builder.dedent();
            try builder.appendIndent();
            try builder.append(trimmed);
            try builder.newline();
            continue;
        }
        
        // Handle text content
        try builder.appendIndent();
        try builder.append(trimmed);
        try builder.newline();
    }
    
    return builder.toOwnedSlice();
}