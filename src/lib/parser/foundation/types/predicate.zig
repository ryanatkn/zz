const std = @import("std");

/// Predicates define what kind of information a fact conveys
/// Used throughout the fact stream system to categorize and query facts
pub const Predicate = union(enum) {
    // =====================================================
    // Lexical Facts - From Layer 0 (Tokenizer)
    // =====================================================

    /// Token has a specific kind (identifier, keyword, operator, etc.)
    is_token: TokenKind,

    /// Token contains specific literal text
    has_text: []const u8,

    /// Token is at a specific bracket depth level
    bracket_depth: u16,

    /// Token represents an opening delimiter
    is_open_delimiter,

    /// Token represents a closing delimiter
    is_close_delimiter,

    /// Token is whitespace or comment (trivia)
    is_trivia,

    // =====================================================
    // Structural Facts - From Layer 1 (Structural Parser)
    // =====================================================

    /// Span represents a structural boundary (function, class, block)
    is_boundary: BoundaryKind,

    /// Span represents an error recovery region
    is_error_region,

    /// Span can be folded in editor
    is_foldable,

    /// Span is indented at a specific level
    indent_level: u16,

    // =====================================================
    // Syntactic Facts - From Layer 2 (Detailed Parser)
    // =====================================================

    /// Span represents a specific AST node type
    is_node: NodeKind,

    /// Fact subject has another fact as a child
    has_child: FactId,

    /// Fact subject has another fact as a parent
    has_parent: FactId,

    /// Fact subject comes before another fact in source order
    precedes: FactId,

    /// Fact subject comes after another fact in source order
    follows: FactId,

    /// Node has a specific named field
    has_field: []const u8,

    // =====================================================
    // Semantic Facts - From Analysis Layers
    // =====================================================

    /// Span binds a symbol (declaration)
    binds_symbol: SymbolId,

    /// Span references a symbol (usage)
    references_symbol: SymbolId,

    /// Span has a specific type
    has_type: TypeId,

    /// Span contains a specific value
    has_value: Value,

    /// Symbol is defined in a specific scope
    in_scope: ScopeId,

    // =====================================================
    // Additional semantic predicates
    // =====================================================

    /// Span represents a function declaration
    is_function,

    /// Span represents a struct declaration
    is_struct,

    /// Span represents a variable declaration
    is_variable,

    /// Span represents a constant declaration
    is_constant,

    /// Span represents an import statement
    is_import,

    /// Span represents a type definition
    is_type,

    /// Span represents an enum declaration
    is_enum,

    /// Span represents a field declaration
    is_field,

    /// Span represents a parameter
    is_parameter,

    /// Span represents a function call
    is_function_call,

    /// Span represents an identifier
    is_identifier,

    /// Span represents a literal value
    is_literal,

    /// Span represents a block/scope
    is_block,

    /// Span represents an assignment
    is_assignment,

    /// Span represents a binary expression
    is_binary_expression,

    /// Span represents a unary expression
    is_unary_expression,

    /// Span represents an if statement
    is_if_statement,

    /// Span represents a while loop
    is_while_loop,

    /// Span represents a for loop
    is_for_loop,

    /// Span represents a return statement
    is_return_statement,

    /// Span represents a comment
    is_comment,

    /// Span is public/exported
    is_public,

    /// Span is mutable
    is_mutable,

    /// Span is documentation
    is_documentation,

    /// Span has return type
    has_return_type,

    /// Span has complexity measure
    has_complexity,

    /// Span has field count
    has_field_count,

    /// Span has variant count
    has_variant_count,

    /// Span has alias
    has_alias,

    /// Span has argument count
    has_argument_count,

    /// Span has literal type
    has_literal_type,

    /// Span has else clause
    has_else_clause,

    /// Span has return value
    has_return_value,

    // =====================================================
    // Editor Facts - From Editor Integration
    // =====================================================

    /// Span should be highlighted with specific color
    highlight_color: HighlightKind,

    /// Span contains a diagnostic (error, warning)
    has_diagnostic: DiagnosticKind,

    /// Span is currently selected in editor
    is_selected,

    /// Span is visible in current viewport
    is_visible,

    /// Span has been recently modified
    is_dirty,

    // =====================================================
    // Meta Facts - About the fact system itself
    // =====================================================

    /// Fact is derived from another fact (not directly parsed)
    derived_from: FactId,

    /// Fact has a specific confidence level
    confidence: f32,

    /// Fact was generated by a specific parser layer
    from_layer: LayerId,

    /// Fact is part of a speculation
    is_speculative,

    pub fn format(
        self: Predicate,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        switch (self) {
            .is_token => |kind| try writer.print("is_token({s})", .{@tagName(kind)}),
            .has_text => |text| try writer.print("has_text(\"{s}\")", .{text}),
            .bracket_depth => |depth| try writer.print("bracket_depth({d})", .{depth}),
            .is_open_delimiter => try writer.writeAll("is_open_delimiter"),
            .is_close_delimiter => try writer.writeAll("is_close_delimiter"),
            .is_trivia => try writer.writeAll("is_trivia"),
            .is_boundary => |kind| try writer.print("is_boundary({s})", .{@tagName(kind)}),
            .is_error_region => try writer.writeAll("is_error_region"),
            .is_foldable => try writer.writeAll("is_foldable"),
            .indent_level => |level| try writer.print("indent_level({d})", .{level}),
            .is_node => |kind| try writer.print("is_node({s})", .{@tagName(kind)}),
            .has_child => |id| try writer.print("has_child({d})", .{id}),
            .has_parent => |id| try writer.print("has_parent({d})", .{id}),
            .precedes => |id| try writer.print("precedes({d})", .{id}),
            .follows => |id| try writer.print("follows({d})", .{id}),
            .has_field => |field| try writer.print("has_field(\"{s}\")", .{field}),
            .binds_symbol => |id| try writer.print("binds_symbol({d})", .{id}),
            .references_symbol => |id| try writer.print("references_symbol({d})", .{id}),
            .has_type => |id| try writer.print("has_type({d})", .{id}),
            .has_value => |value| try writer.print("has_value({any})", .{value}),
            .in_scope => |id| try writer.print("in_scope({d})", .{id}),
            .highlight_color => |kind| try writer.print("highlight_color({s})", .{@tagName(kind)}),
            .has_diagnostic => |kind| try writer.print("has_diagnostic({s})", .{@tagName(kind)}),
            .is_selected => try writer.writeAll("is_selected"),
            .is_visible => try writer.writeAll("is_visible"),
            .is_dirty => try writer.writeAll("is_dirty"),
            .derived_from => |id| try writer.print("derived_from({d})", .{id}),
            .confidence => |conf| try writer.print("confidence({d:.2})", .{conf}),
            .from_layer => |layer| try writer.print("from_layer({s})", .{@tagName(layer)}),
            .is_speculative => try writer.writeAll("is_speculative"),

            // Additional semantic predicates
            .is_function => try writer.writeAll("is_function"),
            .is_struct => try writer.writeAll("is_struct"),
            .is_variable => try writer.writeAll("is_variable"),
            .is_constant => try writer.writeAll("is_constant"),
            .is_import => try writer.writeAll("is_import"),
            .is_type => try writer.writeAll("is_type"),
            .is_enum => try writer.writeAll("is_enum"),
            .is_field => try writer.writeAll("is_field"),
            .is_parameter => try writer.writeAll("is_parameter"),
            .is_function_call => try writer.writeAll("is_function_call"),
            .is_identifier => try writer.writeAll("is_identifier"),
            .is_literal => try writer.writeAll("is_literal"),
            .is_block => try writer.writeAll("is_block"),
            .is_assignment => try writer.writeAll("is_assignment"),
            .is_binary_expression => try writer.writeAll("is_binary_expression"),
            .is_unary_expression => try writer.writeAll("is_unary_expression"),
            .is_if_statement => try writer.writeAll("is_if_statement"),
            .is_while_loop => try writer.writeAll("is_while_loop"),
            .is_for_loop => try writer.writeAll("is_for_loop"),
            .is_return_statement => try writer.writeAll("is_return_statement"),
            .is_comment => try writer.writeAll("is_comment"),
            .is_public => try writer.writeAll("is_public"),
            .is_mutable => try writer.writeAll("is_mutable"),
            .is_documentation => try writer.writeAll("is_documentation"),
            .has_return_type => try writer.writeAll("has_return_type"),
            .has_complexity => try writer.writeAll("has_complexity"),
            .has_field_count => try writer.writeAll("has_field_count"),
            .has_variant_count => try writer.writeAll("has_variant_count"),
            .has_alias => try writer.writeAll("has_alias"),
            .has_argument_count => try writer.writeAll("has_argument_count"),
            .has_literal_type => try writer.writeAll("has_literal_type"),
            .has_else_clause => try writer.writeAll("has_else_clause"),
            .has_return_value => try writer.writeAll("has_return_value"),
        }
    }

    /// Get the category of this predicate for indexing optimization
    pub fn category(self: Predicate) PredicateCategory {
        return switch (self) {
            .is_token, .has_text, .bracket_depth, .is_open_delimiter, .is_close_delimiter, .is_trivia => .lexical,
            .is_boundary, .is_error_region, .is_foldable, .indent_level => .structural,
            .is_node, .has_child, .has_parent, .precedes, .follows, .has_field => .syntactic,
            .binds_symbol, .references_symbol, .has_type, .has_value, .in_scope, .is_function, .is_struct, .is_variable, .is_constant, .is_import, .is_type, .is_enum, .is_field, .is_parameter, .is_function_call, .is_identifier, .is_literal, .is_block, .is_assignment, .is_binary_expression, .is_unary_expression, .is_if_statement, .is_while_loop, .is_for_loop, .is_return_statement, .is_comment, .is_public, .is_mutable, .is_documentation, .has_return_type, .has_complexity, .has_field_count, .has_variant_count, .has_alias, .has_argument_count, .has_literal_type, .has_else_clause, .has_return_value => .semantic,
            .highlight_color, .has_diagnostic, .is_selected, .is_visible, .is_dirty => .editor,
            .derived_from, .confidence, .from_layer, .is_speculative => .meta,
        };
    }

    /// Check if this predicate represents a relationship between facts
    pub fn isRelational(self: Predicate) bool {
        return switch (self) {
            .has_child, .has_parent, .precedes, .follows, .derived_from => true,
            else => false,
        };
    }

    /// Get the hash for this predicate (for HashMap indexing)
    pub fn hash(self: Predicate) u64 {
        var hasher = std.hash.Wyhash.init(0);

        // Hash the tag first
        const tag = std.meta.activeTag(self);
        hasher.update(std.mem.asBytes(&tag));

        // Hash the payload based on type
        switch (self) {
            .is_token => |kind| hasher.update(std.mem.asBytes(&kind)),
            .has_text => |text| hasher.update(text),
            .bracket_depth => |depth| hasher.update(std.mem.asBytes(&depth)),
            .is_boundary => |kind| hasher.update(std.mem.asBytes(&kind)),
            .indent_level => |level| hasher.update(std.mem.asBytes(&level)),
            .is_node => |kind| hasher.update(std.mem.asBytes(&kind)),
            .has_child, .has_parent, .precedes, .follows => |id| hasher.update(std.mem.asBytes(&id)),
            .has_field => |field| hasher.update(field),
            .binds_symbol, .references_symbol => |id| hasher.update(std.mem.asBytes(&id)),
            .has_type => |id| hasher.update(std.mem.asBytes(&id)),
            .has_value => |value| hasher.update(std.mem.asBytes(&value)),
            .in_scope => |id| hasher.update(std.mem.asBytes(&id)),
            .highlight_color => |kind| hasher.update(std.mem.asBytes(&kind)),
            .has_diagnostic => |kind| hasher.update(std.mem.asBytes(&kind)),
            .derived_from => |id| hasher.update(std.mem.asBytes(&id)),
            .confidence => |conf| hasher.update(std.mem.asBytes(&conf)),
            .from_layer => |layer| hasher.update(std.mem.asBytes(&layer)),
            // Simple predicates with no payload - just use tag hash
            else => {},
        }

        return hasher.final();
    }

    /// Check if two predicates are equal
    pub fn eql(self: Predicate, other: Predicate) bool {
        const self_tag = std.meta.activeTag(self);
        const other_tag = std.meta.activeTag(other);

        if (self_tag != other_tag) return false;

        return switch (self) {
            .is_token => |kind| kind == other.is_token,
            .has_text => |text| std.mem.eql(u8, text, other.has_text),
            .bracket_depth => |depth| depth == other.bracket_depth,
            .is_boundary => |kind| kind == other.is_boundary,
            .indent_level => |level| level == other.indent_level,
            .is_node => |kind| kind == other.is_node,
            .has_child => |id| id == other.has_child,
            .has_parent => |id| id == other.has_parent,
            .precedes => |id| id == other.precedes,
            .follows => |id| id == other.follows,
            .has_field => |field| std.mem.eql(u8, field, other.has_field),
            .binds_symbol => |id| id == other.binds_symbol,
            .references_symbol => |id| id == other.references_symbol,
            .has_type => |id| id == other.has_type,
            .has_value => |value| std.meta.eql(value, other.has_value),
            .in_scope => |id| id == other.in_scope,
            .highlight_color => |kind| kind == other.highlight_color,
            .has_diagnostic => |kind| kind == other.has_diagnostic,
            .derived_from => |id| id == other.derived_from,
            .confidence => |conf| conf == other.confidence,
            .from_layer => |layer| layer == other.from_layer,
            // Simple predicates with no payload
            else => true,
        };
    }
};

