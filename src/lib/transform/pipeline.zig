/// Transform pipeline infrastructure
///
/// Composable transformations for progressive data enrichment.
const std = @import("std");
const Token = @import("../token/token.zig").Token;
const StreamToken = @import("../token/stream_token.zig").StreamToken;
const Fact = @import("../fact/fact.zig").Fact;

/// Transform stage interface
pub const Transform = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    const VTable = struct {
        transformFn: *const fn (ptr: *anyopaque, input: anytype, allocator: std.mem.Allocator) anyerror!anyopaque,
        deinitFn: *const fn (ptr: *anyopaque) void,
        nameFn: *const fn (ptr: *anyopaque) []const u8,
    };

    pub fn transform(self: Transform, input: anytype, allocator: std.mem.Allocator) !anyopaque {
        return self.vtable.transformFn(self.ptr, input, allocator);
    }

    pub fn deinit(self: Transform) void {
        self.vtable.deinitFn(self.ptr);
    }

    pub fn name(self: Transform) []const u8 {
        return self.vtable.nameFn(self.ptr);
    }
};

/// Pipeline of transforms
pub const Pipeline = struct {
    allocator: std.mem.Allocator,
    transforms: std.ArrayList(Transform),
    stats: PipelineStats = .{},

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .transforms = std.ArrayList(Transform).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.transforms.items) |transform| {
            transform.deinit();
        }
        self.transforms.deinit();
    }

    /// Add transform to pipeline
    pub fn add(self: *Self, transform: Transform) !void {
        try self.transforms.append(transform);
    }

    /// Execute pipeline on input
    pub fn execute(self: *Self, input: anytype) !anyopaque {
        var current = input;
        const start_time = std.time.nanoTimestamp();

        for (self.transforms.items) |transform| {
            const stage_start = std.time.nanoTimestamp();
            current = try transform.transform(current, self.allocator);
            const stage_time = std.time.nanoTimestamp() - stage_start;

            self.stats.total_transforms += 1;
            self.stats.total_time_ns += @intCast(stage_time);
        }

        self.stats.pipeline_time_ns = @intCast(std.time.nanoTimestamp() - start_time);
        return current;
    }

    /// Get pipeline statistics
    pub fn getStats(self: *Self) PipelineStats {
        return self.stats;
    }

    /// Clear pipeline
    pub fn clear(self: *Self) void {
        for (self.transforms.items) |transform| {
            transform.deinit();
        }
        self.transforms.clearRetainingCapacity();
        self.stats = .{};
    }
};

/// Pipeline statistics
pub const PipelineStats = struct {
    total_transforms: usize = 0,
    total_time_ns: u64 = 0,
    pipeline_time_ns: u64 = 0,

    pub fn averageTransformTime(self: PipelineStats) u64 {
        if (self.total_transforms == 0) return 0;
        return self.total_time_ns / self.total_transforms;
    }
};

/// Common transform: Tokens to Facts
pub const TokenToFactTransform = struct {
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{ .allocator = allocator };
    }

    pub fn transform(self: *Self, tokens: []const Token) ![]Fact {
        var facts = std.ArrayList(Fact).init(self.allocator);

        for (tokens) |token| {
            if (shouldGenerateFact(token)) {
                try facts.append(Fact{
                    .subject = token.span.start,
                    .predicate = @intFromEnum(token.kind),
                    .object = token.span.end,
                });
            }
        }

        return facts.toOwnedSlice();
    }

    fn shouldGenerateFact(token: Token) bool {
        return switch (token.kind) {
            .identifier, .keyword, .string, .number => true,
            .whitespace, .newline => false,
            else => true,
        };
    }

    pub fn toInterface(self: *Self) Transform {
        const gen = struct {
            fn transformImpl(ptr: *anyopaque, input: anytype, allocator: std.mem.Allocator) anyerror!anyopaque {
                _ = allocator;
                const s: *Self = @ptrCast(@alignCast(ptr));
                const tokens = @as([]const Token, input);
                return @ptrCast(try s.transform(tokens));
            }

            fn deinitImpl(ptr: *anyopaque) void {
                _ = ptr;
            }

            fn nameImpl(ptr: *anyopaque) []const u8 {
                _ = ptr;
                return "TokenToFact";
            }

            const vtable = Transform.VTable{
                .transformFn = transformImpl,
                .deinitFn = deinitImpl,
                .nameFn = nameImpl,
            };
        };

        return .{
            .ptr = self,
            .vtable = &gen.vtable,
        };
    }
};

/// Common transform: AST to Facts
pub const ASTToFactTransform = struct {
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{ .allocator = allocator };
    }

    pub fn transform(self: *Self, ast: anytype) ![]Fact {
        var facts = std.ArrayList(Fact).init(self.allocator);

        // Walk AST and generate semantic facts
        try self.walkNode(ast.root, &facts);

        return facts.toOwnedSlice();
    }

    fn walkNode(self: *Self, node: anytype, facts: *std.ArrayList(Fact)) !void {
        _ = self;
        _ = node;
        _ = facts;
        // TODO: Implement AST walking
    }
};
