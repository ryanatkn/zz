const std = @import("std");

/// Idiomatic Zig ownership patterns - clear naming and explicit ownership transfer
/// Philosophy: Use the type system and naming to make ownership clear, no hidden behavior
/// Clear ownership through function naming conventions
/// - initOwning() functions take ownership of parameters
/// - initBorrowing() functions borrow parameters (caller retains ownership)
/// - moveX() functions transfer ownership and invalidate the source
/// - toOwnedX() functions return ownership to caller
/// Helper for config patterns - determines if config should be owned or borrowed
pub const ConfigOwnership = enum {
    /// Function makes a copy of config or only needs it during initialization
    borrowed,
    /// Function stores config long-term, needs to own it
    owned,
};

/// Simple arena-based temporary allocations - idiomatic Zig pattern
pub const TempAllocator = struct {
    arena: std.heap.ArenaAllocator,

    pub fn init(backing_allocator: std.mem.Allocator) TempAllocator {
        return TempAllocator{
            .arena = std.heap.ArenaAllocator.init(backing_allocator),
        };
    }

    pub fn allocator(self: *TempAllocator) std.mem.Allocator {
        return self.arena.allocator();
    }

    /// Reset all temporary allocations - idiomatic for arenas
    pub fn reset(self: *TempAllocator) void {
        self.arena.deinit();
        self.arena = std.heap.ArenaAllocator.init(self.arena.child_allocator);
    }

    pub fn deinit(self: *TempAllocator) void {
        self.arena.deinit();
    }
};

/// Builder pattern - simple, clear ownership transfer on build()
pub fn SimpleBuilder(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        // Build state would go here

        pub fn init(allocator: std.mem.Allocator) Self {
            return Self{
                .allocator = allocator,
            };
        }

        /// Transfer ownership of built object to caller
        pub fn build(self: *Self) !T {
            _ = self; // Mark parameter as unused - this is a placeholder implementation
            // Build the object using self.allocator
            // Ownership transfers to caller
            return undefined; // Placeholder
        }

        // Builder methods would go here - simple, no state tracking
    };
}

// Example patterns for clear ownership

/// Demonstrates config ownership patterns
const ExampleConfig = struct {
    value: u32,

    pub fn deinit(self: *ExampleConfig, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
        // Would cleanup allocated resources
    }
};

/// Example consumer that borrows config (doesn't take ownership)
const ExampleConsumerBorrowing = struct {
    value: u32,

    /// Clear naming: we borrow the config, caller keeps ownership
    pub fn initBorrowing(allocator: std.mem.Allocator, config: *const ExampleConfig) !ExampleConsumerBorrowing {
        _ = allocator;
        return ExampleConsumerBorrowing{ .value = config.value };
    }

    // No deinit needed since we don't own anything
};

/// Example consumer that takes ownership
const ExampleConsumerOwning = struct {
    config: ExampleConfig,

    /// Clear naming: we take ownership of config, caller should not use it after
    pub fn initOwning(allocator: std.mem.Allocator, config: ExampleConfig) !ExampleConsumerOwning {
        _ = allocator;
        return ExampleConsumerOwning{ .config = config };
    }

    pub fn deinit(self: *ExampleConsumerOwning, allocator: std.mem.Allocator) void {
        self.config.deinit(allocator);
    }
};

test "idiomatic ownership patterns" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Pattern 1: Borrowing (caller retains ownership)
    var config = ExampleConfig{ .value = 42 };
    defer config.deinit(allocator); // Caller responsible for cleanup

    const consumer1 = try ExampleConsumerBorrowing.initBorrowing(allocator, &config);
    _ = consumer1;
    // config is still valid and owned by us

    // Pattern 2: Transfer ownership (config moves to consumer)
    const config2 = ExampleConfig{ .value = 24 };
    var consumer2 = try ExampleConsumerOwning.initOwning(allocator, config2);
    defer consumer2.deinit(allocator); // Consumer now owns config
    // config2 should not be used after initOwning call
}

test "temporary allocator pattern" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var temp = TempAllocator.init(allocator);
    defer temp.deinit();

    // Use temp allocator for short-lived allocations
    const temp_slice = try temp.allocator().alloc(u32, 10);
    _ = temp_slice;

    // Reset clears all allocations at once
    temp.reset();

    // More temporary allocations...
    const temp_slice2 = try temp.allocator().alloc(u8, 20);
    _ = temp_slice2;

    // All freed on deinit
}
