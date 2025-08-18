const std = @import("std");
const ZonParser = @import("../languages/zon/mod.zig");

/// ZON-specific memory management utilities
/// Handles parsed vs default ZON configurations with proper cleanup
/// Memory management helper for ZON parsed data
/// Follows ownership patterns with clear naming and explicit ownership tracking
pub fn ManagedZonConfig(comptime T: type) type {
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
                ZonParser.free(self.allocator, self.config);
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
pub fn parseZonSafely(
    comptime T: type,
    allocator: std.mem.Allocator,
    content: []const u8,
    default_value: T,
) ManagedZonConfig(T) {
    const parsed = ZonParser.parseFromSlice(T, allocator, content) catch {
        // On parse error, use default (no freeing needed)
        return ManagedZonConfig(T).initDefault(allocator, default_value);
    };

    // Success - parsed data needs freeing
    return ManagedZonConfig(T).initParsed(allocator, parsed);
}

/// Arena-based ZON parsing for temporary usage (like tests)
/// All allocations are cleaned up when arena is deinitialized
pub const ArenaZonParser = struct {
    arena: std.heap.ArenaAllocator,

    pub fn init(backing_allocator: std.mem.Allocator) ArenaZonParser {
        return ArenaZonParser{
            .arena = std.heap.ArenaAllocator.init(backing_allocator),
        };
    }

    pub fn deinit(self: *ArenaZonParser) void {
        self.arena.deinit();
    }

    /// Parse ZON with arena allocator - no need for individual freeing
    pub fn parseFromSlice(self: *ArenaZonParser, comptime T: type, content: []const u8) !T {
        return ZonParser.parseFromSlice(T, self.arena.allocator(), content);
    }

    /// Parse with default fallback
    pub fn parseFromSliceWithDefault(self: *ArenaZonParser, comptime T: type, content: []const u8, default_value: T) T {
        return self.parseFromSlice(T, content) catch default_value;
    }
};

test "ManagedZonConfig with parsed data" {
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
    const parsed = try ZonParser.parseFromSlice(TestConfig, testing.allocator, test_content);
    var managed = ManagedZonConfig(TestConfig).initParsed(testing.allocator, parsed);
    defer managed.deinit();

    // Verify data
    try testing.expectEqualStrings("test", managed.get().name);
    try testing.expectEqual(@as(u32, 42), managed.get().value);
    try testing.expect(managed.wasParsed());
}

test "ManagedZonConfig with default data" {
    const testing = std.testing;

    const TestConfig = struct {
        name: []const u8 = "default",
        value: u32 = 0,
    };

    const default_config = TestConfig{};
    var managed = ManagedZonConfig(TestConfig).initDefault(testing.allocator, default_config);
    defer managed.deinit(); // Safe to call, won't free anything

    // Verify data
    try testing.expectEqualStrings("default", managed.get().name);
    try testing.expectEqual(@as(u32, 0), managed.get().value);
    try testing.expect(!managed.wasParsed());
}

test "parseZonSafely with valid content" {
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
    var managed = parseZonSafely(TestConfig, testing.allocator, test_content, default_config);
    defer managed.deinit();

    try testing.expectEqualStrings("test", managed.get().name);
    try testing.expectEqual(@as(u32, 42), managed.get().value);
    try testing.expect(managed.wasParsed());
}

test "parseZonSafely with invalid content" {
    const testing = std.testing;

    const TestConfig = struct {
        name: []const u8 = "default",
        value: u32 = 0,
    };

    const invalid_content = "{ invalid zon }";
    const default_config = TestConfig{};
    var managed = parseZonSafely(TestConfig, testing.allocator, invalid_content, default_config);
    defer managed.deinit(); // Safe - uses default, no freeing needed

    try testing.expectEqualStrings("default", managed.get().name);
    try testing.expectEqual(@as(u32, 0), managed.get().value);
    try testing.expect(!managed.wasParsed());
}

test "ArenaZonParser basic usage" {
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

    var arena_parser = ArenaZonParser.init(testing.allocator);
    defer arena_parser.deinit(); // Cleans up all allocations automatically

    const parsed = try arena_parser.parseFromSlice(TestConfig, test_content);
    try testing.expectEqualStrings("test", parsed.name);
    try testing.expectEqual(@as(u32, 42), parsed.value);

    // No need for individual freeing - arena cleans up everything
}
