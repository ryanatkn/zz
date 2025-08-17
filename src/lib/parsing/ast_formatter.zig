const std = @import("std");
const FormatterOptions = @import("formatter.zig").FormatterOptions;

/// Legacy AST formatter compatibility stub - delegates to stratified parser
pub const AstFormatter = struct {
    options: FormatterOptions,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, options: FormatterOptions) AstFormatter {
        return AstFormatter{
            .options = options,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *AstFormatter) void {
        _ = self;
    }
    
    /// Format AST content using stratified parser (stub implementation)
    pub fn formatAst(self: *AstFormatter, content: []const u8) ![]u8 {
        // For now, just return a copy of the content
        // In the future, this would use the stratified parser's AST formatting
        return try self.allocator.dupe(u8, content);
    }
    
    /// Format with language-specific rules
    pub fn formatWithLanguage(self: *AstFormatter, content: []const u8, language: []const u8) ![]u8 {
        _ = language;
        return try self.formatAst(content);
    }
};