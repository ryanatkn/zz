const std = @import("std");
const PathMatcher = @import("path_matcher.zig").PathMatcher;
const FilesystemInterface = @import("../filesystem/interface.zig").FilesystemInterface;
const path = @import("../core/path.zig");
const errors = @import("../core/errors.zig");
const collections = @import("../core/collections.zig");
const pools = @import("../memory/pools.zig");
const builders = @import("../text/builders.zig");

/// Result of pattern validation
pub const ValidationResult = struct {
    matched_files: u32,
    total_files: u32,
    failed_patterns: collections.List([]const u8),
    available_files: collections.List([]const u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ValidationResult {
        return ValidationResult{
            .matched_files = 0,
            .total_files = 0,
            .failed_patterns = collections.List([]const u8).init(allocator),
            .available_files = collections.List([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ValidationResult) void {
        for (self.failed_patterns.items) |pattern| {
            self.allocator.free(pattern);
        }
        self.failed_patterns.deinit();

        for (self.available_files.items) |file| {
            self.allocator.free(file);
        }
        self.available_files.deinit();
    }

    /// Generate helpful error message with suggestions
    pub fn formatError(self: *const ValidationResult, allocator: std.mem.Allocator) ![]u8 {
        if (self.failed_patterns.items.len == 0) {
            return allocator.dupe(u8, "No pattern validation errors");
        }

        var builder = builders.ResultBuilder.init(allocator);
        defer builder.deinit();

        // Header with summary
        try builder.appendLineFmt("✗ Pattern Validation Failed: {d} pattern{s} did not match any files", .{ self.failed_patterns.items.len, if (self.failed_patterns.items.len == 1) "" else "s" });
        try builder.appendLine("");

        // Failed patterns with enhanced formatting
        try builder.appendLine("Failed patterns:");
        for (self.failed_patterns.items) |pattern| {
            try builder.appendLineFmt("  ✗ '{s}'", .{pattern});
        }

        try builder.appendLine("");

        // Repository info
        if (self.total_files == 0) {
            try builder.appendLine("Repository appears to be empty (no files found)");
        } else {
            try builder.appendLineFmt("Repository contains {d} file{s}/director{s}:", .{ self.total_files, if (self.total_files == 1) "" else "s", if (self.total_files == 1) "y" else "ies" });

            // Show categorized file examples
            try self.showCategorizedFiles(&builder);
        }

        try builder.appendLine("");

        // Smart suggestions based on failed patterns and available files
        try self.generateSmartSuggestions(&builder, allocator);

        return builder.toOwnedSlice();
    }

    /// Show available files categorized by type for better understanding
    fn showCategorizedFiles(self: *const ValidationResult, builder: *builders.ResultBuilder) !void {
        const max_show = @min(12, self.available_files.items.len);

        // Categorize files by type
        var src_files = collections.List([]const u8).init(self.allocator);
        defer src_files.deinit();
        var config_files = collections.List([]const u8).init(self.allocator);
        defer config_files.deinit();
        var doc_files = collections.List([]const u8).init(self.allocator);
        defer doc_files.deinit();
        var other_files = collections.List([]const u8).init(self.allocator);
        defer other_files.deinit();

        for (self.available_files.items[0..max_show]) |file| {
            if (std.mem.endsWith(u8, file, ".zig") or
                std.mem.endsWith(u8, file, ".c") or
                std.mem.endsWith(u8, file, ".h") or
                std.mem.startsWith(u8, file, "src/") or
                std.mem.startsWith(u8, file, "lib/"))
            {
                try src_files.append(file);
            } else if (std.mem.endsWith(u8, file, ".json") or
                std.mem.endsWith(u8, file, ".zon") or
                std.mem.endsWith(u8, file, ".toml") or
                std.mem.endsWith(u8, file, ".yaml") or
                std.mem.eql(u8, file, "build.zig") or
                std.mem.eql(u8, file, "Makefile"))
            {
                try config_files.append(file);
            } else if (std.mem.endsWith(u8, file, ".md") or
                std.mem.endsWith(u8, file, ".txt") or
                std.mem.endsWith(u8, file, ".rst") or
                std.mem.startsWith(u8, file, "docs/"))
            {
                try doc_files.append(file);
            } else {
                try other_files.append(file);
            }
        }

        // Show categorized files
        if (src_files.items.len > 0) {
            try builder.appendLine("  Source files:");
            for (src_files.items[0..@min(4, src_files.items.len)]) |file| {
                try builder.appendLineFmt("    - {s}", .{file});
            }
            if (src_files.items.len > 4) {
                try builder.appendLineFmt("    ... and {d} more", .{src_files.items.len - 4});
            }
        }

        if (config_files.items.len > 0) {
            try builder.appendLine("  Configuration files:");
            for (config_files.items[0..@min(3, config_files.items.len)]) |file| {
                try builder.appendLineFmt("    - {s}", .{file});
            }
        }

        if (doc_files.items.len > 0) {
            try builder.appendLine("  Documentation:");
            for (doc_files.items[0..@min(3, doc_files.items.len)]) |file| {
                try builder.appendLineFmt("    - {s}", .{file});
            }
        }

        if (other_files.items.len > 0) {
            try builder.appendLine("  Other files:");
            for (other_files.items[0..@min(3, other_files.items.len)]) |file| {
                try builder.appendLineFmt("    - {s}", .{file});
            }
        }

        if (self.available_files.items.len > max_show) {
            try builder.appendLineFmt("  ... and {d} more files", .{self.available_files.items.len - max_show});
        }
    }

    /// Generate smart suggestions based on failed patterns and available files
    fn generateSmartSuggestions(self: *const ValidationResult, builder: *builders.ResultBuilder, allocator: std.mem.Allocator) !void {
        try builder.appendLine("💡 Suggestions:");

        // Analyze failed patterns and suggest alternatives
        for (self.failed_patterns.items) |failed_pattern| {
            const suggestion = try self.suggestAlternative(failed_pattern, allocator);
            defer if (suggestion) |s| allocator.free(s);

            if (suggestion) |s| {
                try builder.appendLineFmt("  • Instead of '{s}', try: {s}", .{ failed_pattern, s });
            }
        }

        try builder.appendLine("");
        try builder.appendLine("📖 Pattern syntax guide:");
        try builder.appendLine("  • '*' matches any characters in a filename");
        try builder.appendLine("  • '**/' matches any subdirectory recursively");
        try builder.appendLine("  • 'dir/' matches directory and its contents");
        try builder.appendLine("  • '*.ext' matches all files with extension");
        try builder.appendLine("  • Use exact paths for specific files");

        try builder.appendLine("");
        try builder.appendLine("🔧 Common patterns:");
        try builder.appendLine("  • Source files: '*.zig', 'src/', '**/*.c'");
        try builder.appendLine("  • Config files: '*.json', 'build.zig', 'Makefile'");
        try builder.appendLine("  • Documentation: '*.md', 'docs/', 'README*'");
        try builder.appendLine("  • Include all: omit include patterns entirely");
    }

    /// Suggest alternative patterns based on available files
    fn suggestAlternative(self: *const ValidationResult, failed_pattern: []const u8, allocator: std.mem.Allocator) !?[]u8 {
        // Extract pattern type and suggest similar patterns that would match
        if (std.mem.endsWith(u8, failed_pattern, ".js")) {
            // Look for similar script files
            for (self.available_files.items) |file| {
                if (std.mem.endsWith(u8, file, ".zig") or std.mem.endsWith(u8, file, ".ts")) {
                    if (std.mem.endsWith(u8, file, ".zig")) {
                        return try allocator.dupe(u8, "'*.zig' (found Zig files)");
                    } else {
                        return try allocator.dupe(u8, "'*.ts' (found TypeScript files)");
                    }
                }
            }
        } else if (std.mem.endsWith(u8, failed_pattern, ".py")) {
            // Look for other script files
            for (self.available_files.items) |file| {
                if (std.mem.endsWith(u8, file, ".zig")) {
                    return try allocator.dupe(u8, "'*.zig' (found Zig files instead)");
                }
            }
        } else if (std.mem.eql(u8, failed_pattern, "src/")) {
            // Look for actual source directories
            for (self.available_files.items) |file| {
                if (std.mem.startsWith(u8, file, "lib/")) {
                    return try allocator.dupe(u8, "'lib/' (found lib directory)");
                } else if (std.mem.indexOf(u8, file, "/")) |_| {
                    const dir = file[0..std.mem.indexOf(u8, file, "/").?];
                    return try std.fmt.allocPrint(allocator, "'{s}/' (found {s} directory)", .{ dir, dir });
                }
            }
            return try allocator.dupe(u8, "remove src/ pattern or use exact filenames");
        } else if (std.mem.eql(u8, failed_pattern, "test/") or std.mem.eql(u8, failed_pattern, "tests/")) {
            // Look for test files
            for (self.available_files.items) |file| {
                if (std.mem.indexOf(u8, file, "test") != null) {
                    return try allocator.dupe(u8, "'*test*' (found test files)");
                }
            }
            return try allocator.dupe(u8, "remove test pattern if no tests needed");
        } else if (std.mem.startsWith(u8, failed_pattern, "*.")) {
            // Extension pattern - suggest similar extensions
            const ext = failed_pattern[2..];
            if (std.mem.eql(u8, ext, "cpp") or std.mem.eql(u8, ext, "cc")) {
                for (self.available_files.items) |file| {
                    if (std.mem.endsWith(u8, file, ".c")) {
                        return try allocator.dupe(u8, "'*.c' (found C files)");
                    }
                }
            }
        }

        // Default suggestion based on most common files in repository
        if (self.available_files.items.len > 0) {
            // Count file types
            var zig_count: u32 = 0;
            var c_count: u32 = 0;
            var md_count: u32 = 0;

            for (self.available_files.items) |file| {
                if (std.mem.endsWith(u8, file, ".zig")) zig_count += 1;
                if (std.mem.endsWith(u8, file, ".c") or std.mem.endsWith(u8, file, ".h")) c_count += 1;
                if (std.mem.endsWith(u8, file, ".md")) md_count += 1;
            }

            if (zig_count > 0) {
                return try allocator.dupe(u8, "'*.zig' or remove include patterns");
            } else if (c_count > 0) {
                return try allocator.dupe(u8, "'*.c' or '*.h'");
            } else if (md_count > 0) {
                return try allocator.dupe(u8, "'*.md' or specific filenames");
            }
        }

        return null;
    }
};

/// Pattern validator for dependency include/exclude patterns
pub const PatternValidator = struct {
    allocator: std.mem.Allocator,
    filesystem: FilesystemInterface,
    arena: pools.Arena,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, filesystem: FilesystemInterface) Self {
        return Self{
            .allocator = allocator,
            .filesystem = filesystem,
            .arena = pools.Arena.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.arena.deinit();
    }

    /// Validate that include patterns match at least one file in the repository
    /// Only validates when include patterns are specified (non-empty)
    pub fn validateIncludePatterns(
        self: *Self,
        repo_dir: []const u8,
        include_patterns: []const []const u8,
        exclude_patterns: []const []const u8,
    ) !ValidationResult {
        // Reset arena for temporary allocations
        self.arena.reset();

        var result = ValidationResult.init(self.allocator);
        errdefer result.deinit();

        // If no include patterns specified, everything is included - validation passes
        if (include_patterns.len == 0) {
            return result;
        }

        // Collect all files in repository
        var all_files = collections.List([]const u8).init(self.allocator);
        defer {
            for (all_files.items) |file| {
                self.allocator.free(file);
            }
            all_files.deinit();
        }

        try self.collectFiles(repo_dir, "", &all_files);
        result.total_files = @intCast(all_files.items.len);

        // Store sample of available files for error messages
        const max_samples = @min(20, all_files.items.len);
        for (all_files.items[0..max_samples]) |file| {
            const file_copy = try self.allocator.dupe(u8, file);
            try result.available_files.append(file_copy);
        }

        // Check each include pattern for matches
        for (include_patterns) |pattern| {
            var pattern_matched = false;

            for (all_files.items) |file| {
                if (PathMatcher.shouldCopyPath(file, &.{pattern}, exclude_patterns)) {
                    pattern_matched = true;
                    result.matched_files += 1;
                    break; // Found at least one match for this pattern
                }
            }

            if (!pattern_matched) {
                const failed_pattern = try self.allocator.dupe(u8, pattern);
                try result.failed_patterns.append(failed_pattern);
            }
        }

        return result;
    }

    /// Check if exclude patterns are meaningful (optional validation)
    /// Returns warning information if exclude patterns match nothing
    pub fn validateExcludePatterns(
        self: *Self,
        repo_dir: []const u8,
        exclude_patterns: []const []const u8,
    ) !ValidationResult {
        // Reset arena for temporary allocations
        self.arena.reset();

        var result = ValidationResult.init(self.allocator);
        errdefer result.deinit();

        // If no exclude patterns specified, nothing to validate
        if (exclude_patterns.len == 0) {
            return result;
        }

        // Collect all files in repository
        var all_files = collections.List([]const u8).init(self.allocator);
        defer {
            for (all_files.items) |file| {
                self.allocator.free(file);
            }
            all_files.deinit();
        }

        try self.collectFiles(repo_dir, "", &all_files);

        // Check each exclude pattern for matches
        for (exclude_patterns) |pattern| {
            var pattern_matched = false;

            for (all_files.items) |file| {
                if (PathMatcher.shouldExclude(file, &.{pattern})) {
                    pattern_matched = true;
                    break;
                }
            }

            if (!pattern_matched) {
                const failed_pattern = try self.allocator.dupe(u8, pattern);
                try result.failed_patterns.append(failed_pattern);
            }
        }

        return result;
    }

    /// Recursively collect all files and directories in a repository
    fn collectFiles(self: *Self, base_dir: []const u8, rel_path: []const u8, files: *collections.List([]const u8)) !void {
        // Use arena for temporary path allocations
        const arena_alloc = self.arena.allocator();

        const full_path = if (rel_path.len == 0)
            try arena_alloc.dupe(u8, base_dir)
        else
            try path.joinPath(arena_alloc, base_dir, rel_path);

        var dir = self.filesystem.openDir(self.allocator, full_path, .{}) catch |err| switch (err) {
            error.FileNotFound, error.AccessDenied, error.NotDir => return,
            else => return err,
        };
        defer dir.close();

        var iterator = dir.iterate(self.allocator) catch return;

        while (try iterator.next(self.allocator)) |entry| {
            // Skip .git directories
            if (std.mem.eql(u8, entry.name, ".git")) continue;

            const entry_rel_path = if (rel_path.len == 0)
                try self.allocator.dupe(u8, entry.name)
            else
                try path.joinPath(self.allocator, rel_path, entry.name);

            // Add this file/directory to the list (using permanent allocator)
            try files.append(entry_rel_path);

            // Recursively collect from subdirectories
            if (entry.kind == .directory) {
                try self.collectFiles(base_dir, entry_rel_path, files);
            }
        }
    }

    /// Quick check if repository has any files (not empty)
    pub fn hasFiles(self: *Self, repo_dir: []const u8) !bool {
        var dir = self.filesystem.openDir(self.allocator, repo_dir, .{}) catch return false;
        defer dir.close();

        var iterator = dir.iterate(self.allocator) catch return false;

        while (try iterator.next(self.allocator)) |entry| {
            // Skip .git directories
            if (std.mem.eql(u8, entry.name, ".git")) continue;
            return true; // Found at least one non-.git file
        }

        return false;
    }
};

// Tests
test "PatternValidator - no include patterns (allow all)" {
    const testing = std.testing;
    const MockFilesystem = @import("../filesystem/mock.zig").MockFilesystem;

    var mock_fs = MockFilesystem.init(testing.allocator);
    defer mock_fs.deinit();

    try mock_fs.addDirectory("/repo");
    try mock_fs.addFile("/repo/main.zig", "content");

    var validator = PatternValidator.init(testing.allocator, mock_fs.interface());
    defer validator.deinit();

    var result = try validator.validateIncludePatterns("/repo", &.{}, &.{});
    defer result.deinit();

    // No include patterns means validation passes
    try testing.expectEqual(@as(u32, 0), result.failed_patterns.items.len);
}

test "PatternValidator - include pattern matches files" {
    const testing = std.testing;
    const MockFilesystem = @import("../filesystem/mock.zig").MockFilesystem;

    var mock_fs = MockFilesystem.init(testing.allocator);
    defer mock_fs.deinit();

    try mock_fs.addDirectory("/repo");
    try mock_fs.addFile("/repo/main.zig", "content");
    try mock_fs.addFile("/repo/test.zig", "content");
    try mock_fs.addFile("/repo/readme.md", "content");

    var validator = PatternValidator.init(testing.allocator, mock_fs.interface());
    defer validator.deinit();

    // Test pattern that matches zig files
    var result = try validator.validateIncludePatterns("/repo", &.{"*.zig"}, &.{});
    defer result.deinit();

    try testing.expectEqual(@as(u32, 0), result.failed_patterns.items.len);
    try testing.expect(result.matched_files > 0);
}

test "PatternValidator - include pattern with no matches" {
    const testing = std.testing;
    const MockFilesystem = @import("../filesystem/mock.zig").MockFilesystem;

    var mock_fs = MockFilesystem.init(testing.allocator);
    defer mock_fs.deinit();

    try mock_fs.addDirectory("/repo");
    try mock_fs.addFile("/repo/main.zig", "content");
    try mock_fs.addFile("/repo/readme.md", "content");

    var validator = PatternValidator.init(testing.allocator, mock_fs.interface());
    defer validator.deinit();

    // Test pattern that matches no files
    var result = try validator.validateIncludePatterns("/repo", &.{"*.js"}, &.{});
    defer result.deinit();

    try testing.expectEqual(@as(u32, 1), result.failed_patterns.items.len);
    try testing.expectEqualStrings("*.js", result.failed_patterns.items[0]);
    try testing.expect(result.available_files.items.len > 0);
}

test "PatternValidator - error message formatting" {
    const testing = std.testing;

    var result = ValidationResult.init(testing.allocator);
    defer result.deinit();

    const failed_pattern = try testing.allocator.dupe(u8, "*.nonexistent");
    try result.failed_patterns.append(failed_pattern);

    const available_file = try testing.allocator.dupe(u8, "main.zig");
    try result.available_files.append(available_file);
    result.total_files = 1; // Set total_files to trigger the enhanced formatting

    const error_msg = try result.formatError(testing.allocator);
    defer testing.allocator.free(error_msg);

    try testing.expect(std.mem.indexOf(u8, error_msg, "*.nonexistent") != null);
    try testing.expect(std.mem.indexOf(u8, error_msg, "main.zig") != null);
    try testing.expect(std.mem.indexOf(u8, error_msg, "💡 Suggestions:") != null);
}

test "PatternValidator - empty repository" {
    const testing = std.testing;
    const MockFilesystem = @import("../filesystem/mock.zig").MockFilesystem;

    var mock_fs = MockFilesystem.init(testing.allocator);
    defer mock_fs.deinit();

    try mock_fs.addDirectory("/repo");
    // No files in repository

    var validator = PatternValidator.init(testing.allocator, mock_fs.interface());
    defer validator.deinit();

    try testing.expect(!try validator.hasFiles("/repo"));

    var result = try validator.validateIncludePatterns("/repo", &.{"*.zig"}, &.{});
    defer result.deinit();

    try testing.expectEqual(@as(u32, 1), result.failed_patterns.items.len);
    try testing.expectEqual(@as(u32, 0), result.total_files);
}
