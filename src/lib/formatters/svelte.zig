const std = @import("std");
const FormatterOptions = @import("../parsing/formatter.zig").FormatterOptions;
const AstFormatter = @import("../parsing/ast_formatter.zig").AstFormatter;
const Language = @import("../language/detection.zig").Language;

pub fn format(allocator: std.mem.Allocator, source: []const u8, options: FormatterOptions) ![]const u8 {
    // Try AST-based Svelte formatting with section-aware parsing
    var ast_formatter = AstFormatter.init(allocator, .svelte, options) catch {
        // If AST formatter creation fails, return source as-is
        return allocator.dupe(u8, source);
    };
    defer ast_formatter.deinit();
    
    return ast_formatter.format(source) catch {
        // If AST formatting fails, return source as-is
        return allocator.dupe(u8, source);
    };
}