const std = @import("std");

/// Predicates define what kind of information a fact conveys
/// Designed to fit in 2 bytes (u16 enum) for the 24-byte Fact struct
pub const Predicate = enum(u16) {
    // =====================================================
    // Lexical Facts - From tokenization
    // =====================================================

    /// Token of a specific kind
    is_token,
    /// Token has specific text
    has_text,
    /// Token has specific kind (identifier, keyword, etc.)
    has_kind,
    /// Token is whitespace
    is_whitespace,
    /// Token is a comment
    is_comment,
    /// Token is an identifier
    is_identifier,
    /// Token is a keyword
    is_keyword,
    /// Token is a string literal
    is_string,
    /// Token is a number literal
    is_number,
    /// Token is an operator
    is_operator,
    /// Token is a delimiter
    is_delimiter,

    // =====================================================
    // Structural Facts - From structural parsing
    // =====================================================

    /// Span is a structural boundary
    is_boundary,
    /// Span starts a block
    starts_block,
    /// Span ends a block
    ends_block,
    /// Span is at indentation level
    indent_level,
    /// Span can be folded
    is_foldable,
    /// Span is an error region
    is_error_region,
    /// Span has parent fact
    has_parent,
    /// Span has child fact
    has_child,
    /// Span precedes another fact
    precedes,
    /// Span follows another fact
    follows,

    // =====================================================
    // Semantic Facts - From analysis
    // =====================================================

    /// Span defines a symbol
    defines_symbol,
    /// Span references a symbol
    references_symbol,
    /// Span has a type
    has_type,
    /// Span has a value
    has_value,
    /// Span is in scope
    has_scope,
    /// Span is a function
    is_function,
    /// Span is a variable
    is_variable,
    /// Span is a type definition
    is_type_def,
    /// Span is a class/struct
    is_class,
    /// Span is a method
    is_method,
    /// Span is a parameter
    is_parameter,
    /// Span is a field
    is_field,

    // =====================================================
    // Diagnostic Facts - From validation
    // =====================================================

    /// Span has an error
    has_error,
    /// Span has a warning
    has_warning,
    /// Span has an info message
    has_info,
    /// Span has a hint
    has_hint,
    /// Span suggests a fix
    has_suggestion,
    /// Span is deprecated
    is_deprecated,
    /// Span is unused
    is_unused,

    // =====================================================
    // Language-Specific Facts
    // =====================================================

    /// JSON: is object
    json_is_object,
    /// JSON: is array
    json_is_array,
    /// JSON: is key
    json_is_key,
    /// JSON: is value
    json_is_value,
    /// JSON: is null
    json_is_null,
    /// JSON: is boolean
    json_is_boolean,

    /// HTML: is tag
    html_is_tag,
    /// HTML: is attribute
    html_is_attribute,
    /// HTML: is text content
    html_is_text,
    /// HTML: is self-closing
    html_is_self_closing,

    /// CSS: is selector
    css_is_selector,
    /// CSS: is property
    css_is_property,
    /// CSS: is value
    css_is_value,
    /// CSS: is rule
    css_is_rule,

    // Add more as needed...

    _, // Non-exhaustive for extensibility
};

/// Get the category of a predicate
pub fn getCategory(predicate: Predicate) PredicateCategory {
    return switch (predicate) {
        .is_token,
        .has_text,
        .has_kind,
        .is_whitespace,
        .is_comment,
        .is_identifier,
        .is_keyword,
        .is_string,
        .is_number,
        .is_operator,
        .is_delimiter,
        => .lexical,

        .is_boundary,
        .starts_block,
        .ends_block,
        .indent_level,
        .is_foldable,
        .is_error_region,
        .has_parent,
        .has_child,
        .precedes,
        .follows,
        => .structural,

        .defines_symbol,
        .references_symbol,
        .has_type,
        .has_value,
        .has_scope,
        .is_function,
        .is_variable,
        .is_type_def,
        .is_class,
        .is_method,
        .is_parameter,
        .is_field,
        => .semantic,

        .has_error,
        .has_warning,
        .has_info,
        .has_hint,
        .has_suggestion,
        .is_deprecated,
        .is_unused,
        => .diagnostic,

        .json_is_object,
        .json_is_array,
        .json_is_key,
        .json_is_value,
        .json_is_null,
        .json_is_boolean,
        .html_is_tag,
        .html_is_attribute,
        .html_is_text,
        .html_is_self_closing,
        .css_is_selector,
        .css_is_property,
        .css_is_value,
        .css_is_rule,
        => .language_specific,

        _ => .unknown,
    };
}

/// Category of predicates
pub const PredicateCategory = enum {
    lexical,
    structural,
    semantic,
    diagnostic,
    language_specific,
    unknown,
};

// Size assertion
comptime {
    std.debug.assert(@sizeOf(Predicate) == 2);
}
