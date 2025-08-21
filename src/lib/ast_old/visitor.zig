const std = @import("std");
const Node = @import("node.zig").Node;

/// Visitor pattern for AST traversal
pub const Visitor = struct {
    /// Visit a node and return whether to continue traversal
    /// Return true to continue visiting children, false to skip
    visitFn: *const fn (node: *const Node, context: *anyopaque) bool,

    /// Optional function called when leaving a node (post-order)
    leaveFn: ?*const fn (node: *const Node, context: *anyopaque) void,

    /// Context data passed to visit functions
    context: *anyopaque,

    const Self = @This();

    /// Create a visitor with visit and optional leave functions
    pub fn init(
        visitFn: *const fn (node: *const Node, context: *anyopaque) bool,
        leaveFn: ?*const fn (node: *const Node, context: *anyopaque) void,
        context: *anyopaque,
    ) Self {
        return .{
            .visitFn = visitFn,
            .leaveFn = leaveFn,
            .context = context,
        };
    }

    /// Visit a node and its children recursively
    pub fn visit(self: Self, node: *const Node) void {
        // Pre-order visit
        const continue_traversal = self.visitFn(node, self.context);

        // Visit children if requested
        if (continue_traversal) {
            for (node.children) |*child| {
                self.visit(child);
            }
        }

        // Post-order visit if provided
        if (self.leaveFn) |leaveFn| {
            leaveFn(node, self.context);
        }
    }
};

/// Simple visitor that just calls a function on each node
pub fn simpleVisit(node: *const Node, visitFn: *const fn (node: *const Node) void) void {
    const Context = struct {
        fn visit(n: *const Node, ctx: *anyopaque) bool {
            const fn_ptr: *const fn (node: *const Node) void = @ptrCast(@alignCast(ctx));
            fn_ptr(n);
            return true;
        }
    };

    var context = visitFn;
    const visitor = Visitor.init(Context.visit, null, @ptrCast(&context));
    visitor.visit(node);
}

/// Find the first node matching a predicate
pub fn findFirst(node: *const Node, predicate: *const fn (node: *const Node) bool) ?*const Node {
    const Context = struct {
        predicate: *const fn (node: *const Node) bool,
        result: ?*const Node,

        fn visit(n: *const Node, ctx: *anyopaque) bool {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            if (self.predicate(n)) {
                self.result = n;
                return false; // Stop traversal
            }
            return true; // Continue traversal
        }
    };

    var context = Context{
        .predicate = predicate,
        .result = null,
    };

    const visitor = Visitor.init(Context.visit, null, &context);
    visitor.visit(node);

    return context.result;
}

/// Find all nodes matching a predicate
pub fn findAll(
    allocator: std.mem.Allocator,
    node: *const Node,
    predicate: *const fn (node: *const Node) bool,
) ![]const Node {
    const Context = struct {
        predicate: *const fn (node: *const Node) bool,
        results: std.ArrayList(*const Node),

        fn visit(n: *const Node, ctx: *anyopaque) bool {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            if (self.predicate(n)) {
                self.results.append(n) catch {};
            }
            return true; // Continue traversal
        }
    };

    var context = Context{
        .predicate = predicate,
        .results = std.ArrayList(*const Node).init(allocator),
    };
    defer context.results.deinit();

    const visitor = Visitor.init(Context.visit, null, &context);
    visitor.visit(node);

    // Convert pointer list to value list
    var result = std.ArrayList(Node).init(allocator);
    for (context.results.items) |node_ptr| {
        try result.append(node_ptr.*);
    }

    return result.toOwnedSlice();
}

/// Count nodes matching a predicate
pub fn count(node: *const Node, predicate: *const fn (node: *const Node) bool) usize {
    const Context = struct {
        predicate: *const fn (node: *const Node) bool,
        count: usize,

        fn visit(n: *const Node, ctx: *anyopaque) bool {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            if (self.predicate(n)) {
                self.count += 1;
            }
            return true; // Continue traversal
        }
    };

    var context = Context{
        .predicate = predicate,
        .count = 0,
    };

    const visitor = Visitor.init(Context.visit, null, &context);
    visitor.visit(node);

    return context.count;
}
