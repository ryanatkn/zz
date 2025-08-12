const std = @import("std");
const testing = std.testing;
const MockFilesystem = @import("filesystem.zig").MockFilesystem;
const RealFilesystem = @import("filesystem.zig").RealFilesystem;
const FilesystemInterface = @import("filesystem.zig").FilesystemInterface;
const Config = @import("config.zig").Config;
const SharedConfig = @import("config.zig").SharedConfig;
const GlobExpander = @import("prompt/glob.zig").GlobExpander;
const PromptBuilder = @import("prompt/builder.zig").PromptBuilder;

// ============================================================================
// Core Test Context Types
// ============================================================================

/// Test context with mock filesystem and automatic cleanup
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

/// Performance test context with timing and memory tracking
pub const PerformanceTestContext = struct {
    allocator: std.mem.Allocator,
    timer: std.time.Timer,
    start_memory: usize,
    mock_fs: MockFilesystem,
    filesystem: FilesystemInterface,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !Self {
        var mock_fs = MockFilesystem.init(allocator);
        return Self{
            .allocator = allocator,
            .timer = try std.time.Timer.start(),
            .start_memory = 0, // TODO: Track actual memory usage
            .mock_fs = mock_fs,
            .filesystem = mock_fs.interface(),
        };
    }

    pub fn deinit(self: *Self) void {
        self.mock_fs.deinit();
    }

    pub fn elapsed(self: *Self) u64 {
        return self.timer.read();
    }

    pub fn elapsedMs(self: *Self) f64 {
        return @as(f64, @floatFromInt(self.elapsed())) / 1_000_000.0;
    }
};

// ============================================================================
// Common Directory Structure Builders
// ============================================================================

/// Create a typical Zig project structure
pub fn createZigProject(ctx: anytype) !void {
    const T = @TypeOf(ctx.*);
    if (T == MockTestContext) {
        try ctx.addDirectory("src");
        try ctx.addFile("src/main.zig", zigMainContent());
        try ctx.addFile("src/lib.zig", zigLibContent());
        try ctx.addFile("build.zig", buildZigContent());
        try ctx.addFile("build.zig.zon", buildZonContent());
        try ctx.addDirectory("zig-out");
        try ctx.addDirectory(".zig-cache");
    } else if (T == TmpDirTestContext) {
        try ctx.makePath("src");
        try ctx.writeFile("src/main.zig", zigMainContent());
        try ctx.writeFile("src/lib.zig", zigLibContent());
        try ctx.writeFile("build.zig", buildZigContent());
        try ctx.writeFile("build.zig.zon", buildZonContent());
        try ctx.makePath("zig-out");
        try ctx.makePath(".zig-cache");
    }
}

/// Create a Node.js project structure
pub fn createNodeProject(ctx: anytype) !void {
    const T = @TypeOf(ctx.*);
    if (T == MockTestContext) {
        try ctx.addFile("package.json", packageJsonContent());
        try ctx.addFile("index.js", nodeIndexContent());
        try ctx.addDirectory("node_modules");
        try ctx.addDirectory("node_modules/.bin");
        try ctx.addFile("node_modules/package.json", "{}");
        try ctx.addDirectory("src");
        try ctx.addFile("src/app.js", nodeAppContent());
    } else if (T == TmpDirTestContext) {
        try ctx.writeFile("package.json", packageJsonContent());
        try ctx.writeFile("index.js", nodeIndexContent());
        try ctx.makePath("node_modules/.bin");
        try ctx.writeFile("node_modules/package.json", "{}");
        try ctx.makePath("src");
        try ctx.writeFile("src/app.js", nodeAppContent());
    }
}

/// Create a Git repository structure
pub fn createGitRepository(ctx: anytype) !void {
    const T = @TypeOf(ctx.*);
    if (T == MockTestContext) {
        try ctx.addDirectory(".git");
        try ctx.addDirectory(".git/objects");
        try ctx.addDirectory(".git/refs");
        try ctx.addFile(".git/HEAD", "ref: refs/heads/main");
        try ctx.addFile(".gitignore", gitignoreContent());
        try ctx.addFile("README.md", "# Test Repository");
    } else if (T == TmpDirTestContext) {
        try ctx.makePath(".git/objects");
        try ctx.makePath(".git/refs");
        try ctx.writeFile(".git/HEAD", "ref: refs/heads/main");
        try ctx.writeFile(".gitignore", gitignoreContent());
        try ctx.writeFile("README.md", "# Test Repository");
    }
}

