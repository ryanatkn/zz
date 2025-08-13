const std = @import("std");
const testing = std.testing;
const MockFilesystem = @import("filesystem.zig").MockFilesystem;
const RealFilesystem = @import("filesystem.zig").RealFilesystem;
const FilesystemInterface = @import("filesystem.zig").FilesystemInterface;
const SharedConfig = @import("config.zig").SharedConfig;
const GlobExpander = @import("prompt/glob.zig").GlobExpander;

// ============================================================================
// Core Test Context Types - The Essential Test Infrastructure
// ============================================================================

/// Test context with mock filesystem and automatic cleanup
/// Usage: var ctx = test_helpers.MockTestContext.init(testing.allocator); defer ctx.deinit();
pub const MockTestContext = struct {
    allocator: std.mem.Allocator,
    mock_fs: MockFilesystem,
    filesystem: FilesystemInterface,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        var mock_fs = MockFilesystem.init(allocator);
        // Ensure current directory exists for cwd() calls
        mock_fs.addDirectory(".") catch {};
        return Self{
            .allocator = allocator,
            .mock_fs = mock_fs,
            .filesystem = mock_fs.interface(),
        };
    }

    pub fn deinit(self: *Self) void {
        self.mock_fs.deinit();
    }

    pub fn addFile(self: *Self, path: []const u8, content: []const u8) !void {
        try self.mock_fs.addFile(path, content);
    }

    pub fn addDirectory(self: *Self, path: []const u8) !void {
        try self.mock_fs.addDirectory(path);
    }
};

/// Test context with real temporary directory and automatic cleanup
/// Usage: var ctx = try test_helpers.TmpDirTestContext.init(testing.allocator); defer ctx.deinit();
pub const TmpDirTestContext = struct {
    allocator: std.mem.Allocator,
    tmp_dir: std.testing.TmpDir,
    filesystem: FilesystemInterface,
    path: []u8,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !Self {
        var tmp_dir = std.testing.tmpDir(.{});
        const filesystem = RealFilesystem.init();
        const path = try tmp_dir.dir.realpathAlloc(allocator, ".");
        return Self{
            .allocator = allocator,
            .tmp_dir = tmp_dir,
            .filesystem = filesystem,
            .path = path,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.path);
        self.tmp_dir.cleanup();
    }

    pub fn writeFile(self: *Self, sub_path: []const u8, data: []const u8) !void {
        try self.tmp_dir.dir.writeFile(.{ .sub_path = sub_path, .data = data });
    }

    pub fn makeDir(self: *Self, sub_path: []const u8) !void {
        try self.tmp_dir.dir.makeDir(sub_path);
    }

    pub fn makePath(self: *Self, sub_path: []const u8) !void {
        try self.tmp_dir.dir.makePath(sub_path);
    }
};

// ============================================================================
// Specialized Helpers for Common Test Patterns
// ============================================================================

/// Create a GlobExpander with test-friendly defaults for prompt module testing
/// Usage: const expander = test_helpers.createGlobExpander(testing.allocator, ctx.filesystem);
pub fn createGlobExpander(allocator: std.mem.Allocator, filesystem: FilesystemInterface) GlobExpander {
    return GlobExpander{
        .allocator = allocator,
        .filesystem = filesystem,
        .config = SharedConfig{
            .ignored_patterns = &[_][]const u8{}, // Empty patterns for testing
            .hidden_files = &[_][]const u8{},
            .gitignore_patterns = &[_][]const u8{},
            .symlink_behavior = .skip,
            .respect_gitignore = false, // Don't use gitignore in tests
            .patterns_allocated = false,
        },
    };
}

// ============================================================================
// Test Organization Infrastructure
// ============================================================================

/// Test runner for module organization and clean output
/// Usage: test_helpers.TestRunner.setModule("ModuleName"); ... test_helpers.TestRunner.printSummary();
pub const TestRunner = struct {
    var verbose: bool = false;

    /// Enable verbose test output (set via environment variable TEST_VERBOSE=1)
    pub fn init() void {
        if (std.process.getEnvVarOwned(std.heap.page_allocator, "TEST_VERBOSE")) |value| {
            defer std.heap.page_allocator.free(value);
            verbose = std.mem.eql(u8, value, "1") or std.mem.eql(u8, value, "true");
        } else |_| {
            verbose = false;
        }
    }

    /// Set the current module being tested (creates visual section header)
    pub fn setModule(module_name: []const u8) void {
        if (verbose) {
            std.debug.print("\n🧪 === {s} Tests ===\n", .{module_name});
        } else {
            std.debug.print("\n=== {s} Tests ===\n", .{module_name});
        }
    }

    /// Print test completion (clean, no verbose output by default)
    pub fn printSummary() void {
        // Clean module completion - Zig already provides test counts
    }

    /// Optional: Helper for timing specific test operations (not individual tests)
    pub fn timeOperation(comptime operation_name: []const u8, operation_fn: anytype) !void {
        if (!verbose) {
            return operation_fn();
        }

        const start = std.time.nanoTimestamp();
        std.debug.print("  ▶️  Running: {s}\n", .{operation_name});

        operation_fn() catch |err| {
            std.debug.print("  🞪 Failed: {s} - {}\n", .{ operation_name, err });
            return err;
        };

        const end = std.time.nanoTimestamp();
        const duration_ms = @as(f64, @floatFromInt(@as(u64, @intCast(end - start)))) / 1_000_000.0;
        if (duration_ms >= 10.0) {
            std.debug.print("  ✓ Completed: {s} ({d:.1}ms)\n", .{ operation_name, duration_ms });
        } else {
            std.debug.print("  ✓ Completed: {s} ({d:.2}ms)\n", .{ operation_name, duration_ms });
        }
    }
};
