const std = @import("std");
const Language = @import("ast.zig").Language;
const AstFormatter = @import("ast_formatter.zig").AstFormatter;

pub const IndentStyle = enum {
    space,
    tab,
};

pub const FormatterOptions = struct {
    indent_size: u8 = 4,
    indent_style: IndentStyle = .space,
    line_width: u32 = 100,
    preserve_newlines: bool = true,
    trailing_comma: bool = false,
    sort_keys: bool = false, // For JSON
    quote_style: enum { single, double, preserve } = .preserve,
    use_ast: bool = true, // Prefer AST-based formatting when available
};

pub const FormatterError = error{
    UnsupportedLanguage,
    InvalidSource,
    FormattingFailed,
    ExternalToolNotFound,
    OutOfMemory,
};

pub const Formatter = struct {
    allocator: std.mem.Allocator,
    options: FormatterOptions,
    language: Language,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, language: Language, options: FormatterOptions) Self {
        return Self{
            .allocator = allocator,
            .options = options,
            .language = language,
        };
    }

    pub fn format(self: *Self, source: []const u8) FormatterError![]const u8 {
        // Try AST-based formatting first if enabled and supported
        if (self.options.use_ast and self.supportsAstFormatting()) {
            if (self.formatWithAst(source)) |result| {
                return result;
            } else |_| {
                // Fall back to traditional formatters on AST failure
            }
        }
        
        // Dispatch to language-specific formatter
        return switch (self.language) {
            .json => try self.formatJson(source),
            .zig => try self.formatZig(source),
            .html => try self.formatHtml(source),
            .css => try self.formatCss(source),
            .typescript => try self.formatTypeScript(source),
            .svelte => try self.formatSvelte(source),
            .c, .cpp, .python, .rust, .go => FormatterError.UnsupportedLanguage,
            .unknown => FormatterError.UnsupportedLanguage,
        };
    }
    
    /// Check if this language supports AST-based formatting
    fn supportsAstFormatting(self: *Self) bool {
        return switch (self.language) {
            .typescript, .css, .svelte => true,
            .json, .zig, .html => false, // Have good existing implementations
            .c, .cpp, .python, .rust, .go => false, // No formatters yet
            .unknown => false,
        };
    }
    
    /// AST-based formatting
    fn formatWithAst(self: *Self, source: []const u8) FormatterError![]const u8 {
        var ast_formatter = AstFormatter.init(self.allocator, self.language, self.options) catch {
            return FormatterError.FormattingFailed;
        };
        defer ast_formatter.deinit();
        
        return ast_formatter.format(source) catch {
            return FormatterError.FormattingFailed;
        };
    }

    fn formatJson(self: *Self, source: []const u8) FormatterError![]const u8 {
        const json_formatter = @import("formatters/json.zig");
        return json_formatter.format(self.allocator, source, self.options) catch |err| switch (err) {
            error.OutOfMemory => return FormatterError.OutOfMemory,
            else => return FormatterError.FormattingFailed,
        };
    }

    fn formatZig(self: *Self, source: []const u8) FormatterError![]const u8 {
        const zig_formatter = @import("formatters/zig.zig");
        return zig_formatter.format(self.allocator, source, self.options) catch |err| switch (err) {
            error.OutOfMemory => return FormatterError.OutOfMemory,
            else => return FormatterError.FormattingFailed,
        };
    }

    fn formatHtml(self: *Self, source: []const u8) FormatterError![]const u8 {
        const html_formatter = @import("formatters/html.zig");
        return html_formatter.format(self.allocator, source, self.options) catch {
            return FormatterError.FormattingFailed;
        };
    }

    fn formatCss(self: *Self, source: []const u8) FormatterError![]const u8 {
        const css_formatter = @import("formatters/css.zig");
        return css_formatter.format(self.allocator, source, self.options) catch {
            return FormatterError.FormattingFailed;
        };
    }

    fn formatTypeScript(self: *Self, source: []const u8) FormatterError![]const u8 {
        const ts_formatter = @import("formatters/typescript.zig");
        return ts_formatter.format(self.allocator, source, self.options) catch {
            return FormatterError.FormattingFailed;
        };
    }

    fn formatSvelte(self: *Self, source: []const u8) FormatterError![]const u8 {
        const svelte_formatter = @import("formatters/svelte.zig");
        return svelte_formatter.format(self.allocator, source, self.options) catch {
            return FormatterError.FormattingFailed;
        };
    }
};

// Helper functions for formatters

pub fn getIndentString(options: FormatterOptions) []const u8 {
    if (options.indent_style == .tab) {
        return "\t";
    } else {
        return switch (options.indent_size) {
            2 => "  ",
            4 => "    ",
            8 => "        ",
            else => "    ", // Default to 4 spaces
        };
    }
}

pub fn createIndent(allocator: std.mem.Allocator, level: u32, options: FormatterOptions) ![]const u8 {
    const indent_str = getIndentString(options);
    const total_len = indent_str.len * level;
    
    var result = try allocator.alloc(u8, total_len);
    var i: u32 = 0;
    while (i < level) : (i += 1) {
        const start = i * indent_str.len;
        @memcpy(result[start..start + indent_str.len], indent_str);
    }
    
    return result;
}

pub const LineBuilder = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8),
    options: FormatterOptions,
    indent_level: u32 = 0,
    current_line_length: u32 = 0,

    pub fn init(allocator: std.mem.Allocator, options: FormatterOptions) LineBuilder {
        return .{
            .allocator = allocator,
            .buffer = std.ArrayList(u8).init(allocator),
            .options = options,
        };
    }

    pub fn deinit(self: *LineBuilder) void {
        self.buffer.deinit();
    }

    pub fn indent(self: *LineBuilder) void {
        self.indent_level += 1;
    }

    pub fn dedent(self: *LineBuilder) void {
        if (self.indent_level > 0) {
            self.indent_level -= 1;
        }
    }

    pub fn appendIndent(self: *LineBuilder) !void {
        const indent_str = try createIndent(self.allocator, self.indent_level, self.options);
        defer self.allocator.free(indent_str);
        try self.buffer.appendSlice(indent_str);
        self.current_line_length = @intCast(indent_str.len);
    }

    pub fn append(self: *LineBuilder, text: []const u8) !void {
        try self.buffer.appendSlice(text);
        self.current_line_length += @intCast(text.len);
    }

    pub fn newline(self: *LineBuilder) !void {
        try self.buffer.append('\n');
        self.current_line_length = 0;
    }

    pub fn shouldBreakLine(self: *LineBuilder, additional_length: u32) bool {
        return self.current_line_length + additional_length > self.options.line_width;
    }

    pub fn toOwnedSlice(self: *LineBuilder) ![]const u8 {
        return self.buffer.toOwnedSlice();
    }
};