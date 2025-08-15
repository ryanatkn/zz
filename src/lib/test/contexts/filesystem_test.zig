const std = @import("std");
const testing = std.testing;
const MockFilesystem = @import("../../filesystem/mock.zig").MockFilesystem;
const FilesystemInterface = @import("../../filesystem/interface.zig").FilesystemInterface;

/// Specialized test context for filesystem operations using MockFilesystem
/// Reduces 30+ repeated filesystem test setups to standardized helpers
pub const FilesystemTestContext = struct {
    allocator: std.mem.Allocator,
    mock_fs: MockFilesystem,

    /// Initialize filesystem test context with mock filesystem
    pub fn init(allocator: std.mem.Allocator) !FilesystemTestContext {
        var mock_fs = MockFilesystem.init(allocator);
        return FilesystemTestContext{
            .allocator = allocator,
            .mock_fs = mock_fs,
        };
    }

    /// Cleanup filesystem test context
    pub fn deinit(self: *FilesystemTestContext) void {
        self.mock_fs.deinit();
    }

    /// Get filesystem interface for testing
    pub fn interface(self: *FilesystemTestContext) FilesystemInterface {
        return self.mock_fs.interface();
    }

    /// Setup files and directories for testing
    pub fn setupFiles(self: *FilesystemTestContext, files: []const struct { path: []const u8, content: []const u8 }) !void {
        for (files) |file| {
            // Create parent directories if needed
            if (std.fs.path.dirname(file.path)) |dirname| {
                try self.setupDirectories(&[_][]const u8{dirname});
            }
            try self.mock_fs.addFile(file.path, file.content);
        }
    }

    /// Setup directories for testing
    pub fn setupDirectories(self: *FilesystemTestContext, directories: []const []const u8) !void {
        for (directories) |dir| {
            try self.mock_fs.addDirectory(dir);
        }
    }

    /// Setup a typical source code project structure
    pub fn setupSourceProject(self: *FilesystemTestContext) !void {
        try self.setupDirectories(&[_][]const u8{
            "src",
            "src/lib",
            "src/test",
            "docs",
            "build",
        });

        try self.setupFiles(&[_]struct { path: []const u8, content: []const u8 }{
            .{ .path = "src/main.zig", .content = "const std = @import(\"std\");\npub fn main() void {}" },
            .{ .path = "src/lib/utils.zig", .content = "pub fn helper() i32 { return 42; }" },
            .{ .path = "src/test/main_test.zig", .content = "test \"basic\" { }" },
            .{ .path = "README.md", .content = "# Test Project" },
            .{ .path = "build.zig", .content = "// Build script" },
        });
    }

    /// Setup a web project structure (HTML, CSS, JS)
    pub fn setupWebProject(self: *FilesystemTestContext) !void {
        try self.setupDirectories(&[_][]const u8{
            "src",
            "src/components",
            "src/styles",
            "public",
        });

        try self.setupFiles(&[_]struct { path: []const u8, content: []const u8 }{
            .{ .path = "src/index.html", .content = "<html><body><h1>Test</h1></body></html>" },
            .{ .path = "src/styles/main.css", .content = ".container { display: flex; }" },
            .{ .path = "src/components/App.svelte", .content = "<script>export let name = 'World';</script><h1>Hello {name}!</h1>" },
            .{ .path = "src/main.js", .content = "console.log('Hello, world!');" },
            .{ .path = "package.json", .content = "{\"name\": \"test-project\"}" },
        });
    }

    /// Setup files with various extensions for language detection testing
    pub fn setupLanguageFiles(self: *FilesystemTestContext) !void {
        try self.setupFiles(&[_]struct { path: []const u8, content: []const u8 }{
            .{ .path = "test.zig", .content = "pub fn test() void {}" },
            .{ .path = "test.c", .content = "int main() { return 0; }" },
            .{ .path = "test.cpp", .content = "int main() { return 0; }" },
            .{ .path = "test.js", .content = "function test() {}" },
            .{ .path = "test.ts", .content = "function test(): void {}" },
            .{ .path = "test.py", .content = "def test(): pass" },
            .{ .path = "test.rs", .content = "fn main() {}" },
            .{ .path = "test.go", .content = "func main() {}" },
            .{ .path = "test.java", .content = "public class Test {}" },
            .{ .path = "test.css", .content = ".test { color: red; }" },
            .{ .path = "test.html", .content = "<html><body></body></html>" },
            .{ .path = "test.json", .content = "{\"test\": true}" },
            .{ .path = "test.svelte", .content = "<script></script><h1>Test</h1>" },
        });
    }

    /// Expect file exists with specific content
    pub fn expectFileExists(self: *FilesystemTestContext, path: []const u8) !void {
        const exists = self.mock_fs.fileExists(path);
        try testing.expect(exists);
    }

    /// Expect file has specific content
    pub fn expectFileContent(self: *FilesystemTestContext, path: []const u8, expected_content: []const u8) !void {
        const content = try self.mock_fs.readFile(path);
        try testing.expectEqualStrings(expected_content, content);
    }

    /// Expect directory exists
    pub fn expectDirectoryExists(self: *FilesystemTestContext, path: []const u8) !void {
        const exists = self.mock_fs.directoryExists(path);
        try testing.expect(exists);
    }

    /// Expect directory contains specific number of files
    pub fn expectDirectoryCount(self: *FilesystemTestContext, path: []const u8, expected_count: usize) !void {
        var entries = try self.mock_fs.listDirectory(path);
        defer entries.deinit();

        try testing.expectEqual(expected_count, entries.items.len);
    }

    /// Expect file does not exist
    pub fn expectFileNotExists(self: *FilesystemTestContext, path: []const u8) !void {
        const exists = self.mock_fs.fileExists(path);
        try testing.expect(!exists);
    }

    /// Expect directory contains files with specific extensions
    pub fn expectFilesByExtension(self: *FilesystemTestContext, path: []const u8, extension: []const u8, expected_count: usize) !void {
        var entries = try self.mock_fs.listDirectory(path);
        defer entries.deinit();

        var count: usize = 0;
        for (entries.items) |entry| {
            if (std.mem.endsWith(u8, entry, extension)) {
                count += 1;
            }
        }

        try testing.expectEqual(expected_count, count);
    }

    /// Create a temporary file for testing
    pub fn createTempFile(self: *FilesystemTestContext, content: []const u8) ![]const u8 {
        const temp_path = try std.fmt.allocPrint(self.allocator, "temp_file_{d}.txt", .{std.time.timestamp()});
        try self.mock_fs.addFile(temp_path, content);
        return temp_path;
    }

    /// Create a temporary directory for testing
    pub fn createTempDirectory(self: *FilesystemTestContext) ![]const u8 {
        const temp_path = try std.fmt.allocPrint(self.allocator, "temp_dir_{d}", .{std.time.timestamp()});
        try self.mock_fs.addDirectory(temp_path);
        return temp_path;
    }

    /// Helper for testing file operations that should fail
    pub fn expectOperationFails(self: *FilesystemTestContext, operation: anytype) !void {
        const result = operation();
        try testing.expectError(error.FileNotFound, result);
    }

    /// Helper for testing directory traversal
    pub fn expectTraversalResults(self: *FilesystemTestContext, start_path: []const u8, expected_files: []const []const u8) !void {
        var found_files = std.ArrayList([]const u8).init(self.allocator);
        defer found_files.deinit();

        // Mock traversal - collect all files recursively
        try self.collectFilesRecursive(start_path, &found_files);

        // Check that all expected files were found
        try testing.expectEqual(expected_files.len, found_files.items.len);

        for (expected_files) |expected| {
            var found = false;
            for (found_files.items) |file| {
                if (std.mem.eql(u8, file, expected)) {
                    found = true;
                    break;
                }
            }
            try testing.expect(found);
        }
    }

    /// Helper to recursively collect files from mock filesystem
    fn collectFilesRecursive(self: *FilesystemTestContext, dir_path: []const u8, files: *std.ArrayList([]const u8)) !void {
        var entries = try self.mock_fs.listDirectory(dir_path);
        defer entries.deinit();

        for (entries.items) |entry| {
            const full_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ dir_path, entry });
            defer self.allocator.free(full_path);

            if (self.mock_fs.directoryExists(full_path)) {
                try self.collectFilesRecursive(full_path, files);
            } else {
                const owned_path = try self.allocator.dupe(u8, full_path);
                try files.append(owned_path);
            }
        }
    }

    /// Test helper for common ignore patterns
    pub fn setupIgnoreFiles(self: *FilesystemTestContext) !void {
        try self.setupFiles(&[_]struct { path: []const u8, content: []const u8 }{
            .{ .path = ".gitignore", .content = "node_modules/\n*.log\n.env" },
            .{ .path = "node_modules/package/index.js", .content = "// Ignored by gitignore" },
            .{ .path = "debug.log", .content = "Debug information" },
            .{ .path = ".env", .content = "SECRET=value" },
        });
    }

    /// Test helper for hidden files
    pub fn setupHiddenFiles(self: *FilesystemTestContext) !void {
        try self.setupFiles(&[_]struct { path: []const u8, content: []const u8 }{
            .{ .path = ".hidden_file", .content = "Hidden content" },
            .{ .path = ".DS_Store", .content = "macOS metadata" },
            .{ .path = "Thumbs.db", .content = "Windows thumbnail cache" },
            .{ .path = "visible_file.txt", .content = "Visible content" },
        });
    }
};

