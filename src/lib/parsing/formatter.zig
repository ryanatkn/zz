const std = @import("std");

/// Legacy formatter compatibility stub - delegates to stratified parser
pub const FormatterOptions = struct {
    indent_size: u32 = 4,
    use_tabs: bool = false,
    max_line_length: u32 = 100,

    pub fn default() FormatterOptions {
        return FormatterOptions{};
    }
};

pub const IndentStyle = enum {
    spaces,
    tabs,
};

pub const LineBuilder = struct {
    buffer: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) LineBuilder {
        return LineBuilder{
            .buffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *LineBuilder) void {
        self.buffer.deinit();
    }

    pub fn append(self: *LineBuilder, text: []const u8) !void {
        try self.buffer.appendSlice(text);
    }

    pub fn toOwnedSlice(self: *LineBuilder) ![]u8 {
        return try self.buffer.toOwnedSlice();
    }
};

pub const Formatter = struct {
    options: FormatterOptions,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, options: FormatterOptions) Formatter {
        return Formatter{
            .options = options,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Formatter) void {
        _ = self;
    }

    /// Format content using stratified parser (stub implementation)
    pub fn format(self: *Formatter, content: []const u8) ![]u8 {
        // For now, just return a copy of the content
        // In the future, this would use the stratified parser's formatting capabilities
        return try self.allocator.dupe(u8, content);
    }
};
