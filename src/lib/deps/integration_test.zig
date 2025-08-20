// Integration tests for cross-module functionality
const std = @import("std");
const LockGuard = @import("lock.zig").LockGuard;
const path = @import("../core/path.zig");
const process = @import("../core/process.zig");

test "Lock module - PID management" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test lock acquisition and release (using real filesystem since lock uses PID operations)
    var lock = LockGuard.acquire(allocator, "/tmp") catch |err| switch (err) {
        error.LockHeld => {
            // Lock already held, which is fine for testing
            return;
        },
        else => return err,
    };
    defer lock.deinit();

    // The lock was successfully acquired and will be released by deinit
}

test "Path utilities integration" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test path joining with dependency-style paths
    const joined = try path.joinPath(allocator, "deps", "tree-sitter");
    defer allocator.free(joined);

    try testing.expectEqualStrings("deps/tree-sitter", joined);

    // Test with longer paths
    const long_joined = try path.joinPath(allocator, "deps", "tree-sitter-typescript");
    defer allocator.free(long_joined);

    try testing.expectEqualStrings("deps/tree-sitter-typescript", long_joined);

    // Test multi-component paths
    const multi_path = try path.joinPaths(allocator, &.{ "deps", ".tmp", "tree-sitter-123456" });
    defer allocator.free(multi_path);

    try testing.expectEqualStrings("deps/.tmp/tree-sitter-123456", multi_path);
}

test "Process module integration" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test git args building
    var git_args = try process.buildGitArgs(allocator, &.{ "status", "--porcelain" });
    defer git_args.deinit();

    try testing.expectEqualStrings("git", git_args.items[0]);
    try testing.expectEqualStrings("status", git_args.items[1]);
    try testing.expectEqualStrings("--porcelain", git_args.items[2]);

    // Test command output parsing
    const raw_output = "  abc123def456  \n  ";
    const parsed = try process.parseCommandOutput(allocator, raw_output);
    defer allocator.free(parsed);

    try testing.expectEqualStrings("abc123def456", parsed);
}
