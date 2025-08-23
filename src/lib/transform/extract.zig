/// Extraction transforms
///
/// Transforms for extracting information from code (signatures, types, etc).
const std = @import("std");
const StreamToken = @import("../token/stream_token.zig").StreamToken;
const Fact = @import("../fact/fact.zig").Fact;

/// Extraction options
pub const ExtractOptions = struct {
    include_private: bool = false,
    include_docs: bool = true,
    include_types: bool = true,
    include_signatures: bool = true,
    max_depth: u32 = 10,
};

/// Extract signatures from tokens
pub const SignatureExtractor = struct {
    allocator: std.mem.Allocator,
    options: ExtractOptions,
    signatures: std.ArrayList(Signature),

    const Self = @This();

    pub const Signature = struct {
        name: []const u8,
        kind: SignatureKind,
        params: []const Param,
        return_type: ?[]const u8,
        docs: ?[]const u8,
        span: Span,
    };

    pub const SignatureKind = enum {
        function,
        method,
        constructor,
        getter,
        setter,
    };

    pub const Param = struct {
        name: []const u8,
        type: ?[]const u8,
        default: ?[]const u8,
    };

    const Span = @import("../span/span.zig").Span;

    pub fn init(allocator: std.mem.Allocator, options: ExtractOptions) Self {
        return .{
            .allocator = allocator,
            .options = options,
            .signatures = std.ArrayList(Signature).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.signatures.deinit();
    }

    /// Extract signatures from tokens
    pub fn extract(self: *Self, tokens: []const Token) ![]const Signature {
        self.signatures.clearRetainingCapacity();

        var i: usize = 0;
        while (i < tokens.len) : (i += 1) {
            if (self.isFunctionStart(tokens, i)) {
                const sig = try self.extractSignature(tokens, &i);
                if (self.shouldInclude(sig)) {
                    try self.signatures.append(sig);
                }
            }
        }

        return self.signatures.items;
    }

    fn isFunctionStart(self: *Self, tokens: []const Token, index: usize) bool {
        _ = self;
        if (index >= tokens.len) return false;

        const token = tokens[index];

        // Look for function keywords
        if (token.kind == .keyword) {
            // Would need to check actual keyword text
            return true;
        }

        // Look for identifier followed by parenthesis
        if (token.kind == .identifier and index + 1 < tokens.len) {
            return tokens[index + 1].kind == .left_paren;
        }

        return false;
    }

    fn extractSignature(self: *Self, tokens: []const Token, index: *usize) !Signature {
        const start = index.*;

        // Extract function name
        const name = "function"; // Placeholder

        // Extract parameters
        var params = std.ArrayList(Param).init(self.allocator);
        defer params.deinit();

        // Skip to parameters
        while (index.* < tokens.len and tokens[index.*].kind != .left_paren) {
            index.* += 1;
        }

        if (index.* < tokens.len) {
            index.* += 1; // Skip left paren

            // Extract params until right paren
            while (index.* < tokens.len and tokens[index.*].kind != .right_paren) {
                // Parse parameter
                // Simplified - would need proper parsing
                index.* += 1;
            }
        }

        // Extract return type if present
        const return_type: ?[]const u8 = null;

        // Extract docs if present
        const docs: ?[]const u8 = null;

        const end = index.*;

        return Signature{
            .name = name,
            .kind = .function,
            .params = try params.toOwnedSlice(),
            .return_type = return_type,
            .docs = docs,
            .span = .{
                .start = tokens[start].span.start,
                .end = if (end > 0) tokens[end - 1].span.end else tokens[start].span.end,
            },
        };
    }

    fn shouldInclude(self: *Self, sig: Signature) bool {
        // Check if should include based on options
        if (!self.options.include_private) {
            // Check if private (would need actual implementation)
            _ = sig;
        }

        return true;
    }
};

/// Extract types from AST
pub const TypeExtractor = struct {
    allocator: std.mem.Allocator,
    options: ExtractOptions,
    types: std.ArrayList(TypeInfo),

    const Self = @This();

    pub const TypeInfo = struct {
        name: []const u8,
        kind: TypeKind,
        fields: []const Field,
        methods: []const Method,
        docs: ?[]const u8,
    };

    pub const TypeKind = enum {
        struct_type,
        enum_type,
        union_type,
        interface_type,
        alias_type,
    };

    pub const Field = struct {
        name: []const u8,
        type: []const u8,
        default: ?[]const u8,
        docs: ?[]const u8,
    };

    pub const Method = struct {
        name: []const u8,
        signature: SignatureExtractor.Signature,
    };

    pub fn init(allocator: std.mem.Allocator, options: ExtractOptions) Self {
        return .{
            .allocator = allocator,
            .options = options,
            .types = std.ArrayList(TypeInfo).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.types.deinit();
    }

    /// Extract types from AST (generic over AST type)
    pub fn extract(self: *Self, ast: anytype) ![]const TypeInfo {
        _ = ast;
        self.types.clearRetainingCapacity();

        // Walk AST and extract type definitions
        // TODO: Implement AST walking

        return self.types.items;
    }
};

/// Extract facts for semantic analysis
pub const FactExtractor = struct {
    allocator: std.mem.Allocator,
    facts: std.ArrayList(Fact),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .facts = std.ArrayList(Fact).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.facts.deinit();
    }

    /// Extract facts from tokens
    pub fn extractFromTokens(self: *Self, tokens: []const Token) ![]const Fact {
        self.facts.clearRetainingCapacity();

        for (tokens) |token| {
            if (self.shouldExtractFact(token)) {
                try self.facts.append(Fact{
                    .subject = token.span.start,
                    .predicate = @intFromEnum(token.kind),
                    .object = token.span.end,
                });
            }
        }

        return self.facts.items;
    }

    fn shouldExtractFact(self: *Self, token: Token) bool {
        _ = self;
        return switch (token.kind) {
            .identifier, .keyword, .string, .number => true,
            .whitespace, .newline, .comment => false,
            else => true,
        };
    }
};
