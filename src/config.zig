// Configuration system facade - re-exports from config/ modules
// Uses layered pattern matching via lib/patterns for consistency

const std = @import("std");
const shared = @import("config/shared.zig");
const zon = @import("config/zon.zig");
const resolver = @import("config/resolver.zig");
const path_matcher = @import("lib/patterns/path.zig");
const glob = @import("lib/patterns/glob.zig");
const primitives = @import("lib/patterns/primitives.zig");

// Re-export all public API for backward compatibility
pub const SharedConfig = shared.SharedConfig;
pub const SymlinkBehavior = shared.SymlinkBehavior;
pub const BasePatterns = shared.BasePatterns;
pub const ZonLoader = zon.ZonLoader;
pub const ZonConfig = zon.ZonConfig;
pub const PatternResolver = resolver.PatternResolver;

// DRY helper function using layered pattern matching
pub fn shouldIgnorePath(config: SharedConfig, path: []const u8) bool {
    if (path.len == 0) return false;
    
    // Check against ignored patterns using appropriate matcher
    for (config.ignored_patterns) |pattern| {
        if (matchesPattern(path, pattern)) {
            return true;
        }
    }
    
    // Check dot directories (always ignored)
    if (path_matcher.startsWithDotDirectory(path)) {
        return true;
    }
    
    return false;
}

/// Smart pattern dispatcher - detects pattern type and delegates to appropriate matcher
fn matchesPattern(path: []const u8, pattern: []const u8) bool {
    // Detect pattern type and delegate to appropriate matcher
    if (primitives.hasWildcard(pattern)) {
        // Use glob matcher for wildcard patterns
        return glob.matchSimplePattern(path, pattern);
    }
    
    // Use path matcher for path-based patterns
    return path_matcher.matchPath(path, pattern);
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