/// Categories of predicates for indexing optimization
pub const PredicateCategory = enum {
    lexical, // Token-level facts
    structural, // Block/boundary facts
    syntactic, // AST node facts
    semantic, // Symbol/type facts
    editor, // Editor integration facts
    meta, // Facts about facts
};

/// Placeholder types that will be defined elsewhere in the system
pub const FactId = u32;
pub const SymbolId = u32;
pub const TypeId = u32;
pub const ScopeId = u32;

/// Token kinds for lexical facts
pub const TokenKind = enum {
    identifier,
    keyword,
    operator,
    literal,
    string_literal,
    number_literal,
    boolean_literal, // true/false literals
    null_literal, // null literal
    
    // Specific delimiter types for precise tokenization
    left_brace,      // {
    right_brace,     // }
    left_bracket,    // [
    right_bracket,   // ]
    left_paren,      // (
    right_paren,     // )
    comma,           // ,
    colon,           // :
    semicolon,       // ;
    dot,             // .
    
    // Generic delimiter for fallback
    delimiter,
    
    whitespace,
    comment,
    newline,
    eof,
    unknown,
};

/// Boundary kinds for structural facts
pub const BoundaryKind = enum {
    function,
    class,
    struct_,
    struct_definition,
    enum_,
    enum_definition,
    block,
    module,
    namespace,
};

