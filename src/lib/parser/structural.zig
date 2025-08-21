/// Structural analysis - Fast boundary detection without full parsing
///
/// Detects structural boundaries (functions, classes, blocks) for navigation
/// and folding without building a complete AST.
const std = @import("std");
const Token = @import("../token/token.zig").Token;
const Span = @import("../span/span.zig").Span;

/// Structural boundary types
pub const BoundaryKind = enum {
    function,
    class,
    interface,
    struct_type,
    enum_type,
    block,
    array,
    object,
    namespace,
    module,
    comment_block,
};

/// A structural boundary in the code
pub const Boundary = struct {
    kind: BoundaryKind,
    span: Span,
    depth: u16,
    name: ?[]const u8 = null,
    parent: ?*Boundary = null,
    children: std.ArrayList(*Boundary),

    pub fn init(allocator: std.mem.Allocator, kind: BoundaryKind, span: Span, depth: u16) !*Boundary {
        const boundary = try allocator.create(Boundary);
        boundary.* = .{
            .kind = kind,
            .span = span,
            .depth = depth,
            .children = std.ArrayList(*Boundary).init(allocator),
        };
        return boundary;
    }

    pub fn deinit(self: *Boundary, allocator: std.mem.Allocator) void {
        for (self.children.items) |child| {
            child.deinit(allocator);
        }
        self.children.deinit();
        allocator.destroy(self);
    }

    pub fn addChild(self: *Boundary, child: *Boundary) !void {
        child.parent = self;
        try self.children.append(child);
    }
};

/// Fast structural analyzer
pub const StructuralAnalyzer = struct {
    allocator: std.mem.Allocator,
    boundaries: std.ArrayList(*Boundary),
    stack: std.ArrayList(*Boundary),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .boundaries = std.ArrayList(*Boundary).init(allocator),
            .stack = std.ArrayList(*Boundary).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.boundaries.items) |boundary| {
            boundary.deinit(self.allocator);
        }
        self.boundaries.deinit();
        self.stack.deinit();
    }

    /// Analyze tokens to find structural boundaries
    pub fn analyze(self: *Self, tokens: []const Token) ![]Boundary {
        self.reset();

        var depth: u16 = 0;
        var i: usize = 0;

        while (i < tokens.len) : (i += 1) {
            const token = tokens[i];

            // Track nesting depth
            switch (token.kind) {
                .left_brace, .left_bracket, .left_paren => {
                    depth += 1;

                    // Check if this starts a boundary
                    if (self.isBoundaryStart(tokens, i)) {
                        const boundary_kind = self.detectBoundaryKind(tokens, i);
                        const span = self.findBoundarySpan(tokens, i);

                        const boundary = try Boundary.init(self.allocator, boundary_kind, span, depth);

                        // Extract name if available
                        boundary.name = self.extractBoundaryName(tokens, i);

                        // Add to hierarchy
                        if (self.stack.items.len > 0) {
                            const parent = self.stack.items[self.stack.items.len - 1];
                            try parent.addChild(boundary);
                        } else {
                            try self.boundaries.append(boundary);
                        }

                        try self.stack.append(boundary);
                    }
                },

                .right_brace, .right_bracket, .right_paren => {
                    if (depth > 0) depth -= 1;

                    // Check if this ends a boundary
                    if (self.stack.items.len > 0) {
                        const current = self.stack.items[self.stack.items.len - 1];
                        if (current.depth == depth + 1) {
                            _ = self.stack.pop();
                        }
                    }
                },

                else => {},
            }
        }

        // Return top-level boundaries
        return self.boundaries.items;
    }

    fn reset(self: *Self) void {
        self.boundaries.clearRetainingCapacity();
        self.stack.clearRetainingCapacity();
    }

    fn isBoundaryStart(self: *Self, tokens: []const Token, index: usize) bool {
        _ = self;
        if (index == 0) return false;

        const prev = tokens[index - 1];
        const curr = tokens[index];

        // Function/method detection
        if (curr.kind == .left_paren and prev.kind == .identifier) {
            return true;
        }

        // Object/class detection
        if (curr.kind == .left_brace) {
            if (prev.kind == .identifier or prev.kind == .keyword) {
                return true;
            }
        }

        return false;
    }

    fn detectBoundaryKind(self: *Self, tokens: []const Token, index: usize) BoundaryKind {
        _ = self;
        if (index < 2) return .block;

        // Look for keywords before the boundary
        var i = index - 1;
        while (i > 0) : (i -= 1) {
            const token = tokens[i];
            if (token.kind == .keyword) {
                // Map keyword text to boundary kind
                // This would need language-specific logic
                return .function; // Default for now
            }
            if (token.kind == .semicolon or token.kind == .newline) {
                break;
            }
        }

        return .block;
    }

    fn findBoundarySpan(self: *Self, tokens: []const Token, start: usize) Span {
        _ = self;
        const start_token = tokens[start];
        var depth: u32 = 1;
        var i = start + 1;

        while (i < tokens.len) : (i += 1) {
            const token = tokens[i];

            switch (token.kind) {
                .left_brace, .left_bracket, .left_paren => depth += 1,
                .right_brace, .right_bracket, .right_paren => {
                    depth -= 1;
                    if (depth == 0) {
                        return Span{
                            .start = start_token.span.start,
                            .end = token.span.end,
                        };
                    }
                },
                else => {},
            }
        }

        // Unclosed boundary
        return Span{
            .start = start_token.span.start,
            .end = tokens[tokens.len - 1].span.end,
        };
    }

    fn extractBoundaryName(self: *Self, tokens: []const Token, index: usize) ?[]const u8 {
        _ = self;
        if (index == 0) return null;

        const prev = tokens[index - 1];
        if (prev.kind == .identifier) {
            // Would need to extract actual text from token
            return null; // Placeholder
        }

        return null;
    }
};
