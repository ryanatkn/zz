const std = @import("std");
const ts = @import("tree-sitter");

// Import from the new tree_sitter modules
const tree_sitter_node = @import("../tree_sitter/node.zig");
const tree_sitter_visitor = @import("../tree_sitter/visitor.zig");

// Re-export tree_sitter types for backward compatibility
pub const Node = tree_sitter_node.Node;
pub const Visitor = tree_sitter_visitor.Visitor;
pub const AstWalker = tree_sitter_visitor.AstWalker;
pub const ExtractionContext = tree_sitter_visitor.ExtractionContext;

// Backward compatibility aliases for parser modules
pub const AstNode = Node;
pub const NodeVisitor = Visitor;
pub const VisitResult = void;

// Additional helper for common extraction patterns
pub const ExtractionFlags = @import("../language/flags.zig").ExtractionFlags;

test "Node creation from tree-sitter" {
    // Test that we can create synthetic nodes
    const synthetic_node = Node.synthetic("test", "test content", 0, 12);
    try std.testing.expect(std.mem.eql(u8, synthetic_node.kind, "test"));
    try std.testing.expect(std.mem.eql(u8, synthetic_node.text, "test content"));
    try std.testing.expect(synthetic_node.start_byte == 0);
    try std.testing.expect(synthetic_node.end_byte == 12);
}

test "Visitor shouldExtract" {
    const flags = ExtractionFlags{
        .signatures = true,
        .types = false,
        .imports = false,
        .docs = false,
        .tests = false,
        .full = false,
    };

    try std.testing.expect(Visitor.shouldExtract("function_definition", flags));
    try std.testing.expect(!Visitor.shouldExtract("struct", flags));
    try std.testing.expect(!Visitor.shouldExtract("import_statement", flags));
}