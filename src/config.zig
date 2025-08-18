// Configuration system facade - re-exports from config/ modules
// Legacy lib/config.zig deleted - functionality moved to config/ directory

const shared = @import("config/shared.zig");
const zon = @import("config/zon.zig");
const resolver = @import("config/resolver.zig");

// Re-export all public API for backward compatibility
pub const SharedConfig = shared.SharedConfig;
pub const SymlinkBehavior = shared.SymlinkBehavior;
pub const BasePatterns = shared.BasePatterns;
pub const ZonLoader = zon.ZonLoader;
pub const ZonConfig = zon.ZonConfig;
pub const PatternResolver = resolver.PatternResolver;

// TODO: Re-implement DRY helper functions after refactoring
// Temporary stub implementations
pub fn shouldIgnorePath(_: anytype, _: []const u8) bool {
    return false; // TODO: Implement actual ignore logic
}

pub fn shouldHideFile(_: anytype, _: []const u8) bool {
    return false; // TODO: Implement actual hide logic
}

pub fn handleSymlink(_: anytype, _: []const u8) bool {
    return true; // TODO: Implement actual symlink handling
}
