const std = @import("std");
const io = @import("../core/io.zig");

/// Simple change detection using content hashing
pub const ChangeDetector = struct {
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    /// Hash the content of deps.zon file for change detection
    pub fn hashDepsZon(self: *Self, path: []const u8) !u64 {
        const content = io.readFileOptional(self.allocator, path) catch |err| switch (err) {
            error.FileNotFound => return 0, // No deps.zon = hash of 0
            else => return err,
        };

        if (content) |c| {
            defer self.allocator.free(c);
            return std.hash.XxHash64.hash(0, c);
        } else {
            return 0;
        }
    }

    /// Get the last known hash from state file
    pub fn getLastHash(self: *Self, state_path: []const u8) !u64 {
        const content = io.readFileOptional(self.allocator, state_path) catch |err| switch (err) {
            error.FileNotFound => return 0, // No state file = hash of 0
            else => return err,
        };

        if (content) |c| {
            defer self.allocator.free(c);

            // Parse simple format: deps_zon_hash=12345
            var lines = std.mem.splitSequence(u8, c, "\n");
            while (lines.next()) |line| {
                const trimmed = std.mem.trim(u8, line, " \t\r\n");
                if (std.mem.startsWith(u8, trimmed, "deps_zon_hash=")) {
                    const hash_str = trimmed[14..]; // Skip "deps_zon_hash="
                    return std.fmt.parseInt(u64, hash_str, 10) catch 0;
                }
            }
        }

        return 0;
    }

    /// Save the current hash to state file
    pub fn saveHash(self: *Self, state_path: []const u8, hash: u64) !void {
        const content = try std.fmt.allocPrint(self.allocator, "deps_zon_hash={d}\n", .{hash});
        defer self.allocator.free(content);

        try io.writeFile(state_path, content);
    }

    /// Check if deps.zon has changed since last check
    pub fn hasChanged(self: *Self, deps_zon_path: []const u8, state_path: []const u8) !bool {
        const current_hash = try self.hashDepsZon(deps_zon_path);
        const last_hash = try self.getLastHash(state_path);

        const changed = current_hash != last_hash;

        // Update state if changed
        if (changed) {
            try self.saveHash(state_path, current_hash);
        }

        return changed;
    }
};

// Tests
test "ChangeDetector - hash empty content" {
    const testing = std.testing;
    var detector = ChangeDetector.init(testing.allocator);

    // Non-existent file should hash to 0
    const hash = try detector.hashDepsZon("non-existent.zon");
    try testing.expect(hash == 0);
}

test "ChangeDetector - hash consistent content" {
    const testing = std.testing;
    var detector = ChangeDetector.init(testing.allocator);

    // Create temporary file
    const tmp_dir = testing.tmpDir(.{});
    const test_file = try tmp_dir.dir.realpathAlloc(testing.allocator, "test.zon");
    defer testing.allocator.free(test_file);

    // Write test content
    try tmp_dir.dir.writeFile(.{ .sub_path = "test.zon", .data = ".{ .dependencies = .{} }" });

    // Hash should be consistent
    const hash1 = try detector.hashDepsZon(test_file);
    const hash2 = try detector.hashDepsZon(test_file);
    try testing.expect(hash1 == hash2);
    try testing.expect(hash1 != 0);
}

test "ChangeDetector - detect changes" {
    const testing = std.testing;
    var detector = ChangeDetector.init(testing.allocator);

    // Create temporary files
    const tmp_dir = testing.tmpDir(.{});
    const deps_file = try tmp_dir.dir.realpathAlloc(testing.allocator, "deps.zon");
    defer testing.allocator.free(deps_file);
    const state_file = try tmp_dir.dir.realpathAlloc(testing.allocator, ".deps_state");
    defer testing.allocator.free(state_file);

    // Initial content
    try tmp_dir.dir.writeFile(.{ .sub_path = "deps.zon", .data = ".{ .dependencies = .{} }" });

    // First check should detect change (no previous state)
    const changed1 = try detector.hasChanged(deps_file, state_file);
    try testing.expect(changed1 == true);

    // Second check should not detect change
    const changed2 = try detector.hasChanged(deps_file, state_file);
    try testing.expect(changed2 == false);

    // Modify content
    try tmp_dir.dir.writeFile(.{ .sub_path = "deps.zon", .data = ".{ .dependencies = .{ .test = .{} } }" });

    // Third check should detect change
    const changed3 = try detector.hasChanged(deps_file, state_file);
    try testing.expect(changed3 == true);

    // Fourth check should not detect change
    const changed4 = try detector.hasChanged(deps_file, state_file);
    try testing.expect(changed4 == false);
}
