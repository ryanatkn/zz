/// Error recovery strategies for robust parsing
///
/// Provides strategies to recover from parse errors and continue parsing.
const std = @import("std");
const Token = @import("../token/token.zig").Token;
const TokenKind = @import("../token/token.zig").TokenKind;

/// Recovery strategies
pub const RecoveryStrategy = enum {
    /// Skip tokens until a synchronization point
    skip_until_sync,
    /// Insert missing token
    insert_token,
    /// Delete unexpected token
    delete_token,
    /// Panic mode - skip until delimiter
    panic_mode,
    /// Try alternative production
    try_alternative,
};

/// Recovery context
pub const RecoveryContext = struct {
    tokens: []const Token,
    current: usize,
    sync_tokens: []const TokenKind,
    max_lookahead: usize = 5,

    const Self = @This();

    /// Find next synchronization point
    pub fn findSyncPoint(self: *Self) ?usize {
        var i = self.current;
        while (i < self.tokens.len) : (i += 1) {
            const token = self.tokens[i];
            for (self.sync_tokens) |sync| {
                if (token.kind == sync) {
                    return i;
                }
            }
        }
        return null;
    }

    /// Skip to next sync point
    pub fn skipToSync(self: *Self) void {
        if (self.findSyncPoint()) |sync_pos| {
            self.current = sync_pos;
        } else {
            self.current = self.tokens.len;
        }
    }

    /// Check if token could be inserted
    pub fn canInsert(self: *Self, kind: TokenKind) bool {
        // Check if inserting this token would make sense
        if (self.current >= self.tokens.len) return false;

        const next = self.tokens[self.current];

        // Common cases where insertion makes sense
        switch (kind) {
            .semicolon => {
                // Insert semicolon before newline or closing brace
                return next.kind == .newline or next.kind == .right_brace;
            },
            .comma => {
                // Insert comma in lists
                return next.kind == .identifier or next.kind == .string;
            },
            .right_paren, .right_brace, .right_bracket => {
                // Insert closing delimiter
                return true;
            },
            else => return false,
        }
    }

    /// Check if current token can be deleted
    pub fn canDelete(self: *Self) bool {
        if (self.current >= self.tokens.len) return false;

        const token = self.tokens[self.current];

        // Tokens that are often extraneous
        switch (token.kind) {
            .comma, .semicolon => {
                // Extra punctuation
                if (self.current + 1 < self.tokens.len) {
                    const next = self.tokens[self.current + 1];
                    return next.kind == .comma or next.kind == .semicolon or
                        next.kind == .right_brace or next.kind == .right_bracket;
                }
            },
            else => {},
        }

        return false;
    }
};

/// Recovery point for backtracking
pub const RecoveryPoint = struct {
    position: usize,
    error_count: usize,
    strategy: RecoveryStrategy,
};

/// Error recovery manager
pub const ErrorRecovery = struct {
    allocator: std.mem.Allocator,
    recovery_points: std.ArrayList(RecoveryPoint),
    sync_tokens: []const TokenKind,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .recovery_points = std.ArrayList(RecoveryPoint).init(allocator),
            .sync_tokens = &.{
                .semicolon,
                .right_brace,
                .right_bracket,
                .right_paren,
                .keyword, // Any keyword can be sync point
            },
        };
    }

    pub fn deinit(self: *Self) void {
        self.recovery_points.deinit();
    }

    /// Add recovery point
    pub fn addRecoveryPoint(self: *Self, point: RecoveryPoint) !void {
        try self.recovery_points.append(point);
    }

    /// Get best recovery strategy
    pub fn getBestStrategy(self: *Self, context: RecoveryContext) RecoveryStrategy {
        _ = self;

        // Try strategies in order of preference

        // 1. Can we delete current token?
        var ctx = context;
        if (ctx.canDelete()) {
            return .delete_token;
        }

        // 2. Can we insert a missing token?
        const common_missing = [_]TokenKind{ .semicolon, .comma, .right_paren, .right_brace };
        for (common_missing) |kind| {
            if (ctx.canInsert(kind)) {
                return .insert_token;
            }
        }

        // 3. Skip to sync point
        if (ctx.findSyncPoint() != null) {
            return .skip_until_sync;
        }

        // 4. Panic mode as last resort
        return .panic_mode;
    }

    /// Apply recovery strategy
    pub fn applyStrategy(
        self: *Self,
        strategy: RecoveryStrategy,
        context: *RecoveryContext,
    ) void {
        _ = self;

        switch (strategy) {
            .skip_until_sync => context.skipToSync(),
            .delete_token => context.current += 1,
            .insert_token => {}, // Parser handles insertion
            .panic_mode => {
                // Skip until delimiter or EOF
                while (context.current < context.tokens.len) {
                    const token = context.tokens[context.current];
                    if (token.kind == .semicolon or
                        token.kind == .right_brace or
                        token.kind == .eof)
                    {
                        break;
                    }
                    context.current += 1;
                }
            },
            .try_alternative => {}, // Parser handles alternatives
        }
    }
};

/// Common synchronization tokens for different contexts
pub const SyncTokens = struct {
    pub const statement = [_]TokenKind{
        .semicolon,
        .keyword,
        .right_brace,
    };

    pub const expression = [_]TokenKind{
        .semicolon,
        .comma,
        .right_paren,
        .right_bracket,
        .right_brace,
    };

    pub const declaration = [_]TokenKind{
        .keyword,
        .identifier,
        .right_brace,
    };
};