/// Create a nested tree structure for testing tree command
pub fn createTestTreeStructure(ctx: anytype) !void {
    const T = @TypeOf(ctx.*);
    if (T == MockTestContext) {
        try ctx.addDirectory("root");
        try ctx.addFile("root/file1.txt", "content1");
        try ctx.addDirectory("root/dir1");
        try ctx.addFile("root/dir1/file2.txt", "content2");
        try ctx.addDirectory("root/dir1/subdir");
        try ctx.addFile("root/dir1/subdir/file3.txt", "content3");
        try ctx.addDirectory("root/dir2");
        try ctx.addFile("root/dir2/file4.txt", "content4");
        try ctx.addDirectory("root/.hidden");
        try ctx.addFile("root/.hidden/secret.txt", "secret");
    } else if (T == TmpDirTestContext) {
        try ctx.makePath("root");
        try ctx.writeFile("root/file1.txt", "content1");
        try ctx.makePath("root/dir1/subdir");
        try ctx.writeFile("root/dir1/file2.txt", "content2");
        try ctx.writeFile("root/dir1/subdir/file3.txt", "content3");
        try ctx.makePath("root/dir2");
        try ctx.writeFile("root/dir2/file4.txt", "content4");
        try ctx.makePath("root/.hidden");
        try ctx.writeFile("root/.hidden/secret.txt", "secret");
    }
}

/// Create a performance test structure with many files
pub fn createPerformanceTestStructure(ctx: anytype, n_dirs: usize, n_files_per_dir: usize) !void {
    const T = @TypeOf(ctx.*);
    var i: usize = 0;
    while (i < n_dirs) : (i += 1) {
        const dir_name = try std.fmt.allocPrint(ctx.allocator, "dir_{d}", .{i});
        defer ctx.allocator.free(dir_name);
        
        if (T == MockTestContext) {
            try ctx.addDirectory(dir_name);
            var j: usize = 0;
            while (j < n_files_per_dir) : (j += 1) {
                const file_name = try std.fmt.allocPrint(ctx.allocator, "{s}/file_{d}.txt", .{dir_name, j});
                defer ctx.allocator.free(file_name);
                try ctx.addFile(file_name, "test content");
            }
        } else if (T == TmpDirTestContext) {
            try ctx.makeDir(dir_name);
            var j: usize = 0;
            while (j < n_files_per_dir) : (j += 1) {
                const file_name = try std.fmt.allocPrint(ctx.allocator, "{s}/file_{d}.txt", .{dir_name, j});
                defer ctx.allocator.free(file_name);
                try ctx.writeFile(file_name, "test content");
            }
        }
    }
}

// ============================================================================
// File Content Templates
// ============================================================================

pub fn zigMainContent() []const u8 {
    return 
        \\const std = @import("std");
        \\
        \\pub fn main() !void {
        \\    std.debug.print("Hello, world!\n", .{});
        \\}
    ;
}

pub fn zigLibContent() []const u8 {
    return 
        \\const std = @import("std");
        \\
        \\pub fn add(a: i32, b: i32) i32 {
        \\    return a + b;
        \\}
        \\
        \\test "add" {
        \\    try std.testing.expect(add(2, 3) == 5);
        \\}
    ;
}

pub fn zigTestContent() []const u8 {
    return 
        \\const std = @import("std");
        \\const testing = std.testing;
        \\
        \\test "basic test" {
        \\    try testing.expect(true);
        \\}
    ;
}

pub fn buildZigContent() []const u8 {
    return 
        \\const std = @import("std");
        \\
        \\pub fn build(b: *std.Build) void {
        \\    const exe = b.addExecutable(.{
        \\        .name = "test-app",
        \\        .root_source_file = b.path("src/main.zig"),
        \\        .target = b.standardTargetOptions(.{}),
        \\        .optimize = b.standardOptimizeOption(.{}),
        \\    });
        \\    b.installArtifact(exe);
        \\}
    ;
}

pub fn buildZonContent() []const u8 {
    return 
        \\.{
        \\    .name = "test-app",
        \\    .version = "0.1.0",
        \\    .dependencies = .{},
        \\    .paths = .{"."},
        \\}
    ;
}

pub fn packageJsonContent() []const u8 {
    return 
        \\{
        \\  "name": "test-app",
        \\  "version": "1.0.0",
        \\  "main": "index.js",
        \\  "scripts": {
        \\    "start": "node index.js",
        \\    "test": "echo \"No tests\""
        \\  }
        \\}
    ;
}

pub fn nodeIndexContent() []const u8 {
    return 
        \\console.log('Hello from Node.js!');
        \\require('./src/app');
    ;
}

pub fn nodeAppContent() []const u8 {
    return 
        \\module.exports = {
        \\  run: () => console.log('App running')
        \\};
    ;
}

pub fn gitignoreContent() []const u8 {
    return 
        \\node_modules/
        \\zig-out/
        \\.zig-cache/
        \\*.log
        \\.DS_Store
        \\Thumbs.db
    ;
}