/// Node kinds for syntactic facts
pub const NodeKind = enum {
    terminal,
    rule,
    list,
    optional,
    error_recovery,
};

/// Highlight kinds for editor facts
pub const HighlightKind = enum {
    keyword,
    identifier,
    string,
    number,
    comment,
    operator,
    delimiter,
    err,
};

/// Diagnostic kinds for editor facts
pub const DiagnosticKind = enum {
    err,
    warning,
    info,
    hint,
};

/// Parser layer identifiers
pub const LayerId = enum {
    lexical,
    structural,
    detailed,
    semantic,
    speculative,
};

/// Generic value type for facts
pub const Value = union(enum) {
    string: []const u8,
    number: f64,
    integer: i64,
    boolean: bool,
    null_value,

    pub fn format(
        self: Value,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        switch (self) {
            .string => |s| try writer.print("\"{s}\"", .{s}),
            .number => |n| try writer.print("{d}", .{n}),
            .integer => |i| try writer.print("{d}", .{i}),
            .boolean => |b| try writer.print("{}", .{b}),
            .null_value => try writer.writeAll("null"),
        }
    }
};

// Tests
const testing = std.testing;

test "Predicate creation and formatting" {
    const pred1 = Predicate{ .is_token = .identifier };
    const pred2 = Predicate{ .has_text = "hello" };
    const pred3 = Predicate{ .bracket_depth = 3 };
    const pred4 = Predicate.is_trivia;

    // Test that they can be created without errors
    _ = pred1;
    _ = pred2;
    _ = pred3;
    _ = pred4;
}

