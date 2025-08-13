const std = @import("std");
const builtin = @import("builtin");

/// Conditional imports helper to centralize test vs production dependency management
/// Provides standardized patterns for optional dependencies and feature flags
pub const ConditionalImports = struct {

    // ============================================================================
    // Tree-sitter Conditional Import
    // ============================================================================

    /// Tree-sitter parser that works in both test and production environments
    /// In tests: provides mock interface to avoid tree-sitter dependencies
    /// In production: uses real tree-sitter for AST parsing
    pub const TreeSitter = if (builtin.is_test) struct {
        pub const Parser = ?*anyopaque;
        pub const Tree = ?*anyopaque;
        pub const Node = struct {
            pub fn isNull(self: @This()) bool { _ = self; return true; }
            pub fn child(self: @This(), index: u32) @This() { _ = self; _ = index; return @This(){}; }
            pub fn childCount(self: @This()) u32 { _ = self; return 0; }
            pub fn @"type"(self: @This()) []const u8 { _ = self; return "mock"; }
            pub fn startByte(self: @This()) u32 { _ = self; return 0; }
            pub fn endByte(self: @This()) u32 { _ = self; return 0; }
        };
        
        pub fn parser() Parser { return null; }
        pub fn parseString(parser_inst: Parser, source: []const u8) ?Tree { _ = parser_inst; _ = source; return null; }
        pub fn rootNode(tree: Tree) Node { _ = tree; return Node{}; }
    } else @import("tree-sitter");

    // ============================================================================
    // Feature Flag System
    // ============================================================================

    /// Feature flags for conditional compilation
    pub const Features = struct {
        /// Enable tree-sitter AST parsing (disabled in tests by default)
        pub const enable_ast_parsing = !builtin.is_test;
        
        /// Enable performance benchmarking (enabled in release builds)
        pub const enable_benchmarking = builtin.mode != .Debug;
        
        /// Enable colored output (disabled in tests for reproducible output)
        pub const enable_colors = !builtin.is_test;
        
        /// Enable verbose logging (enabled in debug builds)
        pub const enable_verbose_logging = builtin.mode == .Debug;
        
        /// Enable memory tracking (enabled in debug builds)
        pub const enable_memory_tracking = builtin.mode == .Debug;
    };

    // ============================================================================
    // Platform-Specific Imports
    // ============================================================================

    /// Platform detection utilities
    pub const Platform = struct {
        pub const is_posix = switch (builtin.os.tag) {
            .linux, .macos, .freebsd, .netbsd, .openbsd, .dragonfly => true,
            else => false,
        };
        
        pub const is_windows = builtin.os.tag == .windows;
        pub const is_linux = builtin.os.tag == .linux;
        pub const is_macos = builtin.os.tag == .macos;
        
        pub const supports_colors = is_posix; // ANSI colors generally work on POSIX
    };

    // ============================================================================
    // Development vs Production Imports
    // ============================================================================

    /// Testing utilities that are only available in test mode
    pub const TestingOnly = if (builtin.is_test) struct {
        pub const MockFilesystem = @import("../filesystem/mock.zig").MockFilesystem;
        pub const test_allocator = std.testing.allocator;
        pub const expectEqual = std.testing.expectEqual;
        pub const expectEqualStrings = std.testing.expectEqualStrings;
        pub const expect = std.testing.expect;
        
        /// Create a mock filesystem for testing
        pub fn createMockFilesystem(allocator: std.mem.Allocator) MockFilesystem {
            return MockFilesystem.init(allocator);
        }
    } else struct {
        // Empty struct for production builds
    };

    // ============================================================================
    // Optional Dependency Management
    // ============================================================================

    /// Placeholder for future optional dependency management
    /// Note: Zig requires compile-time known import paths, so runtime optional imports
    /// are not directly supported. This serves as a design pattern for future use.
    pub const OptionalImports = struct {
        // Future: Could contain registry of available/unavailable modules
        pub const available_modules = .{
            .tree_sitter = !builtin.is_test,
        };
    };

    // ============================================================================
    // Environment-Based Configuration
    // ============================================================================

    /// Configuration based on environment variables and build settings
    pub const Config = struct {
        /// Check if verbose mode is enabled via environment or build
        pub fn isVerbose() bool {
            if (builtin.is_test) return false; // Quiet tests by default
            
            // Check environment variable
            if (std.process.getEnvVarOwned(std.heap.page_allocator, "VERBOSE")) |value| {
                defer std.heap.page_allocator.free(value);
                return std.mem.eql(u8, value, "1") or std.mem.eql(u8, value, "true");
            } else |_| {}
            
            return Features.enable_verbose_logging;
        }
        
        /// Check if colors should be enabled
        pub fn shouldUseColors() bool {
            if (!Features.enable_colors) return false;
            if (!Platform.supports_colors) return false;
            
            // Check if NO_COLOR environment variable is set
            if (std.process.getEnvVarOwned(std.heap.page_allocator, "NO_COLOR")) |value| {
                defer std.heap.page_allocator.free(value);
                return false; // NO_COLOR is set, disable colors
            } else |_| {}
            
            // Check if stdout is a TTY
            return std.io.getStdOut().isTty();
        }
        
        /// Get the number of threads to use for parallel operations
        pub fn getThreadCount() u32 {
            if (std.process.getEnvVarOwned(std.heap.page_allocator, "ZZ_THREADS")) |value| {
                defer std.heap.page_allocator.free(value);
                return std.fmt.parseInt(u32, value, 10) catch 1;
            } else |_| {}
            
            // Default to CPU count or 1
            const cpu_count = std.Thread.getCpuCount() catch 1;
            return @max(1, @as(u32, @intCast(@min(cpu_count, std.math.maxInt(u32)))));
        }
    };

    // ============================================================================
    // Version and Build Information
    // ============================================================================

    /// Build information for debugging and diagnostics
    pub const BuildInfo = struct {
        pub const zig_version = builtin.zig_version;
        pub const build_mode = builtin.mode;
        pub const target = builtin.target;
        pub const is_test = builtin.is_test;
        pub const is_debug = builtin.mode == .Debug;
        pub const is_release_fast = builtin.mode == .ReleaseFast;
        pub const is_release_safe = builtin.mode == .ReleaseSafe;
        pub const is_release_small = builtin.mode == .ReleaseSmall;
        
        /// Get build information as a formatted string
        pub fn getBuildString(allocator: std.mem.Allocator) ![]u8 {
            return try std.fmt.allocPrint(allocator, 
                "zig {d}.{d}.{d} ({s}, {s})", 
                .{ 
                    zig_version.major,
                    zig_version.minor,
                    zig_version.patch,
                    @tagName(build_mode), 
                    @tagName(target.os.tag) 
                }
            );
        }
    };
};

