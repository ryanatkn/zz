const std = @import("std");
const testing = std.testing;

// Import JSON components
const Parser = @import("../parser/mod.zig").Parser;
const Linter = @import("../linter/mod.zig").Linter;
const EnabledRules = @import("../linter/mod.zig").EnabledRules;

// Import types
const interface_types = @import("../../interface.zig");

// =============================================================================
// Linter Tests
// =============================================================================

test "JSON linter - all rules" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Create JSON with duplicate keys (valid JSON syntax)
    const problematic_json = "{\"key\": 1, \"key\": 2}"; // Duplicate key

    // Use default enabled rules from linter
    const enabled_rules = Linter.getDefaultRules();

    var linter = Linter.init(allocator, .{});
    defer linter.deinit();

    const diagnostics = try linter.lintSource(problematic_json, enabled_rules);
    defer {
        for (diagnostics) |diag| {
            allocator.free(diag.message);
        }
        allocator.free(diagnostics);
    }

    // Should find issues
    try testing.expect(diagnostics.len > 0);

    // Check that we found specific issues
    var found_duplicate_keys = false;

    for (diagnostics) |diag| {
        if (diag.rule == .no_duplicate_keys) {
            found_duplicate_keys = true;
        }
    }

    try testing.expect(found_duplicate_keys);
}

test "JSON linter - deep nesting warning" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Create deeply nested JSON
    const deep_json = "{\"a\": {\"b\": {\"c\": {\"d\": {\"e\": 1}}}}}";

    var linter = Linter.init(allocator, .{ .warn_on_deep_nesting = 3 });
    defer linter.deinit();

    var enabled_rules = EnabledRules.initEmpty();
    enabled_rules.insert(.deep_nesting);

    const diagnostics = try linter.lintSource(deep_json, enabled_rules);
    defer {
        for (diagnostics) |diag| {
            allocator.free(diag.message);
        }
        allocator.free(diagnostics);
    }

    // Should warn about deep nesting
    try testing.expect(diagnostics.len > 0);
}
