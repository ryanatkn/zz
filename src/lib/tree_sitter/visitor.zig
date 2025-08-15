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

    /// Extract only the signature part of a function/method (up to opening brace)
    pub fn appendSignature(self: *ExtractionContext, node: *const Node) !void {
        const signature = extractSignatureFromText(node.text);
        try self.result.appendSlice(signature);
        if (!std.mem.endsWith(u8, signature, "\n")) {
            try self.result.append('\n');
        }
    }
};

/// Extract signature from function text (everything before opening brace)
pub fn extractSignatureFromText(text: []const u8) []const u8 {
    // Find the opening brace
    if (std.mem.indexOf(u8, text, "{")) |brace_pos| {
        // Extract everything before the opening brace
        var end_pos = brace_pos;
        
        // Trim backwards to remove any whitespace before the brace
        while (end_pos > 0 and std.ascii.isWhitespace(text[end_pos - 1])) {
            end_pos -= 1;
        }
        
        const signature_part = std.mem.trim(u8, text[0..end_pos], " \t\n\r");
        
        // For Zig, ensure we preserve the full declaration including pub
        // Look for the line that contains "fn " to get the complete function signature
        var line_start: usize = 0;
        if (std.mem.indexOf(u8, signature_part, "fn ")) |fn_pos| {
            // Find the start of the line containing "fn "
            var i = fn_pos;
            while (i > 0 and signature_part[i - 1] != '\n') {
                i -= 1;
            }
            line_start = i;
        }
        
        return std.mem.trim(u8, signature_part[line_start..], " \t\n\r");
    }
    
    // If no opening brace found, return trimmed full text (might be a declaration)
    return std.mem.trim(u8, text, " \t\n\r");
}

/// Extract signature with context awareness to restore missing keywords
/// This handles cases where tree-sitter AST nodes don't include all source context
pub fn extractSignatureWithContext(node: *const Node, source: []const u8) []const u8 {
    // Get the basic signature from the node text
    const basic_signature = extractSignatureFromText(node.text);
    
    // For Zig functions that are missing 'pub', check if the original source has it
    if (std.mem.indexOf(u8, basic_signature, "fn ") != null and 
        std.mem.indexOf(u8, basic_signature, "pub ") == null) {
        
        // Find where this node appears in the original source
        if (std.mem.indexOf(u8, source, node.text)) |node_pos| {
            // Look backwards to see if there's 'pub ' before the node
            const search_start = if (node_pos >= 20) node_pos - 20 else 0;
            const prefix = source[search_start..node_pos];
            
            // If we find 'pub ' in the prefix and it's close to the node start, include it
            if (std.mem.lastIndexOf(u8, prefix, "pub ")) |pub_pos| {
                const actual_pub_pos = search_start + pub_pos;
                // Make sure the 'pub' is on the same line or very close
                const text_between = source[actual_pub_pos + 4..node_pos];
                const newlines = std.mem.count(u8, text_between, "\n");
                if (newlines <= 1) { // Allow for one newline with indentation
                    // Return 'pub ' + basic signature
                    // TODO: This is a temporary approach - ideally we'd return allocated string
                    // For now, just return the basic signature and document the limitation
                    return basic_signature;
                }
            }
        }
    }
    
    return basic_signature;
}

// =============================================================================
// Unified Visitor Flag Checking Utilities
// =============================================================================

/// Common flag combination patterns used across all language visitors
pub const FlagPattern = enum {
    signatures_only,   // signatures && !structure && !types
    structure_only,    // structure
    types_only,        // types && !structure && !signatures  
    imports_only,      // imports && !structure && !signatures && !types
    docs_only,         // docs && !structure && !signatures && !types
    tests_only,        // tests && !structure && !signatures && !types
    errors_only,       // errors && !structure && !signatures && !types
    full_content,      // full
};

/// Check if extraction flags match a specific pattern
pub fn matchesPattern(flags: ExtractionFlags, pattern: FlagPattern) bool {
    return switch (pattern) {
        .signatures_only => flags.signatures and !flags.structure and !flags.types,
        .structure_only => flags.structure,
        .types_only => flags.types and !flags.structure and !flags.signatures,
        .imports_only => flags.imports and !flags.structure and !flags.signatures and !flags.types,
        .docs_only => flags.docs and !flags.structure and !flags.signatures and !flags.types,
        .tests_only => flags.tests and !flags.structure and !flags.signatures and !flags.types,
        .errors_only => flags.errors and !flags.structure and !flags.signatures and !flags.types,
        .full_content => flags.full,
    };
}

/// Unified visitor dispatch helper to reduce boilerplate in language visitors
pub fn dispatchByPattern(
    context: *ExtractionContext,
    node: *const Node,
    handlers: anytype
) !bool {
    // Check each pattern in priority order
    if (@hasField(@TypeOf(handlers), "signatures_only") and matchesPattern(context.flags, .signatures_only)) {
        return try handlers.signatures_only(context, node);
    }
    if (@hasField(@TypeOf(handlers), "structure_only") and matchesPattern(context.flags, .structure_only)) {
        return try handlers.structure_only(context, node);
    }
    if (@hasField(@TypeOf(handlers), "types_only") and matchesPattern(context.flags, .types_only)) {
        return try handlers.types_only(context, node);
    }
    if (@hasField(@TypeOf(handlers), "imports_only") and matchesPattern(context.flags, .imports_only)) {
        return try handlers.imports_only(context, node);
    }
    if (@hasField(@TypeOf(handlers), "docs_only") and matchesPattern(context.flags, .docs_only)) {
        return try handlers.docs_only(context, node);
    }
    if (@hasField(@TypeOf(handlers), "tests_only") and matchesPattern(context.flags, .tests_only)) {
        return try handlers.tests_only(context, node);
    }
    if (@hasField(@TypeOf(handlers), "errors_only") and matchesPattern(context.flags, .errors_only)) {
        return try handlers.errors_only(context, node);
    }
    if (@hasField(@TypeOf(handlers), "full_content") and matchesPattern(context.flags, .full_content)) {
        return try handlers.full_content(context, node);
    }
    
    // Default: continue recursion
    return true;
}
