/// ZON Linter - Core linting functionality
///
/// This module provides the main ZON linting interface

// Re-export core linter
pub const Linter = @import("core.zig").ZonLinter;
pub const RuleType = @import("core.zig").ZonRuleType;
pub const EnabledRules = @import("core.zig").EnabledRules;
pub const Diagnostic = @import("core.zig").Diagnostic;

// Re-export commonly used types
pub const LinterOptions = Linter.LinterOptions;
