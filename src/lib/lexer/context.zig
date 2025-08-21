/// Lexer context and error handling
///
/// Common context and error types for all lexers.
const std = @import("std");
const Span = @import("../span/span.zig").Span;

/// Lexer error types
pub const LexerError = error{
    UnexpectedCharacter,
    UnterminatedString,
    UnterminatedComment,
    InvalidEscape,
    InvalidNumber,
    InvalidUnicode,
    BufferOverflow,
    OutOfMemory,
};

/// Detailed error information
pub const ErrorDetail = struct {
    kind: LexerError,
    message: []const u8,
    span: Span,
    hint: ?[]const u8 = null,
};

/// Lexer context for error tracking and state
pub const LexerContext = struct {
    /// Current position in source
    position: usize = 0,
    /// Current line number (1-based)
    line: u32 = 1,
    /// Current column (1-based)
    column: u32 = 1,
    /// Errors encountered during lexing
    errors: std.ArrayList(ErrorDetail),
    /// Warning messages
    warnings: std.ArrayList(ErrorDetail),
    /// Source file path (optional)
    source_path: ?[]const u8 = null,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .errors = std.ArrayList(ErrorDetail).init(allocator),
            .warnings = std.ArrayList(ErrorDetail).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.errors.deinit();
        self.warnings.deinit();
    }

    /// Add an error
    pub fn addError(self: *Self, err: LexerError, message: []const u8, span: Span) !void {
        try self.errors.append(.{
            .kind = err,
            .message = message,
            .span = span,
        });
    }

    /// Add a warning
    pub fn addWarning(self: *Self, err: LexerError, message: []const u8, span: Span) !void {
        try self.warnings.append(.{
            .kind = err,
            .message = message,
            .span = span,
        });
    }

    /// Update position tracking
    pub fn advance(self: *Self, char: u8) void {
        self.position += 1;
        if (char == '\n') {
            self.line += 1;
            self.column = 1;
        } else {
            self.column += 1;
        }
    }

    /// Get current span
    pub fn currentSpan(self: *Self) Span {
        return Span{
            .start = @intCast(self.position),
            .end = @intCast(self.position + 1),
        };
    }

    /// Create span from start position to current
    pub fn spanFrom(self: *Self, start: usize) Span {
        return Span{
            .start = @intCast(start),
            .end = @intCast(self.position),
        };
    }

    /// Check if lexing had errors
    pub fn hasErrors(self: *Self) bool {
        return self.errors.items.len > 0;
    }

    /// Clear all errors and warnings
    pub fn clearErrors(self: *Self) void {
        self.errors.clearRetainingCapacity();
        self.warnings.clearRetainingCapacity();
    }

    /// Reset context for new source
    pub fn reset(self: *Self) void {
        self.position = 0;
        self.line = 1;
        self.column = 1;
        self.clearErrors();
    }
};

/// Common lexer state that can be shared
pub const LexerState = struct {
    /// Nesting depth for brackets/parens
    nesting_depth: u32 = 0,
    /// Whether currently in a string
    in_string: bool = false,
    /// Whether currently in a comment
    in_comment: bool = false,
    /// String delimiter if in string
    string_delimiter: ?u8 = null,
    /// Comment style if in comment
    comment_style: CommentStyle = .none,

    pub const CommentStyle = enum {
        none,
        single_line,
        multi_line,
        doc_comment,
    };

    pub fn reset(self: *LexerState) void {
        self.nesting_depth = 0;
        self.in_string = false;
        self.in_comment = false;
        self.string_delimiter = null;
        self.comment_style = .none;
    }
};
