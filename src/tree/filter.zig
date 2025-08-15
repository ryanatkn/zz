const std = @import("std");
const SharedConfig = @import("../config.zig").SharedConfig;
const shouldIgnorePath = @import("../config.zig").shouldIgnorePath;
const shouldHideFile = @import("../config.zig").shouldHideFile;

pub const Filter = struct {
    shared_config: SharedConfig,

    const Self = @This();

    pub fn init(shared_config: SharedConfig) Self {
        return Self{
            .shared_config = shared_config,
        };
    }

    pub fn shouldIgnore(self: Self, path: []const u8) bool {
        // Use shared DRY helper function
        return shouldIgnorePath(self.shared_config, path);
    }

    pub fn shouldIgnoreAtPath(self: Self, full_path: []const u8) bool {
        // Use shared helper which handles path-based patterns
        return shouldIgnorePath(self.shared_config, full_path);
    }

    pub fn shouldHide(self: Self, name: []const u8) bool {
        // Use shared DRY helper function
        return shouldHideFile(self.shared_config, name);
    }
};
