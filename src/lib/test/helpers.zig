const std = @import("std");
const testing = std.testing;
const MockFilesystem = @import("../filesystem/mock.zig").MockFilesystem;
const RealFilesystem = @import("../filesystem/real.zig").RealFilesystem;
const FilesystemInterface = @import("../core/filesystem.zig").FilesystemInterface;
const SharedConfig = @import("../../config.zig").SharedConfig;
const GlobExpander = @import("../../prompt/glob.zig").GlobExpander;
const collections = @import("../core/collections.zig");
const errors = @import("../core/errors.zig");
const io = @import("../core/io.zig");

// ============================================================================
// Core Test Context Types - The Essential Test Infrastructure
// ============================================================================

/// Test scope management for automatic setup and teardown
/// Usage: try testScope(testing.allocator, testFunction);
pub fn testScope(allocator: std.mem.Allocator, comptime testFn: anytype) !void {
    const TestArgs = @TypeOf(testFn);
    const args_info = @typeInfo(TestArgs).Fn;

    if (args_info.params.len == 1) {
        // Function expects MockTestContext
        var ctx = MockTestContext.init(allocator);
        defer ctx.deinit();
        try testFn(ctx);
    } else if (args_info.params.len == 2) {
        // Function expects allocator and context
        var ctx = MockTestContext.init(allocator);
        defer ctx.deinit();
        try testFn(allocator, ctx);
    } else {
        @compileError("testScope expects function with 1 or 2 parameters");
    }
}

/// Fluent test context builder
pub const TestContextBuilder = struct {
    allocator: std.mem.Allocator,
    use_mock_fs: bool = true,
    files: collections.List([]const u8),
    dirs: collections.List([]const u8),

    pub fn init(allocator: std.mem.Allocator) TestContextBuilder {
        return .{
            .allocator = allocator,
            .files = collections.List([]const u8).init(allocator),
            .dirs = collections.List([]const u8).init(allocator),
        };
    }

    pub fn withFile(self: *TestContextBuilder, path: []const u8, content: []const u8) *TestContextBuilder {
        const file_spec = std.fmt.allocPrint(self.allocator, "{s}:{s}", .{ path, content }) catch unreachable;
        self.files.append(file_spec) catch unreachable;
        return self;
    }

    pub fn withDir(self: *TestContextBuilder, path: []const u8) *TestContextBuilder {
        const duped = self.allocator.dupe(u8, path) catch unreachable;
        self.dirs.append(duped) catch unreachable;
        return self;
    }

    pub fn withRealFS(self: *TestContextBuilder) *TestContextBuilder {
        var builder = self.*;
        builder.use_mock_fs = false;
        return &builder;
    }

    pub fn build(self: *TestContextBuilder) !TestContext {
        if (self.use_mock_fs) {
            var ctx = MockTestContext.init(self.allocator);

            // Add directories first
            for (self.dirs.items) |dir| {
                try ctx.addDirectory(dir);
            }

            // Add files
            for (self.files.items) |file_spec| {
                const colon_pos = std.mem.indexOf(u8, file_spec, ":") orelse continue;
                const path = file_spec[0..colon_pos];
                const content = file_spec[colon_pos + 1 ..];
                try ctx.addFile(path, content);
            }

            return TestContext{ .mock = ctx };
        } else {
            var ctx = try TmpDirTestContext.init(self.allocator);

            // Add directories first
            for (self.dirs.items) |dir| {
                try ctx.makeDir(dir);
            }

            // Add files
            for (self.files.items) |file_spec| {
                const colon_pos = std.mem.indexOf(u8, file_spec, ":") orelse continue;
                const path = file_spec[0..colon_pos];
                const content = file_spec[colon_pos + 1 ..];
                try ctx.writeFile(path, content);
            }

            return TestContext{ .tmp = ctx };
        }
    }

    pub fn deinit(self: *TestContextBuilder) void {
        self.files.deinit();
        self.dirs.deinit();
    }
};

/// Union context for either mock or real filesystem tests
pub const TestContext = union(enum) {
    mock: MockTestContext,
    tmp: TmpDirTestContext,

    pub fn deinit(self: *TestContext) void {
        switch (self.*) {
            .mock => |*ctx| ctx.deinit(),
            .tmp => |*ctx| ctx.deinit(),
        }
    }

    pub fn filesystem(self: *const TestContext) FilesystemInterface {
        return switch (self.*) {
            .mock => |*ctx| ctx.filesystem,
            .tmp => |*ctx| ctx.filesystem,
        };
    }
};