// ============================================================================
// Convenience Re-exports
// ============================================================================

/// Convenient access to the tree-sitter import
pub const ts = ConditionalImports.TreeSitter;

/// Convenient access to platform detection
pub const platform = ConditionalImports.Platform;

/// Convenient access to feature flags
pub const features = ConditionalImports.Features;

/// Convenient access to configuration
pub const config = ConditionalImports.Config;

/// Convenient access to build information
pub const build_info = ConditionalImports.BuildInfo;

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "tree-sitter conditional import" {
    // In test mode, should provide mock interface
    try testing.expect(builtin.is_test);
    
    const parser = ts.parser();
    try testing.expect(parser == null); // Mock returns null
    
    const mock_node = ts.Node{};
    try testing.expect(mock_node.isNull());
    try testing.expect(mock_node.childCount() == 0);
    try testing.expectEqualStrings("mock", mock_node.@"type"());
}

test "feature flags" {
    // Test feature flags in test environment
    try testing.expect(!features.enable_ast_parsing); // Disabled in tests
    try testing.expect(!features.enable_colors); // Disabled in tests
    try testing.expect(features.enable_verbose_logging == (builtin.mode == .Debug));
}

test "platform detection" {
    // These should work regardless of platform
    try testing.expect(platform.is_posix or platform.is_windows);
    try testing.expect(!(platform.is_posix and platform.is_windows));
}

test "build information" {
    const allocator = testing.allocator;
    
    try testing.expect(build_info.is_test);
    try testing.expect(build_info.zig_version.major >= 0);
    
    const build_string = try build_info.getBuildString(allocator);
    defer allocator.free(build_string);
    try testing.expect(build_string.len > 0);
}

test "configuration helpers" {
    // Test configuration in test environment
    try testing.expect(!config.isVerbose()); // Should be false in tests
    try testing.expect(!config.shouldUseColors()); // Should be false in tests
    try testing.expect(config.getThreadCount() >= 1);
}