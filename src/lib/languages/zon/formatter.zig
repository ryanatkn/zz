const std = @import("std");
const FormatterOptions = @import("../../parsing/formatter.zig").FormatterOptions;

/// ZON (Zig Object Notation) formatter
/// Formats ZON files with proper indentation, commenting, and structure
/// ZON is similar to JSON but uses Zig-specific syntax

/// Format ZON content using simple text-based approach
pub fn formatZon(allocator: std.mem.Allocator, content: []const u8, options: FormatterOptions) ![]u8 {
    // For now, use a simple approach similar to Zig formatting
    // ZON is essentially a subset of Zig syntax for data structures
    return formatZonSimple(allocator, content, options);
}

/// Simple ZON formatting with basic cleanup
fn formatZonSimple(allocator: std.mem.Allocator, content: []const u8, options: FormatterOptions) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();
    
    var lines = std.mem.splitSequence(u8, content, "\n");
    var indent_level: u32 = 0;
    
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        
        // Skip empty lines
        if (trimmed.len == 0) {
            try result.append('\n');
            continue;
        }
        
        // Handle comments - preserve as-is with proper indentation
        if (std.mem.startsWith(u8, trimmed, "//")) {
            try appendIndent(&result, indent_level, options);
            try result.appendSlice(trimmed);
            try result.append('\n');
            continue;
        }
        
        // Handle closing braces - dedent first
        if (std.mem.startsWith(u8, trimmed, "}")) {
            if (indent_level > 0) indent_level -= 1;
            try appendIndent(&result, indent_level, options);
            try result.appendSlice(trimmed);
            try result.append('\n');
            continue;
        }
        
        // Add proper indentation
        try appendIndent(&result, indent_level, options);
        
        // Clean up the line formatting
        const formatted_line = try formatZonLine(allocator, trimmed, options);
        defer allocator.free(formatted_line);
        
        try result.appendSlice(formatted_line);
        try result.append('\n');
        
        // Handle opening braces - indent after
        if (std.mem.indexOf(u8, trimmed, "{") != null) {
            indent_level += 1;
        }
    }
    
    return result.toOwnedSlice();
}

/// Format a single ZON line
fn formatZonLine(allocator: std.mem.Allocator, line: []const u8, options: FormatterOptions) ![]u8 {
    _ = options;
    
    // Fix spacing around equals signs
    if (std.mem.indexOf(u8, line, "=")) |eq_pos| {
        const before_eq = std.mem.trimRight(u8, line[0..eq_pos], " \t");
        const after_eq = std.mem.trimLeft(u8, line[eq_pos + 1..], " \t");
        
        return std.fmt.allocPrint(allocator, "{s} = {s}", .{ before_eq, after_eq });
    } else {
        // No equals sign, return as-is
        return allocator.dupe(u8, line);
    }
}

/// Append proper indentation
fn appendIndent(result: *std.ArrayList(u8), level: u32, options: FormatterOptions) !void {
    const indent_char = if (options.indent_style == .tab) "\t" else " ";
    const indent_size = if (options.indent_style == .tab) 1 else options.indent_size;
    
    var i: u32 = 0;
    while (i < level * indent_size) : (i += 1) {
        try result.appendSlice(indent_char);
    }
}

/// Check if ZON content is well-formed for formatting
pub fn isValidZon(content: []const u8) bool {
    var brace_count: i32 = 0;
    var in_string = false;
    var escape_next = false;
    
    for (content) |c| {
        if (escape_next) {
            escape_next = false;
            continue;
        }
        
        if (in_string) {
            if (c == '\\') {
                escape_next = true;
            } else if (c == '"') {
                in_string = false;
            }
            continue;
        }
        
        switch (c) {
            '"' => in_string = true,
            '{' => brace_count += 1,
            '}' => brace_count -= 1,
            else => {},
        }
        
        if (brace_count < 0) return false; // More closing than opening
    }
    
    return brace_count == 0 and !in_string;
}

test "formatZon basic" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    const input =
        \\.{
        \\.name="test",
        \\.version   =   "1.0.0"   ,
        \\}
    ;
    
    const options = FormatterOptions{};
    const formatted = try formatZon(allocator, input, options);
    defer allocator.free(formatted);
    
    // Should have proper spacing around equals
    try testing.expect(std.mem.indexOf(u8, formatted, ".name = \"test\"") != null);
    try testing.expect(std.mem.indexOf(u8, formatted, ".version = \"1.0.0\"") != null);
}

test "isValidZon" {
    const valid_zon = 
        \\.{
        \\    .name = "test",
        \\    .nested = .{
        \\        .value = "hello",
        \\    },
        \\}
    ;
    
    const invalid_zon = 
        \\.{
        \\    .name = "test",
        \\    .nested = .{
        \\        .value = "hello"
        \\    // Missing closing brace
    ;
    
    try std.testing.expect(isValidZon(valid_zon));
    try std.testing.expect(!isValidZon(invalid_zon));
}