pub fn gitConfigContent() []const u8 {
    return 
        \\[core]
        \\    repositoryformatversion = 0
        \\    filemode = true
        \\[user]
        \\    name = Test User
        \\    email = test@example.com
    ;
}

/// Generate binary content of specified size
pub fn binaryContent(allocator: std.mem.Allocator, size: usize) ![]u8 {
    const content = try allocator.alloc(u8, size);
    var rng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));
    rng.random().bytes(content);
    return content;
}

/// Generate Unicode test content
pub fn unicodeContent() []const u8 {
    return "Hello 世界 🌍 Здравствуй мир नमस्ते दुनिया";
}

// ============================================================================
// Memory Management Helpers
// ============================================================================

/// Cleanup helper for string arrays
pub fn cleanupStringArray(allocator: std.mem.Allocator, array: [][]const u8) void {
    for (array) |str| {
        allocator.free(str);
    }
    allocator.free(array);
}

/// Auto-cleanup list for strings
pub const AutoCleanupList = struct {
    allocator: std.mem.Allocator,
    items: std.ArrayList([]const u8),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .items = std.ArrayList([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.items.items) |item| {
            self.allocator.free(item);
        }
        self.items.deinit();
    }

    pub fn append(self: *Self, str: []const u8) !void {
        const owned = try self.allocator.dupe(u8, str);
        try self.items.append(owned);
    }

    pub fn toOwnedSlice(self: *Self) ![][]const u8 {
        return try self.items.toOwnedSlice();
    }
};

// ============================================================================
// Common Test Patterns as Functions
// ============================================================================

/// Run test with automatic mock filesystem setup/cleanup
pub fn withMockFilesystem(allocator: std.mem.Allocator, testFn: fn(*MockTestContext) anyerror!void) !void {
    var ctx = MockTestContext.init(allocator);
    defer ctx.deinit();
    try testFn(&ctx);
}

/// Run test with automatic temp directory setup/cleanup
pub fn withTmpDir(allocator: std.mem.Allocator, testFn: fn(*TmpDirTestContext) anyerror!void) !void {
    var ctx = try TmpDirTestContext.init(allocator);
    defer ctx.deinit();
    try testFn(&ctx);
}

/// Run test with a configured Config object
pub fn withConfig(
    allocator: std.mem.Allocator,
    filesystem: FilesystemInterface,
    args: [][:0]const u8,
    testFn: fn(*Config) anyerror!void
) !void {
    var config = try Config.fromArgs(allocator, filesystem, args);
    defer config.deinit();
    try testFn(&config);
}

/// Create a test Config with minimal defaults
pub fn createTestConfig(allocator: std.mem.Allocator) Config {
    return Config{
        .allocator = allocator,
        .shared_config = SharedConfig{
            .ignored_patterns = &[_][]const u8{},
            .hidden_files = &[_][]const u8{},
            .gitignore_patterns = &[_][]const u8{},
            .symlink_behavior = .skip,
            .respect_gitignore = false,
            .patterns_allocated = false,
        },
        .prepend_text = null,
        .append_text = null,
        .allow_empty_glob = false,
        .allow_missing = false,
    };
}

/// Create a GlobExpander with proper cleanup (with default config for testing)
pub fn createGlobExpander(allocator: std.mem.Allocator, filesystem: FilesystemInterface) GlobExpander {
    return GlobExpander{
        .allocator = allocator,
        .filesystem = filesystem,
        .config = SharedConfig{
            .ignored_patterns = &[_][]const u8{}, // Empty patterns
            .hidden_files = &[_][]const u8{},
            .gitignore_patterns = &[_][]const u8{},
            .symlink_behavior = .skip,
            .respect_gitignore = false, // Don't use gitignore in tests
            .patterns_allocated = false,
        },
    };
}

/// Create a PromptBuilder with proper cleanup
pub fn createPromptBuilder(allocator: std.mem.Allocator, filesystem: FilesystemInterface) PromptBuilder {
    return PromptBuilder.init(allocator, filesystem);
}

// ============================================================================
// Assertion Helpers
// ============================================================================

/// Assert that a file exists in the filesystem
pub fn expectFileExists(filesystem: FilesystemInterface, path: []const u8) !void {
    const stat = filesystem.statFile(path) catch |err| {
        std.debug.print("Expected file '{s}' to exist, but got error: {}\n", .{path, err});
        return error.FileNotFound;
    };
    try testing.expect(stat.kind == .file);
}

