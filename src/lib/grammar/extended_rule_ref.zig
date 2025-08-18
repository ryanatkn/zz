const std = @import("std");

/// Rule reference for forward/circular rule definitions
pub const RuleRef = struct {
    name: []const u8,

    pub fn init(name: []const u8) RuleRef {
        return .{ .name = name };
    }
};
