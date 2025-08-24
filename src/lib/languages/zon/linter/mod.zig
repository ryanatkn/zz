/// ZON Linter - Core linting functionality
///
/// This module provides the main ZON linting interface

// Re-export core linter
pub const Linter = @import("core.zig").Linter;
pub const RuleType = @import("core.zig").RuleType;
pub const EnabledRules = @import("core.zig").EnabledRules;
pub const Diagnostic = @import("core.zig").Diagnostic;

// Re-export commonly used types
pub const LinterOptions = Linter.LintOptions;