// Tests for the FilesystemTestContext itself
test "FilesystemTestContext basic operations" {
    var context = try FilesystemTestContext.init(testing.allocator);
    defer context.deinit();

    try context.setupFiles(&[_]struct { path: []const u8, content: []const u8 }{
        .{ .path = "test.txt", .content = "Hello, world!" },
    });

    try context.expectFileExists("test.txt");
    try context.expectFileContent("test.txt", "Hello, world!");
}

test "FilesystemTestContext source project setup" {
    var context = try FilesystemTestContext.init(testing.allocator);
    defer context.deinit();

    try context.setupSourceProject();

    try context.expectDirectoryExists("src");
    try context.expectFileExists("src/main.zig");
    try context.expectFileExists("README.md");
}

test "FilesystemTestContext directory operations" {
    var context = try FilesystemTestContext.init(testing.allocator);
    defer context.deinit();

    try context.setupSourceProject();
    try context.expectDirectoryCount("src", 3); // main.zig, lib/, test/
    try context.expectFilesByExtension("src", ".zig", 1); // main.zig
}

test "FilesystemTestContext language files" {
    var context = try FilesystemTestContext.init(testing.allocator);
    defer context.deinit();

    try context.setupLanguageFiles();

    try context.expectFileExists("test.zig");
    try context.expectFileExists("test.js");
    try context.expectFileExists("test.py");
}