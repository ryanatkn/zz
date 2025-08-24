/// ZON Analyzer - Core analysis functionality
///
/// This module provides schema extraction and analysis for ZON files

// Re-export core analyzer
pub const Analyzer = @import("core.zig").ZonAnalyzer;
pub const Symbol = @import("core.zig").Symbol;
pub const ZonSchema = @import("core.zig").ZonAnalyzer.ZonSchema;
pub const ZigTypeDefinition = @import("core.zig").ZonAnalyzer.ZigTypeDefinition;

// Re-export commonly used types
pub const Statistics = Analyzer.Statistics;
pub const AnalyzerOptions = Analyzer.AnalyzerOptions;
