const std = @import("std");
const testing = std.testing;
const GlobExpander = @import("../glob.zig").GlobExpander;
const MockFilesystem = @import("../../filesystem.zig").MockFilesystem;
const SharedConfig = @import("../../config.zig").SharedConfig;

/// Test helper for creating and managing GlobExpander instances
pub const GlobExpanderTestContext = struct {
    allocator: std.mem.Allocator,
    mock_fs: MockFilesystem,
    expander: GlobExpander,

    pub fn init(allocator: std.mem.Allocator) GlobExpanderTestContext {
        var mock_fs = MockFilesystem.init(allocator);
        const filesystem = mock_fs.interface();
        
        return GlobExpanderTestContext{
            .allocator = allocator,
            .mock_fs = mock_fs,
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
        try self.createFile("src/cli/args.zig", "const args = 1;");
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

/// Common test assertions
pub const TestAssertions = struct {
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

/// Helper for testing glob expansion with common patterns
pub fn testBasicGlobExpansion(allocator: std.mem.Allocator, patterns: []const []const u8) !void {
    var ctx = GlobExpanderTestContext.init(allocator);
    defer ctx.deinit();

    var results = try ctx.expander.expandPatternsWithInfo(patterns);
    defer cleanupExpandResults(allocator, results);

    // Basic sanity check - should have at least one result
    try testing.expect(results.items.len > 0);
}