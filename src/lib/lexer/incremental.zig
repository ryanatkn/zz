/// Incremental lexing infrastructure
///
/// Support for incremental updates in editors - optional capability.
const std = @import("std");
const Token = @import("../token/mod.zig").Token;
const Span = @import("../span/mod.zig").Span;

/// Edit operation for incremental updates
pub const Edit = struct {
    /// Range being replaced
    range: Span,
    /// New text replacing the range
    new_text: []const u8,
    /// Byte offset in original text
    offset: u32,
};

/// Delta describing token changes after an edit
pub const TokenDelta = struct {
    /// New tokens in the affected range
    tokens: []const Token,
    /// Range affected by the edit
    affected_range: Span,
    /// Tokens invalidated by the edit
    invalidated: []const Token = &.{},
};

/// Incremental lexer state management
pub const IncrementalState = struct {
    /// Tokens from last full tokenization
    tokens: std.ArrayList(Token),
    /// Source text hash for validation
    source_hash: u64,
    /// Last edit position for optimization
    last_edit: ?Edit = null,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .tokens = std.ArrayList(Token).init(allocator),
            .source_hash = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        self.tokens.deinit();
    }

    /// Apply an edit and return affected tokens
    pub fn applyEdit(self: *Self, edit: Edit, retokenizeFn: anytype) !TokenDelta {
        // Find tokens affected by the edit
        const start_idx = self.findTokenIndex(edit.range.start);
        const end_idx = self.findTokenIndex(edit.range.end);

        // Context variables for Phase 2B implementation
        // Currently unused but will be needed for context-aware retokenization
        _ = if (start_idx > 0) start_idx - 1 else 0;
        _ = @min(end_idx + 1, self.tokens.items.len);

        // Get new tokens for the region
        const new_tokens = try retokenizeFn(edit.new_text);

        // Build delta
        return TokenDelta{
            .tokens = new_tokens,
            .affected_range = edit.range,
            .invalidated = self.tokens.items[start_idx..end_idx],
        };
    }

    fn findTokenIndex(self: *Self, offset: u32) usize {
        // Binary search for token containing offset
        var left: usize = 0;
        var right = self.tokens.items.len;

        while (left < right) {
            const mid = (left + right) / 2;
            const token = self.tokens.items[mid];

            if (token.span.start <= offset and offset < token.span.end) {
                return mid;
            } else if (offset < token.span.start) {
                right = mid;
            } else {
                left = mid + 1;
            }
        }

        return left;
    }
};
