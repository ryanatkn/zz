const std = @import("std");

/// Common token types shared across languages
/// 
/// These tokens represent constructs that appear in multiple languages
/// (operators, delimiters, keywords) to avoid duplication.
pub const CommonToken = enum {
    // Operators
    plus,
    minus,
    multiply,
    divide,
    modulo,
    assign,
    equal,
    not_equal,
    less_than,
    greater_than,
    less_equal,
    greater_equal,
    logical_and,
    logical_or,
    logical_not,
    bitwise_and,
    bitwise_or,
    bitwise_xor,
    bitwise_not,
    left_shift,
    right_shift,
    
    // Delimiters
    left_paren,
    right_paren,
    left_brace,
    right_brace,
    left_bracket,
    right_bracket,
    semicolon,
    comma,
    dot,
    colon,
    question,
    arrow,
    
    // Literals
    string_literal,
    number_literal,
    boolean_literal,
    null_literal,
    
    // Common keywords (present in many C-like languages)
    keyword_if,
    keyword_else,
    keyword_for,
    keyword_while,
    keyword_do,
    keyword_break,
    keyword_continue,
    keyword_return,
    keyword_function,
    keyword_class,
    keyword_struct,
    keyword_enum,
    keyword_interface,
    keyword_import,
    keyword_export,
    keyword_const,
    keyword_let,
    keyword_var,
    keyword_true,
    keyword_false,
    keyword_null,
    
    // Identifiers and whitespace
    identifier,
    whitespace,
    newline,
    comment_line,
    comment_block,
    
    // Special
    end_of_file,
    unknown,
    
    /// Convert common token to string for debugging
    pub fn toString(self: CommonToken) []const u8 {
        return switch (self) {
            .plus => "+",
            .minus => "-",
            .multiply => "*",
            .divide => "/",
            .modulo => "%",
            .assign => "=",
            .equal => "==",
            .not_equal => "!=",
            .less_than => "<",
            .greater_than => ">",
            .less_equal => "<=",
            .greater_equal => ">=",
            .logical_and => "&&",
            .logical_or => "||",
            .logical_not => "!",
            .bitwise_and => "&",
            .bitwise_or => "|",
            .bitwise_xor => "^",
            .bitwise_not => "~",
            .left_shift => "<<",
            .right_shift => ">>",
            
            .left_paren => "(",
            .right_paren => ")",
            .left_brace => "{",
            .right_brace => "}",
            .left_bracket => "[",
            .right_bracket => "]",
            .semicolon => ";",
            .comma => ",",
            .dot => ".",
            .colon => ":",
            .question => "?",
            .arrow => "=>",
            
            .string_literal => "STRING",
            .number_literal => "NUMBER",
            .boolean_literal => "BOOLEAN",
            .null_literal => "NULL",
            
            .keyword_if => "if",
            .keyword_else => "else",
            .keyword_for => "for",
            .keyword_while => "while",
            .keyword_do => "do",
            .keyword_break => "break",
            .keyword_continue => "continue",
            .keyword_return => "return",
            .keyword_function => "function",
            .keyword_class => "class",
            .keyword_struct => "struct",
            .keyword_enum => "enum",
            .keyword_interface => "interface",
            .keyword_import => "import",
            .keyword_export => "export",
            .keyword_const => "const",
            .keyword_let => "let",
            .keyword_var => "var",
            .keyword_true => "true",
            .keyword_false => "false",
            .keyword_null => "null",
            
            .identifier => "IDENTIFIER",
            .whitespace => "WHITESPACE",
            .newline => "NEWLINE",
            .comment_line => "COMMENT_LINE",
            .comment_block => "COMMENT_BLOCK",
            
            .end_of_file => "EOF",
            .unknown => "UNKNOWN",
        };
    }
    
    /// Check if token is an operator
    pub fn isOperator(self: CommonToken) bool {
        return switch (self) {
            .plus, .minus, .multiply, .divide, .modulo,
            .assign, .equal, .not_equal,
            .less_than, .greater_than, .less_equal, .greater_equal,
            .logical_and, .logical_or, .logical_not,
            .bitwise_and, .bitwise_or, .bitwise_xor, .bitwise_not,
            .left_shift, .right_shift => true,
            else => false,
        };
    }
    
    /// Check if token is a delimiter
    pub fn isDelimiter(self: CommonToken) bool {
        return switch (self) {
            .left_paren, .right_paren, .left_brace, .right_brace,
            .left_bracket, .right_bracket, .semicolon, .comma,
            .dot, .colon, .question, .arrow => true,
            else => false,
        };
    }
    
    /// Check if token is a keyword
    pub fn isKeyword(self: CommonToken) bool {
        return switch (self) {
            .keyword_if, .keyword_else, .keyword_for, .keyword_while,
            .keyword_do, .keyword_break, .keyword_continue, .keyword_return,
            .keyword_function, .keyword_class, .keyword_struct, .keyword_enum,
            .keyword_interface, .keyword_import, .keyword_export,
            .keyword_const, .keyword_let, .keyword_var,
            .keyword_true, .keyword_false, .keyword_null => true,
            else => false,
        };
    }
    
    /// Check if token is a literal
    pub fn isLiteral(self: CommonToken) bool {
        return switch (self) {
            .string_literal, .number_literal, .boolean_literal, .null_literal => true,
            else => false,
        };
    }
    
    /// Check if token is trivia (whitespace, comments)
    pub fn isTrivia(self: CommonToken) bool {
        return switch (self) {
            .whitespace, .newline, .comment_line, .comment_block => true,
            else => false,
        };
    }
};

/// Token precedence for operators (higher number = higher precedence)
pub fn getOperatorPrecedence(token: CommonToken) u8 {
    return switch (token) {
        .logical_or => 1,
        .logical_and => 2,
        .bitwise_or => 3,
        .bitwise_xor => 4,
        .bitwise_and => 5,
        .equal, .not_equal => 6,
        .less_than, .greater_than, .less_equal, .greater_equal => 7,
        .left_shift, .right_shift => 8,
        .plus, .minus => 9,
        .multiply, .divide, .modulo => 10,
        .logical_not, .bitwise_not => 11, // Unary operators
        else => 0, // Not an operator or unknown precedence
    };
}

/// Check if operator is left-associative
pub fn isLeftAssociative(token: CommonToken) bool {
    return switch (token) {
        .logical_not, .bitwise_not => false, // Unary operators are right-associative
        else => token.isOperator(),
    };
}

/// Common keyword mappings for different languages
pub const KeywordMap = std.HashMap([]const u8, CommonToken);

/// Create keyword map for C-like languages
pub fn createCLikeKeywords(allocator: std.mem.Allocator) !KeywordMap {
    var map = KeywordMap.init(allocator);
    
    try map.put("if", .keyword_if);
    try map.put("else", .keyword_else);
    try map.put("for", .keyword_for);
    try map.put("while", .keyword_while);
    try map.put("do", .keyword_do);
    try map.put("break", .keyword_break);
    try map.put("continue", .keyword_continue);
    try map.put("return", .keyword_return);
    try map.put("function", .keyword_function);
    try map.put("class", .keyword_class);
    try map.put("struct", .keyword_struct);
    try map.put("enum", .keyword_enum);
    try map.put("interface", .keyword_interface);
    try map.put("import", .keyword_import);
    try map.put("export", .keyword_export);
    try map.put("const", .keyword_const);
    try map.put("let", .keyword_let);
    try map.put("var", .keyword_var);
    try map.put("true", .keyword_true);
    try map.put("false", .keyword_false);
    try map.put("null", .keyword_null);
    
    return map;
}