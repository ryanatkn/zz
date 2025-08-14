const std = @import("std");
const FormatterOptions = @import("../../parsing/formatter.zig").FormatterOptions;
const LineBuilder = @import("../../parsing/formatter.zig").LineBuilder;

/// Format CSS source code
pub fn format(allocator: std.mem.Allocator, source: []const u8, options: FormatterOptions) ![]const u8 {
    var builder = LineBuilder.init(allocator, options);
    defer builder.deinit();
    
    var lines = std.mem.splitScalar(u8, source, '\n');
    var in_rule = false;
    var brace_depth: u32 = 0;
    
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        
        // Skip empty lines
        if (trimmed.len == 0) {
            try builder.newline();
            continue;
        }
        
        // Handle closing braces
        if (std.mem.startsWith(u8, trimmed, "}")) {
            if (brace_depth > 0) {
                builder.dedent();
                brace_depth -= 1;
            }
            in_rule = false;
            try builder.appendIndent();
            try builder.append("}");
            try builder.newline();
            if (brace_depth == 0) {
                try builder.newline(); // Extra line after closing rule
            }
            continue;
        }
        
        // Handle selectors and at-rules
        if (std.mem.indexOf(u8, trimmed, "{") != null) {
            try builder.appendIndent();
            
            // Format selector part
            const brace_pos = std.mem.indexOf(u8, trimmed, "{").?;
            const selector_part = std.mem.trim(u8, trimmed[0..brace_pos], " \t");
            try builder.append(selector_part);
            try builder.append(" {");
            try builder.newline();
            
            builder.indent();
            brace_depth += 1;
            in_rule = true;
            continue;
        }
        
        // Handle properties inside rules
        if (in_rule and std.mem.indexOf(u8, trimmed, ":") != null) {
            try builder.appendIndent();
            
            // Format property: value;
            if (std.mem.indexOf(u8, trimmed, ":")) |colon_pos| {
                const property = std.mem.trim(u8, trimmed[0..colon_pos], " \t");
                const value_part = std.mem.trim(u8, trimmed[colon_pos + 1..], " \t");
                
                try builder.append(property);
                try builder.append(": ");
                try builder.append(value_part);
                if (!std.mem.endsWith(u8, value_part, ";")) {
                    try builder.append(";");
                }
            }
            try builder.newline();
            continue;
        }
        
        // Default: add line with proper indentation
        try builder.appendIndent();
        try builder.append(trimmed);
        try builder.newline();
    }
    
    return builder.toOwnedSlice();
}