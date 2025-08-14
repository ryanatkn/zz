/// JSON language implementation combining extraction, parsing, and formatting
pub const JsonLanguage = struct {
    pub const language_name = "json";
    
    /// Get tree-sitter grammar for JSON
    pub const grammar = @import("grammar.zig").grammar;
    
    /// Extract code using tree-sitter AST
    pub const extract = @import("extractor.zig").extract;
    
    /// AST-based extraction visitor
    pub const visitor = @import("visitor.zig").visitor;
    
    /// Format JSON source code
    pub const format = @import("formatter.zig").format;
    
    /// Legacy pattern-based extraction (fallback)
    pub const patterns = @import("patterns.zig").patterns;
};