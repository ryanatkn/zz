const std = @import("std");

// ============================================================================
// Core AST Types
// ============================================================================

/// Generic AST node that can represent any parsed structure
pub const Node = @import("node.zig").Node;

/// Alias for Node for compatibility
pub const ASTNode = Node;

/// Visitor pattern for AST traversal
pub const Visitor = @import("visitor.zig").Visitor;

const CommonRules = @import("rules.zig").CommonRules;

/// Walker utilities for tree traversal
pub const Walker = @import("walker.zig").Walker;

// ============================================================================
// Node Creation and Management
// ============================================================================

pub const NodeBuilder = @import("node.zig").NodeBuilder;
pub const NodeType = @import("node.zig").NodeType;

// ============================================================================
// Utility Functions
// ============================================================================

pub const createNode = @import("node.zig").createNode;
pub const createLeafNode = @import("node.zig").createLeafNode;

// ============================================================================
// AST Structure
// ============================================================================

/// Complete AST structure with memory management
pub const AST = struct {
    root: ASTNode,
    allocator: std.mem.Allocator,
    /// Texts allocated during parsing that are owned by this AST
    owned_texts: []const []const u8,
    /// Original source text (optional)
    source: []const u8 = "",

    /// Initialize an empty AST
    pub fn init(allocator: std.mem.Allocator) AST {
        return AST{
            .root = ASTNode{
                .rule_id = @intFromEnum(CommonRules.root),
                .node_type = .root,
                .text = "",
                .start_position = 0,
                .end_position = 0,
                .children = &[_]ASTNode{},
                .attributes = null,
                .parent = null,
            },
            .allocator = allocator,
            .owned_texts = &[_][]const u8{},
            .source = "",
        };
    }

    pub fn deinit(self: *AST) void {
        // Free the AST tree
        self.root.deinit(self.allocator);

        // Free all owned texts allocated during parsing
        for (self.owned_texts) |text| {
            self.allocator.free(text);
        }
        // Only free owned_texts array if it's not the empty slice literal
        if (self.owned_texts.ptr != &[_][]const u8{}) {
            self.allocator.free(self.owned_texts);
        }

        // Free the source text if it was allocated (not empty string literal)
        if (self.source.len > 0 and self.source.ptr != "".ptr) {
            self.allocator.free(self.source);
        }
    }
};

/// Alias for AST compatibility
pub const NodeKind = NodeType;

// ============================================================================
// New AST Infrastructure - Centralized for All Languages
// ============================================================================

/// AST Factory for programmatic construction
pub const ASTFactory = @import("factory.zig").ASTFactory;
pub const createMockAST = @import("factory.zig").createMockAST;
pub const createSimpleObjectAST = @import("factory.zig").createSimpleObjectAST;
pub const createSimpleArrayAST = @import("factory.zig").createSimpleArrayAST;
pub const ASTStructure = @import("factory.zig").ASTStructure;
pub const FieldSpec = @import("factory.zig").FieldSpec;

/// Test utilities for all language modules
pub const ASTTestHelpers = @import("test_helpers.zig").ASTTestHelpers;
pub const createZonAST = @import("test_helpers.zig").ASTTestHelpers.createZonAST;
pub const createSimpleObject = @import("test_helpers.zig").ASTTestHelpers.createSimpleObject;
pub const createSimpleArray = @import("test_helpers.zig").ASTTestHelpers.createSimpleArray;
pub const createStructuredAST = @import("test_helpers.zig").ASTTestHelpers.createStructuredAST;
pub const assertASTEqual = @import("test_helpers.zig").ASTTestHelpers.assertASTEqual;
pub const assertASTStructure = @import("test_helpers.zig").ASTTestHelpers.assertASTStructure;
pub const assertHasChild = @import("test_helpers.zig").ASTTestHelpers.assertHasChild;
pub const assertIsFieldAssignment = @import("test_helpers.zig").ASTTestHelpers.assertIsFieldAssignment;
pub const debugPrintAST = @import("test_helpers.zig").ASTTestHelpers.debugPrintAST;
pub const TestContext = @import("test_helpers.zig").ASTTestHelpers.TestContext;

/// Common AST manipulation utilities
pub const ASTUtils = @import("utils.zig").ASTUtils;
pub const findNodeByPath = @import("utils.zig").findNodeByPath;
pub const collectNodes = @import("utils.zig").collectNodes;
pub const collectNodesByRule = @import("utils.zig").collectNodesByRule;
pub const transformAST = @import("utils.zig").transformAST;
pub const cloneAST = @import("utils.zig").cloneAST;
pub const cloneNode = @import("utils.zig").cloneNode;
pub const validateStructure = @import("utils.zig").validateStructure;
pub const extractFieldNames = @import("utils.zig").extractFieldNames;
pub const getFieldValue = @import("utils.zig").getFieldValue;
pub const isLiteralOfType = @import("utils.zig").isLiteralOfType;
pub const extractLiteralValue = @import("utils.zig").extractLiteralValue;
pub const getASTStatistics = @import("utils.zig").getASTStatistics;
pub const ASTSchema = @import("utils.zig").ASTSchema;
pub const ValidationResult = @import("utils.zig").ValidationResult;
pub const ASTStatistics = @import("utils.zig").ASTStatistics;
pub const Predicates = @import("utils.zig").Predicates;

/// Fluent builder DSL for AST construction
pub const ASTBuilder = @import("builder.zig").ASTBuilder;
pub const ObjectBuilder = @import("builder.zig").ObjectBuilder;
pub const ArrayBuilder = @import("builder.zig").ArrayBuilder;
pub const quickObject = @import("builder.zig").quickObject;
pub const quickArray = @import("builder.zig").quickArray;
pub const QuickField = @import("builder.zig").QuickField;
pub const QuickValue = @import("builder.zig").QuickValue;
