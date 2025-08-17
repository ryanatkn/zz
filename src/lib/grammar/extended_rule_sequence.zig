const std = @import("std");

// Forward declaration to avoid circular dependency
pub const ExtendedRule = @import("extended_rules.zig").ExtendedRule;

/// Extended sequence that can contain rule references
pub const ExtendedSequence = struct {
    rules: []const ExtendedRule,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, rules: []const ExtendedRule) !ExtendedSequence {
        const rules_copy = try allocator.dupe(ExtendedRule, rules);
        return .{
            .rules = rules_copy,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *ExtendedSequence) void {
        self.allocator.free(self.rules);
    }
};