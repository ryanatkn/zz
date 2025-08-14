const std = @import("std");
const Node = @import("node.zig").Node;
const ExtractionFlags = @import("../language/flags.zig").ExtractionFlags;

/// Visitor pattern for AST traversal
pub const Visitor = struct {
    /// Function type for visiting nodes
    pub const VisitFn = *const fn (node: *const Node, context: *anyopaque) anyerror!void;

    /// Visit a node and its children
    pub fn visit(
        node: *const Node,
        source: []const u8,
        visitor_fn: VisitFn,
        context: *anyopaque,
    ) !void {
        // Visit current node
        try visitor_fn(node, context);

        // Visit children
        const count = node.childCount();
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            if (node.child(i, source)) |child_node| {
                var child = child_node;
                try visit(&child, source, visitor_fn, context);
            }
        }
    }

    /// Helper to check if node type should be extracted based on flags
    pub fn shouldExtract(node_type: []const u8, flags: ExtractionFlags) bool {
        // Functions
        if (std.mem.eql(u8, node_type, "function_definition") or
            std.mem.eql(u8, node_type, "function_declaration") or
            std.mem.eql(u8, node_type, "method_definition"))
        {
            return flags.signatures;
        }

        // Types
        if (std.mem.eql(u8, node_type, "struct") or
            std.mem.eql(u8, node_type, "class") or
            std.mem.eql(u8, node_type, "interface") or
            std.mem.eql(u8, node_type, "enum"))
        {
            return flags.types;
        }

        // Imports
        if (std.mem.eql(u8, node_type, "import_statement") or
            std.mem.eql(u8, node_type, "import"))
        {
            return flags.imports;
        }

        // Tests
        if (std.mem.eql(u8, node_type, "test_decl") or
            std.mem.startsWith(u8, node_type, "test_"))
        {
            return flags.tests;
        }

        // Comments/docs
        if (std.mem.eql(u8, node_type, "comment") or
            std.mem.eql(u8, node_type, "doc_comment"))
        {
            return flags.docs;
        }

        return flags.full;
    }
};

/// Unified AST walker for all parsers
pub const AstWalker = struct {
    pub const WalkContext = struct {
        allocator: std.mem.Allocator,
        result: *std.ArrayList(u8),
        flags: ExtractionFlags,
        source: []const u8,
    };

    pub fn walkNodeWithVisitor(allocator: std.mem.Allocator, root: *const Node, source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8), visitor_fn: fn (*WalkContext, *const Node) anyerror!void) !void {
        var context = WalkContext{
            .allocator = allocator,
            .result = result,
            .flags = flags,
            .source = source,
        };

        try walkNodeRecursive(&context, root, visitor_fn);
    }

    fn walkNodeRecursive(context: *WalkContext, node: *const Node, visitor_fn: fn (*WalkContext, *const Node) anyerror!void) !void {
        try visitor_fn(context, node);

        // Recurse into children
        const count = node.childCount();
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            if (node.child(i, context.source)) |child| {
                var child_node = child;
                try walkNodeRecursive(context, &child_node, visitor_fn);
            }
        }
    }

    pub const GenericVisitor = struct {
        pub fn visitNode(context: *WalkContext, node: *const Node) !void {
            // Default implementation - extract text if node matches flags
            if (shouldExtractNode(context.flags, node.kind)) {
                try context.result.appendSlice(node.text);
                try context.result.append('\n');
            }
        }
    };

    fn shouldExtractNode(flags: ExtractionFlags, kind: []const u8) bool {
        if (flags.full) return true;

        if (flags.signatures and (std.mem.eql(u8, kind, "function") or
            std.mem.eql(u8, kind, "method")))
        {
            return true;
        }

        if (flags.types and (std.mem.eql(u8, kind, "class") or
            std.mem.eql(u8, kind, "interface") or
            std.mem.eql(u8, kind, "struct")))
        {
            return true;
        }

        if (flags.imports and std.mem.eql(u8, kind, "import")) {
            return true;
        }

        if (flags.tests and std.mem.eql(u8, kind, "test")) {
            return true;
        }

        return false;
    }
};

/// Context for extraction operations
pub const ExtractionContext = struct {
    allocator: std.mem.Allocator,
    result: *std.ArrayList(u8),
    flags: ExtractionFlags,
    source: []const u8,

    pub fn appendNode(self: *ExtractionContext, node: *const Node) !void {
        try self.result.appendSlice(node.text);
        if (!std.mem.endsWith(u8, node.text, "\n")) {
            try self.result.append('\n');
        }
    }

    pub fn appendText(self: *ExtractionContext, text: []const u8) !void {
        try self.result.appendSlice(text);
        if (!std.mem.endsWith(u8, text, "\n")) {
            try self.result.append('\n');
        }
    }
};
