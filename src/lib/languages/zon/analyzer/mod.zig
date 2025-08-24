/// ZON Analyzer - Core analysis functionality
///
/// This module provides schema extraction and analysis for ZON files

// Re-export core analyzer
pub const Analyzer = @import("core.zig").Analyzer;
pub const Symbol = @import("core.zig").Symbol;
pub const Schema = @import("core.zig").Analyzer.Schema;
pub const ZigTypeDefinition = @import("core.zig").Analyzer.ZigTypeDefinition;

// Re-export commonly used types
pub const Statistics = Analyzer.Statistics;
pub const AnalyzerOptions = Analyzer.AnalysisOptions;