/// Assert that a directory exists in the filesystem
pub fn expectDirectoryExists(filesystem: FilesystemInterface, path: []const u8) !void {
    const stat = filesystem.statFile(path) catch |err| {
        std.debug.print("Expected directory '{s}' to exist, but got error: {}\n", .{path, err});
        return error.DirectoryNotFound;
    };
    try testing.expect(stat.kind == .directory);
}

/// Assert glob expansion matches expected files
pub fn expectGlobMatches(
    allocator: std.mem.Allocator,
    expander: GlobExpander,
    pattern: []const u8,
    expected: []const []const u8
) !void {
    var patterns = [_][]const u8{pattern};
    var results = try expander.expandGlobs(&patterns);
    defer {
        for (results.items) |item| {
            allocator.free(item);
        }
        results.deinit();
    }

    try testing.expectEqual(expected.len, results.items.len);
    for (expected) |expected_file| {
        var found = false;
        for (results.items) |result| {
            if (std.mem.eql(u8, result, expected_file)) {
                found = true;
                break;
            }
        }
        if (!found) {
            std.debug.print("Expected to find '{s}' in glob results\n", .{expected_file});
            return error.ExpectedFileNotFound;
        }
    }
}

/// Assert performance is within expected bounds
pub fn expectPerformanceWithin(ctx: *PerformanceTestContext, max_ms: f64) !void {
    const elapsed = ctx.elapsedMs();
    if (elapsed > max_ms) {
        std.debug.print("Performance test failed: {d:.2}ms > {d:.2}ms\n", .{elapsed, max_ms});
        return error.PerformanceTestFailed;
    }
}

/// Assert that config has expected patterns
pub fn expectConfigPatterns(config: *const SharedConfig, expected_patterns: []const []const u8) !void {
    for (expected_patterns) |pattern| {
        var found = false;
        for (config.ignored_patterns) |config_pattern| {
            if (std.mem.eql(u8, config_pattern, pattern)) {
                found = true;
                break;
            }
        }
        if (!found) {
            std.debug.print("Expected pattern '{s}' not found in config\n", .{pattern});
            return error.PatternNotFound;
        }
    }
}

// ============================================================================
// Path Utilities (POSIX only)
// ============================================================================

/// Join paths for tests (POSIX only)
pub fn joinPath(allocator: std.mem.Allocator, parts: []const []const u8) ![]u8 {
    var total_len: usize = 0;
    for (parts, 0..) |part, i| {
        total_len += part.len;
        if (i < parts.len - 1) {
            total_len += 1; // for separator
        }
    }
    
    var result = try allocator.alloc(u8, total_len);
    var offset: usize = 0;
    for (parts, 0..) |part, i| {
        @memcpy(result[offset..offset + part.len], part);
        offset += part.len;
        if (i < parts.len - 1) {
            result[offset] = '/';
            offset += 1;
        }
    }
    
    return result;
}

// ============================================================================
// Specialized Test Scenarios
// ============================================================================

/// Create files with various Unicode characters
pub fn createUnicodeTestFiles(ctx: anytype) !void {
    const T = @TypeOf(ctx.*);
    const files = [_]struct { name: []const u8, content: []const u8 }{
        .{ .name = "hello_世界.txt", .content = "Chinese characters" },
        .{ .name = "مرحبا.txt", .content = "Arabic text" },
        .{ .name = "привет.txt", .content = "Cyrillic text" },
        .{ .name = "🎉emoji🎊.txt", .content = "Emoji in filename" },
        .{ .name = "café.txt", .content = "Accented characters" },
    };

    for (files) |file| {
        if (T == MockTestContext) {
            try ctx.addFile(file.name, file.content);
        } else if (T == TmpDirTestContext) {
            try ctx.writeFile(file.name, file.content);
        }
    }
}

/// Create symlink test structure (only works with TmpDirTestContext)
pub fn createSymlinkTestStructure(ctx: *TmpDirTestContext) !void {
    try ctx.writeFile("target.txt", "target content");
    try ctx.makeDir("target_dir");
    try ctx.writeFile("target_dir/file.txt", "nested file");
    
    // Create symlinks
    try ctx.tmp_dir.dir.symLink("target.txt", "link_to_file.txt", .{});
    try ctx.tmp_dir.dir.symLink("target_dir", "link_to_dir", .{ .is_directory = true });
    try ctx.tmp_dir.dir.symLink("nonexistent", "broken_link.txt", .{});
}

/// Create files with various permissions (POSIX systems)
pub fn createPermissionTestStructure(ctx: *TmpDirTestContext) !void {
    try ctx.writeFile("readable.txt", "readable");
    try ctx.writeFile("writable.txt", "writable");
    try ctx.writeFile("executable.sh", "#!/bin/sh\necho test");
    
    // Note: Setting permissions requires platform-specific code
    // This is a placeholder for the structure
}