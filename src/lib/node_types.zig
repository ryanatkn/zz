const std = @import("std");

/// Generic node type checking utilities
/// Only language-agnostic patterns - language-specific checks should go in their own modules

// ============================================================================
// Generic Node Type Patterns
// ============================================================================

/// Check if node represents any kind of comment
pub fn isComment(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "comment") or
           std.mem.eql(u8, node_type, "doc_comment") or
           std.mem.eql(u8, node_type, "container_doc_comment") or
           std.mem.eql(u8, node_type, "line_comment") or
           std.mem.eql(u8, node_type, "block_comment");
}

/// Check if node represents any kind of function
pub fn isFunction(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "function") or
           std.mem.eql(u8, node_type, "function_declaration") or
           std.mem.eql(u8, node_type, "function_expression") or
           std.mem.eql(u8, node_type, "arrow_function") or
           std.mem.eql(u8, node_type, "method_definition") or
           std.mem.eql(u8, node_type, "test_declaration");
}

/// Check if node represents any kind of import
pub fn isImport(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "import") or
           std.mem.eql(u8, node_type, "import_statement") or
           std.mem.eql(u8, node_type, "import_declaration");
}

/// Check if node represents any kind of export
pub fn isExport(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "export") or
           std.mem.eql(u8, node_type, "export_statement") or
           std.mem.eql(u8, node_type, "export_declaration");
}

/// Check if node represents a type definition
pub fn isTypeDefinition(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "type") or
           std.mem.eql(u8, node_type, "type_alias") or
           std.mem.eql(u8, node_type, "type_alias_declaration") or
           std.mem.eql(u8, node_type, "interface") or
           std.mem.eql(u8, node_type, "interface_declaration");
}

/// Check if node represents a class
pub fn isClass(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "class") or
           std.mem.eql(u8, node_type, "class_declaration") or
           std.mem.eql(u8, node_type, "class_expression");
}

/// Check if node represents a struct
pub fn isStruct(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "struct") or
           std.mem.eql(u8, node_type, "struct_declaration");
}

/// Check if node represents an enum
pub fn isEnum(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "enum") or
           std.mem.eql(u8, node_type, "enum_declaration");
}

/// Check if node represents a union
pub fn isUnion(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "union") or
           std.mem.eql(u8, node_type, "union_declaration");
}

/// Check if node represents a variable declaration
pub fn isVariable(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "variable") or
           std.mem.eql(u8, node_type, "var_declaration") or
           std.mem.eql(u8, node_type, "const_declaration") or
           std.mem.eql(u8, node_type, "let_declaration");
}

/// Check if node represents a constant
pub fn isConstant(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "constant") or
           std.mem.eql(u8, node_type, "const_declaration");
}

/// Check if node represents a test
pub fn isTest(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "test") or
           std.mem.eql(u8, node_type, "test_declaration") or
           std.mem.eql(u8, node_type, "test_case");
}

/// Check if node represents an error
pub fn isError(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "error") or
           std.mem.eql(u8, node_type, "error_declaration") or
           std.mem.eql(u8, node_type, "throw_statement") or
           std.mem.eql(u8, node_type, "catch_clause");
}

test "generic node type checks" {
    try std.testing.expect(isComment("comment"));
    try std.testing.expect(isComment("doc_comment"));
    try std.testing.expect(isComment("line_comment"));
    try std.testing.expect(!isComment("function"));
    
    try std.testing.expect(isFunction("function"));
    try std.testing.expect(isFunction("function_declaration"));
    try std.testing.expect(isFunction("arrow_function"));
    try std.testing.expect(!isFunction("comment"));
    
    try std.testing.expect(isImport("import"));
    try std.testing.expect(isImport("import_statement"));
    try std.testing.expect(!isImport("export"));
    
    try std.testing.expect(isTypeDefinition("type"));
    try std.testing.expect(isTypeDefinition("interface"));
    try std.testing.expect(!isTypeDefinition("function"));
}