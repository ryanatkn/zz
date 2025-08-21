/// Parse context and error tracking
///
/// Manages parsing state, error collection, and recovery information.
const std = @import("std");
const Span = @import("../span/span.zig").Span;
const Token = @import("../token/token.zig").Token;
const TokenKind = @import("../token/token.zig").TokenKind;
const Boundary = @import("structural.zig").Boundary;

/// Parse context for tracking state
pub const ParseContext = struct {
    allocator: std.mem.Allocator,
    source: []const u8,
    tokens: []const Token,
    errors: std.ArrayList(ParseError),
    warnings: std.ArrayList(ParseWarning),
    boundaries: std.ArrayList(*Boundary),
    current_depth: u32 = 0,
    max_depth: u32 = 100,
    strict_mode: bool = false,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, source: []const u8, tokens: []const Token) Self {
        return .{
            .allocator = allocator,
            .source = source,
            .tokens = tokens,
            .errors = std.ArrayList(ParseError).init(allocator),
            .warnings = std.ArrayList(ParseWarning).init(allocator),
            .boundaries = std.ArrayList(*Boundary).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.errors.deinit();
        self.warnings.deinit();
        self.boundaries.deinit();
    }

    /// Add parse error
    pub fn addError(self: *Self, err: ParseError) !void {
        try self.errors.append(err);

        // In strict mode, stop at first error
        if (self.strict_mode) {
            return error.ParseError;
        }
    }

    /// Add parse warning
    pub fn addWarning(self: *Self, warning: ParseWarning) !void {
        try self.warnings.append(warning);
    }

    /// Check nesting depth
    pub fn enterNesting(self: *Self) !void {
        self.current_depth += 1;
        if (self.current_depth > self.max_depth) {
            try self.addError(.{
                .kind = .MaxDepthExceeded,
                .message = "Maximum nesting depth exceeded",
                .span = .{ .start = 0, .end = 0 },
            });
            return error.MaxDepthExceeded;
        }
    }

    pub fn exitNesting(self: *Self) void {
        if (self.current_depth > 0) {
            self.current_depth -= 1;
        }
    }

    /// Get source text for span
    pub fn getSpanText(self: *Self, span: Span) []const u8 {
        const start = @min(span.start, self.source.len);
        const end = @min(span.end, self.source.len);
        return self.source[start..end];
    }

    /// Check if parsing succeeded
    pub fn hasErrors(self: *Self) bool {
        return self.errors.items.len > 0;
    }

    /// Get error summary
    pub fn getErrorSummary(self: *Self, allocator: std.mem.Allocator) ![]u8 {
        var buffer = std.ArrayList(u8).init(allocator);
        const writer = buffer.writer();

        for (self.errors.items) |err| {
            try writer.print("{s} at {}-{}", .{
                @tagName(err.kind),
                err.span.start,
                err.span.end,
            });
            if (err.message) |msg| {
                try writer.print(": {s}", .{msg});
            }
            try writer.writeByte('\n');
        }

        return buffer.toOwnedSlice();
    }
};

/// Parse error information
pub const ParseError = struct {
    kind: ParseErrorKind,
    message: ?[]const u8 = null,
    span: Span,
    hint: ?[]const u8 = null,
    expected: ?TokenKind = null,
    found: ?TokenKind = null,
};

pub const ParseErrorKind = enum {
    UnexpectedToken,
    UnexpectedEOF,
    InvalidSyntax,
    MissingToken,
    DuplicateKey,
    InvalidExpression,
    MaxDepthExceeded,
    InvalidNumber,
    InvalidString,
    InvalidIdentifier,
    TrailingComma,
    MissingComma,
    UnclosedDelimiter,
};

/// Parse warning information
pub const ParseWarning = struct {
    kind: ParseWarningKind,
    message: []const u8,
    span: Span,
    suggestion: ?[]const u8 = null,
};

pub const ParseWarningKind = enum {
    DeprecatedSyntax,
    UnnecessaryParentheses,
    UnusedVariable,
    ShadowedVariable,
    UnreachableCode,
    MissingDocumentation,
    InconsistentStyle,
};

/// Parse statistics
pub const ParseStats = struct {
    total_tokens: usize,
    parse_time_ns: u64,
    error_count: usize,
    warning_count: usize,
    max_depth_reached: u32,
    boundaries_found: usize,

    pub fn format(
        self: ParseStats,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        const parse_time_ms = self.parse_time_ns / 1_000_000;
        const tokens_per_ms = if (parse_time_ms > 0)
            self.total_tokens / parse_time_ms
        else
            0;

        try writer.print(
            \\Parse Statistics:
            \\  Tokens: {}
            \\  Time: {}ms
            \\  Speed: {} tokens/ms
            \\  Errors: {}
            \\  Warnings: {}
            \\  Max depth: {}
            \\  Boundaries: {}
        , .{
            self.total_tokens,
            parse_time_ms,
            tokens_per_ms,
            self.error_count,
            self.warning_count,
            self.max_depth_reached,
            self.boundaries_found,
        });
    }
};

/// Create parse context with default settings
pub fn createDefaultContext(
    allocator: std.mem.Allocator,
    source: []const u8,
    tokens: []const Token,
) ParseContext {
    return ParseContext.init(allocator, source, tokens);
}

/// Create strict parse context (fails on first error)
pub fn createStrictContext(
    allocator: std.mem.Allocator,
    source: []const u8,
    tokens: []const Token,
) ParseContext {
    var context = ParseContext.init(allocator, source, tokens);
    context.strict_mode = true;
    return context;
}
