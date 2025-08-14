/// HTML language implementation combining extraction, parsing, and formatting
pub const HtmlLanguage = struct {
    pub const language_name = "html";
    
    /// Get tree-sitter grammar for HTML
    pub const grammar = @import("grammar.zig").grammar;
    
    /// Extract HTML code using patterns or AST
    pub const extract = @import("extractor.zig").extract;
    
    /// AST-based extraction visitor  
    pub const visitor = @import("visitor.zig").visitor;
    
    /// Format HTML source code
    pub const format = @import("formatter.zig").format;
};