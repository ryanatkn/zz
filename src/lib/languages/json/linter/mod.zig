/// JSON Linter - Combined Core and Rules Functionality
///
/// This module provides a unified interface to the split linter components
const std = @import("std");

// Re-export core linter
pub const Linter = @import("core.zig").Linter;
pub const ValidationError = @import("core.zig").ValidationError;
pub const RuleType = @import("core.zig").RuleType;
pub const EnabledRules = @import("core.zig").EnabledRules;
pub const Diagnostic = @import("core.zig").Diagnostic;
pub const Edit = @import("core.zig").Edit;

// Re-export rule functionality (accessible as linter.rules.*)
pub const rules = @import("rules/mod.zig");

// Re-export commonly used types
pub const LinterOptions = Linter.LinterOptions;
pub const RuleInfo = Linter.RuleInfo;

// ============================================================================
// Tests for Complete Linter Functionality
// ============================================================================

test "JSON linter - detect duplicate keys" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const input = "{\"key\": 1, \"key\": 2}";

    var linter = Linter.init(allocator, .{});
    defer linter.deinit();

    var enabled_rules = EnabledRules.initEmpty();
    enabled_rules.insert(.no_duplicate_keys);

    const diagnostics = try linter.lintSource(input, enabled_rules);
    defer {
        for (diagnostics) |diag| {
            allocator.free(diag.message);
        }
        allocator.free(diagnostics);
    }

    try testing.expect(diagnostics.len > 0);
    try testing.expect(diagnostics[0].rule == .no_duplicate_keys);
}

test "JSON linter - detect leading zeros" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const input = "{\"number\": 01234}";

    var linter = Linter.init(allocator, .{});
    defer linter.deinit();

    var enabled_rules = EnabledRules.initEmpty();
    enabled_rules.insert(.no_leading_zeros);

    const diagnostics = try linter.lintSource(input, enabled_rules);
    defer {
        for (diagnostics) |diag| {
            allocator.free(diag.message);
        }
        allocator.free(diagnostics);
    }

    try testing.expect(diagnostics.len > 0);
    try testing.expect(diagnostics[0].rule == .no_leading_zeros);
}

test "JSON linter - detect deep nesting" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Create deeply nested JSON
    const input = "{\"a\": {\"b\": {\"c\": {\"d\": {\"e\": 1}}}}}";

    var options = Linter.LinterOptions{};
    options.warn_on_deep_nesting = 3; // Warn at depth 3

    var linter = Linter.init(allocator, options);
    defer linter.deinit();

    var enabled_rules = EnabledRules.initEmpty();
    enabled_rules.insert(.deep_nesting);

    const diagnostics = try linter.lintSource(input, enabled_rules);
    defer {
        for (diagnostics) |diag| {
            allocator.free(diag.message);
        }
        allocator.free(diagnostics);
    }

    try testing.expect(diagnostics.len > 0);
    try testing.expect(diagnostics[0].rule == .deep_nesting);
}

test "JSON linter - valid JSON passes" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const input = "{\"name\": \"test\", \"value\": 42, \"active\": true}";

    var linter = Linter.init(allocator, .{});
    defer linter.deinit();

    const default_rules = Linter.getDefaultRules();
    const diagnostics = try linter.lintSource(input, default_rules);
    defer {
        for (diagnostics) |diag| {
            allocator.free(diag.message);
        }
        allocator.free(diagnostics);
    }

    // Valid JSON should not generate diagnostics
    try testing.expectEqual(@as(usize, 0), diagnostics.len);
}

// Include rule tests
test {
    _ = rules;
}
