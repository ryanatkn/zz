const std = @import("std");
const config = @import("../config.zig");
const BuildConfig = @import("build_parser.zig").BuildConfig;

/// Categories for dependency classification
pub const DependencyCategory = enum {
    core, // Core libraries (tree-sitter, zig-tree-sitter)
    grammar, // Language grammars (tree-sitter-*)
    reference, // Documentation/specs (zig-spec)

    pub fn toString(self: DependencyCategory) []const u8 {
        return switch (self) {
            .core => "core",
            .grammar => "grammar",
            .reference => "reference",
        };
    }

    pub fn displayName(self: DependencyCategory) []const u8 {
        return switch (self) {
            .core => "Core Libraries",
            .grammar => "Language Grammars",
            .reference => "Reference Documentation",
        };
    }
};

/// Enhanced dependency documentation structure
pub const DependencyDoc = struct {
    name: []const u8,
    category: DependencyCategory,
    version_info: config.VersionInfo,
    build_config: BuildConfig,
    language: ?[]const u8, // For grammars: "zig", "css", etc.
    purpose: []const u8, // Human-readable purpose

    pub fn deinit(self: *const DependencyDoc, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        self.version_info.deinit(allocator);
        self.build_config.deinit(allocator);
        if (self.language) |lang| {
            allocator.free(lang);
        }
        allocator.free(self.purpose);
    }
};
