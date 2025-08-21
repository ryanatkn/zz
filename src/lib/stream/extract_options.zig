/// Extract options for stream-based fact extraction

const std = @import("std");

/// Options for fact extraction
pub const ExtractOptions = struct {
    /// Extract structural facts (objects, arrays, etc.)
    extract_structure: bool = true,
    
    /// Extract value facts (strings, numbers, booleans)
    extract_values: bool = true,
    
    /// Extract identifier facts (field names, property names)
    extract_identifiers: bool = true,
    
    /// Extract type information
    extract_types: bool = true,
    
    /// Extract documentation/comments
    extract_docs: bool = false,
    
    /// Maximum depth to extract (0 = unlimited)
    max_depth: u8 = 0,
    
    /// Minimum confidence level for facts
    min_confidence: f16 = 0.5,
    
    /// Whether to preserve source text references
    preserve_source: bool = false,
    
    /// Whether to extract nested structures recursively
    recursive: bool = true,
};

/// Default options for different extraction modes
pub const structure_only = ExtractOptions{
    .extract_structure = true,
    .extract_values = false,
    .extract_identifiers = false,
    .extract_types = false,
};

pub const values_only = ExtractOptions{
    .extract_structure = false,
    .extract_values = true,
    .extract_identifiers = false,
    .extract_types = false,
};

pub const full_extraction = ExtractOptions{
    .extract_structure = true,
    .extract_values = true,
    .extract_identifiers = true,
    .extract_types = true,
    .extract_docs = true,
};

pub const api_extraction = ExtractOptions{
    .extract_structure = true,
    .extract_values = false,
    .extract_identifiers = true,
    .extract_types = true,
    .extract_docs = true,
};

test "extraction options" {
    const testing = std.testing;
    
    // Test default options
    const default_opts = ExtractOptions{};
    try testing.expect(default_opts.extract_structure);
    try testing.expect(default_opts.extract_values);
    
    // Test preset options
    const struct_opts = structure_only;
    try testing.expect(struct_opts.extract_structure);
    try testing.expect(!struct_opts.extract_values);
    
    const api_opts = api_extraction;
    try testing.expect(api_opts.extract_structure);
    try testing.expect(api_opts.extract_types);
    try testing.expect(api_opts.extract_docs);
}