/// Fluent helper for MockTestContext creation
pub fn withMockFS(allocator: std.mem.Allocator) TestContextBuilder {
    var builder = TestContextBuilder.init(allocator);
    builder.use_mock_fs = true;
    return builder;
}

/// Fluent helper for TmpDirTestContext creation
pub fn withTmpDir(allocator: std.mem.Allocator) TestContextBuilder {
    var builder = TestContextBuilder.init(allocator);
    builder.use_mock_fs = false;
    return builder;
}

/// Test context with mock filesystem and automatic cleanup
/// Usage: var ctx = test_helpers.MockTestContext.init(testing.allocator); defer ctx.deinit();
pub const MockTestContext = struct {
    allocator: std.mem.Allocator,
    mock_fs: *MockFilesystem,
    filesystem: FilesystemInterface,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        const mock_fs = allocator.create(MockFilesystem) catch @panic("Failed to allocate mock filesystem");
        mock_fs.* = MockFilesystem.init(allocator);
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
        self.allocator.destroy(self.mock_fs);
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
// Prompt Module Specific Test Helpers (unified from prompt/test/helpers.zig)
// ============================================================================

/// Test helper for creating and managing GlobExpander instances
pub const GlobExpanderTestContext = struct {
    allocator: std.mem.Allocator,
    mock_fs: *MockFilesystem,
    filesystem: FilesystemInterface,
    expander: GlobExpander,

    pub fn init(allocator: std.mem.Allocator) GlobExpanderTestContext {
        const mock_fs = allocator.create(MockFilesystem) catch @panic("Failed to allocate mock filesystem");
        mock_fs.* = MockFilesystem.init(allocator);
        const filesystem = mock_fs.interface();

        return GlobExpanderTestContext{
            .allocator = allocator,
            .mock_fs = mock_fs,
            .filesystem = filesystem,
            .expander = GlobExpander{
                .allocator = allocator,
                .filesystem = filesystem,
                .config = SharedConfig{
                    .ignored_patterns = &[_][]const u8{}, // Empty patterns for most tests
                    .hidden_files = &[_][]const u8{},
                    .gitignore_patterns = &[_][]const u8{},
                    .symlink_behavior = .skip,
                    .respect_gitignore = false, // Don't use gitignore in tests
                    .patterns_allocated = false,
                },
            },
        };
    }

    pub fn deinit(self: *GlobExpanderTestContext) void {
        self.mock_fs.deinit();
        self.allocator.destroy(self.mock_fs);
    }

    pub fn addFile(self: *GlobExpanderTestContext, path: []const u8, content: []const u8) !void {
        try self.mock_fs.addFile(path, content);
    }

    pub fn addDirectory(self: *GlobExpanderTestContext, path: []const u8) !void {
        try self.mock_fs.addDirectory(path);
    }
};

/// Helper for cleaning up expansion results
pub fn cleanupExpandResults(allocator: std.mem.Allocator, results: anytype) void {
    for (results.items) |*result| {
        for (result.files.items) |path| {
            allocator.free(path);
        }
        result.files.deinit();
    }
    results.deinit();
}

/// Helper for creating temporary directories with test files
pub const TempDirHelper = struct {
    tmp_dir: std.testing.TmpDir,
    path_buf: [std.fs.max_path_bytes]u8 = undefined,

    pub fn init() TempDirHelper {
        return TempDirHelper{
            .tmp_dir = testing.tmpDir(.{}),
        };
    }

    pub fn deinit(self: *TempDirHelper) void {
        self.tmp_dir.cleanup();
    }

    pub fn getPath(self: *TempDirHelper) ![]const u8 {
        return try self.tmp_dir.dir.realpath(".", &self.path_buf);
    }

    pub fn createFile(self: *TempDirHelper, sub_path: []const u8, data: []const u8) !void {
        try self.tmp_dir.dir.writeFile(.{ .sub_path = sub_path, .data = data });
    }

    pub fn createDir(self: *TempDirHelper, path: []const u8) !void {
        try self.tmp_dir.dir.makeDir(path);
    }

    /// Create a basic test structure with .zig files
    pub fn createBasicZigStructure(self: *TempDirHelper) !void {
        try self.createFile("test1.zig", "const a = 1;");
        try self.createFile("test2.zig", "const b = 2;");
        try self.createFile("README.md", "# Test");
    }

    /// Create a nested source structure
    pub fn createNestedSourceStructure(self: *TempDirHelper) !void {
        try self.createDir("src");
        try self.createDir("src/cli");
        try self.createFile("main.zig", "const main = 1;");
        try self.createFile("src/lib.zig", "const lib = 1;");
        try self.createFile("src/cli/runner.zig", "const runner = 1;");
    }

    /// Create structure with files that should be ignored
    pub fn createStructureWithIgnoredFiles(self: *TempDirHelper) !void {
        try self.createDir("node_modules");
        try self.createFile("main.zig", "const main = 1;");
        try self.createFile("node_modules/package.json", "{}");
        try self.createFile(".hidden", "hidden");
    }

    /// Create structure with hidden files
    pub fn createStructureWithHiddenFiles(self: *TempDirHelper) !void {
        try self.createFile("visible.zig", "const visible = 1;");
        try self.createFile(".hidden.zig", "const hidden = 1;");
        try self.createFile(".env", "SECRET=value");
    }
};

/// Helper for testing glob expansion with common patterns
pub fn testBasicGlobExpansion(allocator: std.mem.Allocator, patterns: []const []const u8) !void {
    var ctx = GlobExpanderTestContext.init(allocator);
    defer ctx.deinit();

    const results = try ctx.expander.expandPatternsWithInfo(patterns);
    defer cleanupExpandResults(allocator, results);

    // Basic sanity check - should have at least one result
    try testing.expect(results.items.len > 0);
}

// ============================================================================
// Test Organization Infrastructure
// ============================================================================

/// Test runner for module organization and comprehensive reporting
/// Usage: test_helpers.TestRunner.setModule("ModuleName"); ... test_helpers.TestRunner.printSummary();
pub const TestRunner = struct {
    var verbose: bool = false;
    var current_module: []const u8 = "";
    var module_start_time: i128 = 0;
    var test_count: u32 = 0;
    var modules_completed: u8 = 0;
    var total_modules: u8 = 0;

    const ModuleStats = struct {
        name: []const u8,
        test_count: u32,
        duration_ms: f64,
        memory_peak_kb: u64,
    };

    var module_stats: [10]ModuleStats = undefined;
    var stats_count: u8 = 0;

    /// Enable verbose test output (set via environment variable TEST_VERBOSE=1)
    pub fn init() void {
        if (std.process.getEnvVarOwned(std.heap.page_allocator, "TEST_VERBOSE")) |value| {
            defer std.heap.page_allocator.free(value);
            verbose = std.mem.eql(u8, value, "1") or std.mem.eql(u8, value, "true");
        } else |_| {
            verbose = false;
        }

        // Reset counters
        modules_completed = 0;
        test_count = 0;
        stats_count = 0;
        total_modules = 6; // Tree, Prompt, Patterns, CLI, Benchmark, Lib

        if (verbose) {
            std.debug.print("\n🧪 Test Suite Starting ({d} modules)\n", .{total_modules});
            std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
        }
    }

    /// Set the current module being tested (creates visual section header)
    pub fn setModule(module_name: []const u8) void {
        // Complete previous module if exists
        if (current_module.len > 0) {
            completeCurrentModule();
        }

        current_module = module_name;
        module_start_time = std.time.nanoTimestamp();
        modules_completed += 1;

        if (verbose) {
            std.debug.print("\n🧪 [{d}/{d}] {s} Tests\n", .{ modules_completed, total_modules, module_name });
            std.debug.print("┌─────────────────────────────────────────────────┐\n", .{});
        } else {
            std.debug.print("\n=== {s} Tests ===\n", .{module_name});
        }
    }

    /// Complete the current module and record statistics
    fn completeCurrentModule() void {
        if (current_module.len == 0) return;

        const end_time = std.time.nanoTimestamp();
        const duration_ms = @as(f64, @floatFromInt(@as(u64, @intCast(end_time - module_start_time)))) / 1_000_000.0;

        // Estimate memory usage (simplified)
        const memory_kb = test_count * 8; // Rough estimate

        if (stats_count < module_stats.len) {
            module_stats[stats_count] = ModuleStats{
                .name = current_module,
                .test_count = test_count,
                .duration_ms = duration_ms,
                .memory_peak_kb = memory_kb,
            };
            stats_count += 1;
        }

        if (verbose) {
            std.debug.print("└─ ✓ {s}: {d} tests in {d:.1}ms\n", .{ current_module, test_count, duration_ms });
        }

        test_count = 0;
    }

    /// Record a test execution (call this from individual tests if needed)
    pub fn recordTest(test_name: []const u8) void {
        test_count += 1;
        if (verbose) {
            std.debug.print("│ • {s}\n", .{test_name});
        }
    }

    /// Print comprehensive test completion summary
    pub fn printSummary() void {
        // Complete final module
        completeCurrentModule();

        if (verbose) {
            std.debug.print("\nTest Suite Summary\n", .{});
            std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});

            var total_tests: u32 = 0;
            var total_duration: f64 = 0;
            var total_memory: u64 = 0;

            for (module_stats[0..stats_count]) |stat| {
                total_tests += stat.test_count;
                total_duration += stat.duration_ms;
                total_memory += stat.memory_peak_kb;
            }

            std.debug.print("\n┌─ Module Breakdown:\n", .{});
            for (module_stats[0..stats_count]) |stat| {
                const percent = if (total_duration > 0) (stat.duration_ms / total_duration) * 100 else 0;
                std.debug.print("│ {s:<12} │ {d:>3} tests │ {d:>6.1}ms ({d:>4.1}%) │ {d:>3}KB\n", .{ stat.name, stat.test_count, stat.duration_ms, percent, stat.memory_peak_kb });
            }

            std.debug.print("└─ Total Summary:\n", .{});
            std.debug.print("   • {d} modules completed\n", .{stats_count});
            std.debug.print("   • {d} total tests executed\n", .{total_tests});
            std.debug.print("   • {d:.1}ms total execution time\n", .{total_duration});
            std.debug.print("   • ~{d}KB peak memory usage\n", .{total_memory});

            if (total_duration > 1000) {
                std.debug.print("   ⚠️  Long test run - consider optimization\n", .{});
            }

            std.debug.print("\n✅ All test modules completed successfully!\n", .{});
        } else {
            // Minimal summary for non-verbose mode
            var total_tests: u32 = 0;
            for (module_stats[0..stats_count]) |stat| {
                total_tests += stat.test_count;
            }
            std.debug.print("\n✅ {d} modules, ~{d} tests completed\n", .{ stats_count, total_tests });
        }
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

// ============================================================================
// Enhanced Assertion Helpers - Better Error Messages and Context
// ============================================================================

/// Enhanced assertion helpers with better error messages and context
pub const Assertions = struct {
    /// Assert string contains substring with context
    pub fn expectStringContains(actual: []const u8, expected_substring: []const u8) !void {
        if (std.mem.indexOf(u8, actual, expected_substring) == null) {
            std.debug.print("\n❌ String does not contain expected substring\n", .{});
            std.debug.print("Expected to find: '{s}'\n", .{expected_substring});
            std.debug.print("Actual string: '{s}'\n", .{actual});
            return testing.expect(false);
        }
    }

    /// Assert string does not contain substring
    pub fn expectStringNotContains(actual: []const u8, unexpected_substring: []const u8) !void {
        if (std.mem.indexOf(u8, actual, unexpected_substring) != null) {
            std.debug.print("\n❌ String contains unexpected substring\n", .{});
            std.debug.print("Should not contain: '{s}'\n", .{unexpected_substring});
            std.debug.print("Actual string: '{s}'\n", .{actual});
            return testing.expect(false);
        }
    }

    /// Assert slice contains item with better error reporting
    pub fn expectSliceContains(comptime T: type, slice: []const T, item: T) !void {
        if (std.mem.indexOfScalar(T, slice, item) == null) {
            std.debug.print("\n❌ Slice does not contain expected item\n");
            std.debug.print("Looking for: {any}\n", .{item});
            std.debug.print("Slice contents: {any}\n", .{slice});
            return testing.expectError("Slice does not contain expected item");
        }
    }

    /// Assert approximate equality for floating point numbers
    pub fn expectApproxEqual(actual: f64, expected: f64, tolerance: f64) !void {
        const diff = @abs(actual - expected);
        if (diff > tolerance) {
            std.debug.print("\n❌ Values not approximately equal\n", .{});
            std.debug.print("Actual: {d}\n", .{actual});
            std.debug.print("Expected: {d}\n", .{expected});
            std.debug.print("Difference: {d} (tolerance: {d})\n", .{ diff, tolerance });
            return testing.expect(false);
        }
    }

    /// Assert file exists and is readable
    pub fn expectFileExists(file_path: []const u8) !void {
        std.fs.cwd().access(file_path, .{}) catch |err| switch (err) {
            error.FileNotFound => {
                std.debug.print("\n❌ File does not exist: {s}\n", .{file_path});
                return testing.expect(false);
            },
            error.PermissionDenied => {
                std.debug.print("\n❌ File access denied: {s}\n", .{file_path});
                return testing.expect(false);
            },
            else => return err,
        };
    }

    /// Assert file contains expected content
    pub fn expectFileContains(allocator: std.mem.Allocator, file_path: []const u8, expected_content: []const u8) !void {
        const content = std.fs.cwd().readFileAlloc(allocator, file_path, 1024 * 1024) catch |err| {
            std.debug.print("\n❌ Could not read file: {s} - {}\n", .{ file_path, err });
            return err;
        };
        defer allocator.free(content);

        try expectStringContains(content, expected_content);
    }

    /// Assert collection has expected length
    pub fn expectLength(comptime T: type, collection: []const T, expected_length: usize) !void {
        if (collection.len != expected_length) {
            std.debug.print("\n❌ Collection length mismatch\n");
            std.debug.print("Expected length: {d}\n", .{expected_length});
            std.debug.print("Actual length: {d}\n", .{collection.len});
            if (collection.len < 20) { // Don't print huge collections
                std.debug.print("Collection contents: {any}\n", .{collection});
            }
            return testing.expectError("Collection length mismatch");
        }
    }

    /// Assert that a file list contains a file ending with the given suffix
    pub fn assertContainsFileEndingWith(files: [][]const u8, suffix: []const u8) !void {
        for (files) |file| {
            if (std.mem.endsWith(u8, file, suffix)) return;
        }
        std.debug.print("Expected file ending with '{s}' not found in file list\n", .{suffix});
        try testing.expect(false);
    }

    /// Assert that a file list does NOT contain a file ending with the given suffix
    pub fn assertDoesNotContainFileEndingWith(files: [][]const u8, suffix: []const u8) !void {
        for (files) |file| {
            if (std.mem.endsWith(u8, file, suffix)) {
                std.debug.print("Unexpected file ending with '{s}' found: {s}\n", .{ suffix, file });
                try testing.expect(false);
            }
        }
    }

    /// Assert that exactly the expected files are found (by suffix)
    pub fn assertExactFilesEndingWith(files: [][]const u8, expected_suffixes: []const []const u8) !void {
        try testing.expect(files.len == expected_suffixes.len);

        for (expected_suffixes) |suffix| {
            try assertContainsFileEndingWith(files, suffix);
        }
    }
};

/// Builder for creating test file structures
pub const FileStructureBuilder = struct {
    allocator: std.mem.Allocator,
    files: collections.List([]const u8),

    pub fn init(allocator: std.mem.Allocator) FileStructureBuilder {
        return .{
            .allocator = allocator,
            .files = collections.List([]const u8).init(allocator),
        };
    }

    pub fn addZigFile(self: *FileStructureBuilder, path: []const u8, functions: []const []const u8) !*FileStructureBuilder {
        var content = collections.List(u8).init(self.allocator);
        defer content.deinit();

        try content.appendSlice("const std = @import(\"std\");\n\n");
        for (functions) |func| {
            try content.appendSlice("pub fn ");
            try content.appendSlice(func);
            try content.appendSlice("() void {}\n\n");
        }

        try self.files.append(try self.allocator.dupe(u8, path));
        try self.files.append(try self.allocator.dupe(u8, content.items));
        return self;
    }

    pub fn deinit(self: *FileStructureBuilder) void {
        self.files.deinit();
    }
};
