// Configuration system facade - re-exports from config/ modules
// Legacy lib/config.zig deleted - functionality moved to config/ directory

const std = @import("std");
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

// DRY helper functions for consistent pattern matching
pub fn shouldIgnorePath(config: SharedConfig, path: []const u8) bool {
    if (path.len == 0) return false;
    
    // Check against ignored patterns
    for (config.ignored_patterns) |pattern| {
        if (std.mem.eql(u8, path, pattern)) {
            return true;
        }
        // Also check if the path ends with the pattern (for path-based matching)
        if (std.mem.endsWith(u8, path, pattern)) {
            return true;
        }
    }
    
    // Check dot directories (always ignored)
    if (std.mem.startsWith(u8, path, ".")) {
        return true;
    }
    
    return false;
}

pub fn shouldHideFile(config: SharedConfig, name: []const u8) bool {
    if (name.len == 0) return false;
    
    // Check against hidden file patterns
    for (config.hidden_files) |pattern| {
        if (std.mem.eql(u8, name, pattern)) {
            return true;
        }
    }
    
    return false;
}

pub fn handleSymlink(_: anytype, _: []const u8) bool {
    return true; // TODO: Implement actual symlink handling
}
