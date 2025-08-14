// Configuration system facade - re-exports consolidated config from lib/
pub const Config = @import("lib/config.zig");

// Re-export all public API for backward compatibility
pub const SharedConfig = Config.SharedConfig;
pub const SymlinkBehavior = Config.SymlinkBehavior;
pub const BasePatterns = Config.BasePatterns;
pub const ZonLoader = Config.ZonLoader;
pub const ZonConfig = Config.ZonConfig;
pub const PatternResolver = Config.PatternResolver;

// Re-export DRY helper functions
pub const shouldIgnorePath = Config.shouldIgnorePath;
pub const shouldHideFile = Config.shouldHideFile;
pub const handleSymlink = Config.handleSymlink;