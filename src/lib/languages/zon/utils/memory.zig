const std = @import("std");
const ast_converter = @import("../ast/converter.zig");

/// ZON-specific memory management utilities
/// Handles parsed vs default ZON configurations with proper cleanup
/// Memory management helper for ZON parsed data
/// Follows ownership patterns with clear naming and explicit ownership tracking
pub fn ManagedConfig(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        config: T,
        is_parsed: bool, // Track if config was parsed (needs freeing) or default (doesn't need freeing)

        /// Create managed config from parsed ZON data - takes ownership of parsed data
        pub fn initParsed(allocator: std.mem.Allocator, parsed_config: T) Self {
            return Self{
                .allocator = allocator,
                .config = parsed_config,
                .is_parsed = true,
            };
        }

        /// Create managed config from default value - no ownership, no freeing needed
        pub fn initDefault(allocator: std.mem.Allocator, default_config: T) Self {
            return Self{
                .allocator = allocator,
                .config = default_config,
                .is_parsed = false,
            };
        }

        /// Safe cleanup - only frees parsed data, ignores default values
        pub fn deinit(self: *Self) void {
            if (self.is_parsed) {
                // Free the parsed data using the AST converter's free function
                ast_converter.free(self.allocator, self.config);
            }
            // Default configs don't need freeing
        }

        /// Get the underlying config value
        pub fn get(self: *const Self) T {
            return self.config;
        }

        /// Check if this config was parsed from ZON file
        pub fn wasParsed(self: *const Self) bool {
            return self.is_parsed;
        }
    };
}

/// Helper function to safely parse ZON content with proper memory management
pub fn parseSafely(
    comptime T: type,
    allocator: std.mem.Allocator,
    content: []const u8,
    default_value: T,
) ManagedConfig(T) {
    const parsed = ast_converter.parseFromSlice(T, allocator, content) catch {
        // On parse error, use default (no freeing needed)
        return ManagedConfig(T).initDefault(allocator, default_value);
    };

    // Success - parsed data needs freeing
    return ManagedConfig(T).initParsed(allocator, parsed);
}

/// Arena-based ZON parsing for temporary usage (like tests)
/// All allocations are cleaned up when arena is deinitialized
pub const ArenaParser = struct {
    arena: std.heap.ArenaAllocator,

    pub fn init(backing_allocator: std.mem.Allocator) ArenaParser {
        return ArenaParser{
            .arena = std.heap.ArenaAllocator.init(backing_allocator),
        };
    }

    pub fn deinit(self: *ArenaParser) void {
        self.arena.deinit();
    }

    /// Parse ZON with arena allocator - no need for individual freeing
    pub fn parseFromSlice(self: *ArenaParser, comptime T: type, content: []const u8) !T {
        return ast_converter.parseFromSlice(T, self.arena.allocator(), content);
    }

    /// Parse with default fallback
    pub fn parseFromSliceWithDefault(self: *ArenaParser, comptime T: type, content: []const u8, default_value: T) T {
        return self.parseFromSlice(T, content) catch default_value;
    }
};

test "ManagedConfig with parsed data" {
    const testing = std.testing;

    const TestConfig = struct {
        name: []const u8,
        value: u32,
    };

    const test_content =
        \\.{
        \\    .name = "test",
        \\    .value = 42,
        \\}
    ;

    // Parse ZON data
    const parsed = try ast_converter.parseFromSlice(TestConfig, testing.allocator, test_content);
    var managed = ManagedConfig(TestConfig).initParsed(testing.allocator, parsed);
    defer managed.deinit();

    // Verify data
    try testing.expectEqualStrings("test", managed.get().name);
    try testing.expectEqual(@as(u32, 42), managed.get().value);
    try testing.expect(managed.wasParsed());
}

test "ManagedConfig with default data" {
    const testing = std.testing;

    const TestConfig = struct {
        name: []const u8 = "default",
        value: u32 = 0,
    };

    const default_config = TestConfig{};
    var managed = ManagedConfig(TestConfig).initDefault(testing.allocator, default_config);
    defer managed.deinit(); // Safe to call, won't free anything

    // Verify data
    try testing.expectEqualStrings("default", managed.get().name);
    try testing.expectEqual(@as(u32, 0), managed.get().value);
    try testing.expect(!managed.wasParsed());
}

test "parseSafely with valid content" {
    const testing = std.testing;

    const TestConfig = struct {
        name: []const u8,
        value: u32,
    };

    const test_content =
        \\.{
        \\    .name = "test",
        \\    .value = 42,
        \\}
    ;

    const default_config = TestConfig{ .name = "default", .value = 0 };
    var managed = parseSafely(TestConfig, testing.allocator, test_content, default_config);
    defer managed.deinit();

    try testing.expectEqualStrings("test", managed.get().name);
    try testing.expectEqual(@as(u32, 42), managed.get().value);
    try testing.expect(managed.wasParsed());
}

test "parseSafely with invalid content" {
    const testing = std.testing;

    const TestConfig = struct {
        name: []const u8,
        value: u32,
    };

    // Use definitely invalid ZON syntax
    const invalid_content = "not valid zon at all";
    const default_config = TestConfig{ .name = "default", .value = 42 };
    var managed = parseSafely(TestConfig, testing.allocator, invalid_content, default_config);
    defer managed.deinit(); // Safe - uses default, no freeing needed

    // The invalid content should cause parseFromSlice to fail and use default
    try testing.expectEqualStrings("default", managed.get().name);
    try testing.expectEqual(@as(u32, 42), managed.get().value);
    try testing.expect(!managed.wasParsed());
}

test "ArenaParser basic usage" {
    const testing = std.testing;

    const TestConfig = struct {
        name: []const u8,
        value: u32,
    };

    const test_content =
        \\.{
        \\    .name = "test",
        \\    .value = 42,
        \\}
    ;

    var arena_parser = ArenaParser.init(testing.allocator);
    defer arena_parser.deinit(); // Cleans up all allocations automatically

    const parsed = try arena_parser.parseFromSlice(TestConfig, test_content);
    try testing.expectEqualStrings("test", parsed.name);
    try testing.expectEqual(@as(u32, 42), parsed.value);

    // No need for individual freeing - arena cleans up everything
}