test "Predicate categories" {
    const lexical_pred = Predicate{ .is_token = .identifier };
    const structural_pred = Predicate{ .is_boundary = .function };
    const syntactic_pred = Predicate{ .is_node = .rule };
    const semantic_pred = Predicate{ .binds_symbol = 123 };
    const editor_pred = Predicate{ .highlight_color = .keyword };
    const meta_pred = Predicate{ .confidence = 0.95 };

    try testing.expectEqual(PredicateCategory.lexical, lexical_pred.category());
    try testing.expectEqual(PredicateCategory.structural, structural_pred.category());
    try testing.expectEqual(PredicateCategory.syntactic, syntactic_pred.category());
    try testing.expectEqual(PredicateCategory.semantic, semantic_pred.category());
    try testing.expectEqual(PredicateCategory.editor, editor_pred.category());
    try testing.expectEqual(PredicateCategory.meta, meta_pred.category());
}

test "Predicate relational check" {
    const relational_pred = Predicate{ .has_child = 456 };
    const non_relational_pred = Predicate{ .is_token = .keyword };

    try testing.expect(relational_pred.isRelational());
    try testing.expect(!non_relational_pred.isRelational());
}

test "Predicate equality" {
    const pred1 = Predicate{ .is_token = .identifier };
    const pred2 = Predicate{ .is_token = .identifier };
    const pred3 = Predicate{ .is_token = .keyword };
    const pred4 = Predicate{ .has_text = "test" };
    const pred5 = Predicate{ .has_text = "test" };
    const pred6 = Predicate{ .has_text = "different" };

    try testing.expect(pred1.eql(pred2));
    try testing.expect(!pred1.eql(pred3));
    try testing.expect(!pred1.eql(pred4));
    try testing.expect(pred4.eql(pred5));
    try testing.expect(!pred4.eql(pred6));
}

test "Predicate hashing" {
    const pred1 = Predicate{ .is_token = .identifier };
    const pred2 = Predicate{ .is_token = .identifier };
    const pred3 = Predicate{ .is_token = .keyword };

    // Same predicates should have same hash
    try testing.expectEqual(pred1.hash(), pred2.hash());

    // Different predicates should have different hashes (very likely)
    try testing.expect(pred1.hash() != pred3.hash());
}

test "Value types" {
    const str_val = Value{ .string = "test" };
    const num_val = Value{ .number = 3.14 };
    const int_val = Value{ .integer = 42 };
    const bool_val = Value{ .boolean = true };
    const null_val = Value.null_value;

    // Test that they can be created without errors
    _ = str_val;
    _ = num_val;
    _ = int_val;
    _ = bool_val;
    _ = null_val;
}
