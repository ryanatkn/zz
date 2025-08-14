const LanguagePatterns = @import("../../extractor_base.zig").LanguagePatterns;

/// Get HTML extraction patterns for fallback text-based extraction
pub fn getHtmlPatterns() LanguagePatterns {
    const element_patterns = [_][]const u8{ "<", "</" };
    const import_patterns = [_][]const u8{ "<script", "<link", "<style", "src=", "href=" };
    const doc_patterns = [_][]const u8{ "<!--" };
    const structure_patterns = [_][]const u8{ "<html", "<head", "<body", "<div", "<section", "<article", "<nav", "<main" };
    
    return LanguagePatterns{
        .functions = null, // HTML doesn't have functions
        .types = &element_patterns,
        .imports = &import_patterns,
        .docs = &doc_patterns,
        .tests = null, // HTML doesn't have tests
        .structure = &structure_patterns,
        .custom_extract = null,
    };
}