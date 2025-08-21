/// Optimization transforms
///
/// Transforms for optimizing code structure and performance.
const std = @import("std");
const Token = @import("../token/token.zig").Token;
const AST = @import("../ast/node.zig").AST;

/// Optimization options
pub const OptimizeOptions = struct {
    remove_dead_code: bool = true,
    inline_constants: bool = true,
    simplify_expressions: bool = true,
    merge_declarations: bool = false,
    minify: bool = false,
};

/// Token stream optimizer
pub const TokenOptimizer = struct {
    allocator: std.mem.Allocator,
    options: OptimizeOptions,
    output: std.ArrayList(Token),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, options: OptimizeOptions) Self {
        return .{
            .allocator = allocator,
            .options = options,
            .output = std.ArrayList(Token).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.output.deinit();
    }

    /// Optimize token stream
    pub fn optimize(self: *Self, tokens: []const Token) ![]const Token {
        self.output.clearRetainingCapacity();

        var i: usize = 0;
        while (i < tokens.len) : (i += 1) {
            const token = tokens[i];

            // Skip whitespace if minifying
            if (self.options.minify) {
                if (token.kind == .whitespace or token.kind == .newline) {
                    if (!self.isSignificantWhitespace(tokens, i)) {
                        continue;
                    }
                }
            }

            // Skip comments if minifying
            if (self.options.minify and token.kind == .comment) {
                continue;
            }

            // Remove consecutive semicolons
            if (token.kind == .semicolon and self.output.items.len > 0) {
                if (self.output.items[self.output.items.len - 1].kind == .semicolon) {
                    continue;
                }
            }

            try self.output.append(token);
        }

        return self.output.items;
    }

    fn isSignificantWhitespace(self: *Self, tokens: []const Token, index: usize) bool {
        _ = self;

        // Check if whitespace is needed to separate tokens
        if (index == 0 or index >= tokens.len - 1) return false;

        const prev = tokens[index - 1];
        const next = tokens[index + 1];

        // Need space between identifiers/keywords
        if ((prev.kind == .identifier or prev.kind == .keyword) and
            (next.kind == .identifier or next.kind == .keyword))
        {
            return true;
        }

        return false;
    }
};

/// AST optimizer
pub const ASTOptimizer = struct {
    allocator: std.mem.Allocator,
    options: OptimizeOptions,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, options: OptimizeOptions) Self {
        return .{
            .allocator = allocator,
            .options = options,
        };
    }

    /// Optimize AST
    pub fn optimize(self: *Self, ast: *AST) !void {
        if (self.options.remove_dead_code) {
            try self.removeDeadCode(ast);
        }

        if (self.options.inline_constants) {
            try self.inlineConstants(ast);
        }

        if (self.options.simplify_expressions) {
            try self.simplifyExpressions(ast);
        }
    }

    fn removeDeadCode(self: *Self, ast: *AST) !void {
        _ = self;
        _ = ast;
        // TODO: Implement dead code removal
    }

    fn inlineConstants(self: *Self, ast: *AST) !void {
        _ = self;
        _ = ast;
        // TODO: Implement constant inlining
    }

    fn simplifyExpressions(self: *Self, ast: *AST) !void {
        _ = self;
        _ = ast;
        // TODO: Implement expression simplification
    }
};

/// Minification transform
pub const Minifier = struct {
    allocator: std.mem.Allocator,
    rename_locals: bool = true,
    remove_whitespace: bool = true,
    remove_comments: bool = true,
    shorten_names: bool = true,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
        };
    }

    /// Minify tokens
    pub fn minify(self: *Self, tokens: []const Token) ![]const Token {
        var optimizer = TokenOptimizer.init(self.allocator, .{
            .minify = true,
            .remove_dead_code = false,
            .inline_constants = false,
            .simplify_expressions = false,
            .merge_declarations = false,
        });
        defer optimizer.deinit();

        return optimizer.optimize(tokens);
    }
};
