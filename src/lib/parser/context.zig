const std = @import("std");

/// Parse context that tracks position and provides input management
pub const ParseContext = struct {
    allocator: std.mem.Allocator,
    input: []const u8,
    position: usize,
    errors: std.ArrayList(ParseError),
    
    pub fn init(allocator: std.mem.Allocator, input: []const u8) ParseContext {
        return .{
            .allocator = allocator,
            .input = input,
            .position = 0,
            .errors = std.ArrayList(ParseError).init(allocator),
        };
    }
    
    pub fn deinit(self: *ParseContext) void {
        self.errors.deinit();
    }
    
    /// Get remaining input from current position
    pub fn remaining(self: ParseContext) []const u8 {
        if (self.position >= self.input.len) return "";
        return self.input[self.position..];
    }
    
    /// Advance position by count characters
    pub fn advance(self: *ParseContext, count: usize) void {
        self.position = @min(self.position + count, self.input.len);
    }
    
    /// Check if we're at end of input
    pub fn isAtEnd(self: ParseContext) bool {
        return self.position >= self.input.len;
    }
    
    /// Peek at character at current position without advancing
    pub fn peek(self: ParseContext) ?u8 {
        if (self.isAtEnd()) return null;
        return self.input[self.position];
    }
    
    /// Peek ahead by offset characters
    pub fn peekAhead(self: ParseContext, offset: usize) ?u8 {
        const pos = self.position + offset;
        if (pos >= self.input.len) return null;
        return self.input[pos];
    }
    
    /// Get current line number (1-based) for error reporting
    pub fn currentLine(self: ParseContext) usize {
        var line: usize = 1;
        for (self.input[0..self.position]) |char| {
            if (char == '\n') line += 1;
        }
        return line;
    }
    
    /// Get current column number (1-based) for error reporting
    pub fn currentColumn(self: ParseContext) usize {
        var column: usize = 1;
        var i = self.position;
        while (i > 0) {
            i -= 1;
            if (self.input[i] == '\n') break;
            column += 1;
        }
        return column;
    }
    
    /// Add a parse error at current position
    pub fn addError(self: *ParseContext, message: []const u8) !void {
        try self.errors.append(ParseError{
            .message = message,
            .position = self.position,
            .line = self.currentLine(),
            .column = self.currentColumn(),
        });
    }
    
    /// Create a mark at current position for backtracking
    pub fn mark(self: ParseContext) usize {
        return self.position;
    }
    
    /// Reset to a previously marked position
    pub fn reset(self: *ParseContext, mark_position: usize) void {
        self.position = mark_position;
    }
    
    /// Get text between two positions
    pub fn getTextBetween(self: ParseContext, start: usize, end: usize) []const u8 {
        const actual_start = @min(start, self.input.len);
        const actual_end = @min(end, self.input.len);
        if (actual_start >= actual_end) return "";
        return self.input[actual_start..actual_end];
    }
};

/// Parse error with position information
pub const ParseError = struct {
    message: []const u8,
    position: usize,
    line: usize,
    column: usize,
    
    pub fn format(self: ParseError, writer: anytype) !void {
        try writer.print("Error at line {}, column {}: {s}", .{ self.line, self.column, self.message });
    }
};