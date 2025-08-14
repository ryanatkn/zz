const patterns_mod = @import("patterns.zig");

/// CSS language implementation
pub const CssLanguage = struct {
    pub const language_name = "css";
    
    /// Get tree-sitter grammar for CSS
    pub const grammar = @import("grammar.zig").grammar;
    
    /// Extract code using patterns (tree-sitter integration in future)
    pub const extract = @import("extractor.zig").extract;
    
    /// AST-based extraction visitor  
    pub const visitor = @import("visitor.zig").visitor;
    
    /// Format CSS source code
    pub const format = @import("formatter.zig").format;
    
    /// Pattern-based extraction patterns
    pub const patterns = patterns_mod.patterns;
};