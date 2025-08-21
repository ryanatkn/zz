//! Test Coverage Analyzer
//!
//! Systematically analyzes test.zig file organization to ensure proper test tree structure.
//! Verifies that every .zig file with test blocks is properly imported by a test.zig barrel file
//! within configurable directory depth tolerance.
//!
//! ## Usage
//!
//! Basic analysis:
//!   zig run src/scripts/check_test_coverage.zig
//!
//! Export results to ZON format:
//!   zig run src/scripts/check_test_coverage.zig -- --export-zon
//!   zig run src/scripts/check_test_coverage.zig -- --export-zon my_coverage.zon
//!
//! Configure search depth:
//!   zig run src/scripts/check_test_coverage.zig -- --depth=2
//!
//! Combined options:
//!   zig run src/scripts/check_test_coverage.zig -- --depth=2 --export-zon coverage.zon
//!
//! ## What it checks
//!
//! 1. **Test Discovery**: Finds all .zig files containing `test {` blocks
//! 2. **Test Barrel Location**: Ensures each file has an accessible test.zig within depth tolerance
//! 3. **Import Verification**: Confirms test.zig files properly import child test files
//! 4. **Tree Structure**: Validates parent-child relationships form a proper test tree
//!
//! ## Expected Structure
//!
//! ```
//! src/
//! ├── test.zig              <- Root test barrel
//! ├── lib/
//! │   ├── core/
//! │   │   ├── test.zig      <- Imports core/*.zig with tests
//! │   │   ├── types.zig     <- Has tests, imported by core/test.zig
//! │   │   └── colors.zig    <- Has tests, imported by core/test.zig
//! │   └── math/
//! │       ├── test.zig      <- Imports math/*.zig with tests
//! │       └── vec2.zig      <- Has tests, imported by math/test.zig
//! └── hex/
//!     ├── factions.zig      <- Has tests, should be in hex/test.zig or src/test.zig
//! ```
//!
//! ## Output
//!
//! - Coverage percentage and statistics
//! - Files missing test.zig coverage
//! - Files with tests not imported by any test.zig
//! - List of existing test.zig barrel files
//! - Optional ZON export with complete analysis data

const std = @import("std");
const print = std.debug.print;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;
const Allocator = std.mem.Allocator;

const Config = struct {
    depth_tolerance: u32 = 1,
    export_zon: bool = false,
    zon_path: []const u8 = "test_coverage.zon",
    src_root: []const u8 = "src",
};

const TestFile = struct {
    path: []const u8,
    relative_path: []const u8,
    has_tests: bool,
    is_test_barrel: bool, // is a test.zig file
    imported_by: ArrayList([]const u8),
    expected_test_barrel: ?[]const u8, // which test.zig should import this

    fn init(allocator: Allocator, path: []const u8, relative_path: []const u8) TestFile {
        return TestFile{
            .path = path,
            .relative_path = relative_path,
            .has_tests = false,
            .is_test_barrel = false,
            .imported_by = ArrayList([]const u8).init(allocator),
            .expected_test_barrel = null,
        };
    }

    fn deinit(self: *TestFile, allocator: Allocator) void {
        // Free all imported_by paths
        for (self.imported_by.items) |path| {
            allocator.free(path);
        }
        self.imported_by.deinit();
    }
};

const TestCoverageAnalyzer = struct {
    allocator: Allocator,
    config: Config,
    files: HashMap([]const u8, TestFile, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),

    pub fn init(allocator: Allocator, config: Config) TestCoverageAnalyzer {
        return TestCoverageAnalyzer{
            .allocator = allocator,
            .config = config,
            .files = HashMap([]const u8, TestFile, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
        };
    }

    pub fn deinit(self: *TestCoverageAnalyzer) void {
        var iterator = self.files.iterator();
        while (iterator.next()) |entry| {
            // Free the key (file path)
            self.allocator.free(entry.key_ptr.*);
            // Free the relative path
            self.allocator.free(entry.value_ptr.relative_path);
            // Free the expected test barrel path if it exists
            if (entry.value_ptr.expected_test_barrel) |path| {
                self.allocator.free(path);
            }
            // Deinit the test file
            entry.value_ptr.deinit(self.allocator);
        }
        self.files.deinit();
    }

    /// Recursively scan directory for .zig files and analyze them
    pub fn analyze(self: *TestCoverageAnalyzer) !void {
        print("🔍 Analyzing test coverage for {s}/\n", .{self.config.src_root});

        // Use std.fs to recursively scan directory
        try self.scanDirectory(self.config.src_root);

        // Determine expected test barrel locations
        try self.determineExpectedTestBarrels();

        // Analyze imports in test.zig files
        try self.analyzeTestBarrelImports();
    }

    fn scanDirectory(self: *TestCoverageAnalyzer, dir_path: []const u8) !void {
        var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch |err| switch (err) {
            error.FileNotFound => {
                print("⚠️ Directory not found: {s}\n", .{dir_path});
                return;
            },
            else => return err,
        };
        defer dir.close();

        var iterator = dir.iterate();
        while (try iterator.next()) |entry| {
            if (entry.kind == .directory) {
                // Recursively scan subdirectories
                const sub_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ dir_path, entry.name });
                defer self.allocator.free(sub_path);
                try self.scanDirectory(sub_path);
            } else if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".zig")) {
                // Analyze .zig files
                const file_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ dir_path, entry.name });
                defer self.allocator.free(file_path);
                try self.analyzeFile(file_path);
            }
        }
    }

    fn analyzeFile(self: *TestCoverageAnalyzer, file_path: []const u8) !void {
        // Skip if not under src root
        if (!std.mem.startsWith(u8, file_path, self.config.src_root)) return;

        // Create relative path
        const relative_path = file_path[self.config.src_root.len..];
        if (relative_path.len == 0 or relative_path[0] != '/') return;
        const clean_relative = relative_path[1..]; // Remove leading /

        // Clone the paths for storage
        const owned_path = try self.allocator.dupe(u8, file_path);
        const owned_relative = try self.allocator.dupe(u8, clean_relative);

        var test_file = TestFile.init(self.allocator, owned_path, owned_relative);

        // Check if it's a test barrel (test.zig)
        test_file.is_test_barrel = std.mem.endsWith(u8, file_path, "/test.zig") or std.mem.eql(u8, std.fs.path.basename(file_path), "test.zig");

        // Read file and check for test blocks
        const content = std.fs.cwd().readFileAlloc(self.allocator, file_path, 1024 * 1024) catch |err| switch (err) {
            error.FileNotFound => {
                print("⚠️ File not found: {s}\n", .{file_path});
                return;
            },
            else => return err,
        };
        defer self.allocator.free(content);

        // Check for test blocks using simple pattern matching
        test_file.has_tests = self.hasTestBlocks(content);

        try self.files.put(owned_path, test_file);
    }

    fn hasTestBlocks(self: *TestCoverageAnalyzer, content: []const u8) bool {
        _ = self;
        var lines = std.mem.splitScalar(u8, content, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t");
            if (std.mem.startsWith(u8, trimmed, "test ") or
                std.mem.startsWith(u8, trimmed, "test{") or
                std.mem.startsWith(u8, trimmed, "test \""))
            {
                return true;
            }
        }
        return false;
    }

    fn determineExpectedTestBarrels(self: *TestCoverageAnalyzer) !void {
        var iterator = self.files.iterator();
        while (iterator.next()) |entry| {
            const test_file = entry.value_ptr;
            if (!test_file.has_tests or test_file.is_test_barrel) continue;

            // Find the expected test.zig location within depth tolerance
            const expected_barrel = try self.findExpectedTestBarrel(test_file.relative_path);
            test_file.expected_test_barrel = expected_barrel;
        }
    }

    fn findExpectedTestBarrel(self: *TestCoverageAnalyzer, relative_path: []const u8) !?[]const u8 {
        const dir_path = std.fs.path.dirname(relative_path) orelse "";

        // Check current directory first
        const test_barrel_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}/test.zig", .{ self.config.src_root, dir_path });
        defer self.allocator.free(test_barrel_path); // Always free this allocation
        if (std.fs.cwd().access(test_barrel_path, .{})) |_| {
            return try self.allocator.dupe(u8, test_barrel_path);
        } else |_| {
            // File doesn't exist, continue to check parent directories
        }

        // Check parent directories up to depth tolerance
        var current_dir = dir_path;
        var depth: u32 = 0;

        while (depth < self.config.depth_tolerance) {
            const parent = std.fs.path.dirname(current_dir);
            if (parent == null or std.mem.eql(u8, parent.?, current_dir)) break;

            current_dir = parent.?;
            depth += 1;

            const parent_test_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}/test.zig", .{ self.config.src_root, current_dir });
            defer self.allocator.free(parent_test_path); // Always free this allocation
            if (std.fs.cwd().access(parent_test_path, .{})) |_| {
                return try self.allocator.dupe(u8, parent_test_path);
            } else |_| {
                // File doesn't exist, continue to next parent
            }
        }

        return null;
    }

    fn analyzeTestBarrelImports(self: *TestCoverageAnalyzer) !void {
        var iterator = self.files.iterator();
        while (iterator.next()) |entry| {
            const test_file = entry.value_ptr;
            if (!test_file.is_test_barrel) continue;

            // Read and analyze imports
            const content = try std.fs.cwd().readFileAlloc(self.allocator, test_file.path, 1024 * 1024);
            defer self.allocator.free(content);

            try self.parseImports(test_file.path, content);
        }
    }

    fn parseImports(self: *TestCoverageAnalyzer, test_barrel_path: []const u8, content: []const u8) !void {
        var lines = std.mem.splitScalar(u8, content, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t");

            // Look for import patterns: _ = @import("path");
            if (std.mem.indexOf(u8, trimmed, "@import(\"") != null) {
                if (std.mem.indexOf(u8, trimmed, "\")") != null) {
                    // Extract the import path
                    const start = std.mem.indexOf(u8, trimmed, "@import(\"").? + 9;
                    const end = std.mem.indexOf(u8, trimmed[start..], "\")").? + start;
                    const import_path = trimmed[start..end];

                    // Resolve relative import to absolute path
                    const resolved_path = try self.resolveImportPath(test_barrel_path, import_path);
                    if (resolved_path) |path| {
                        // Mark this file as imported by the test barrel
                        if (self.files.getPtr(path)) |imported_file| {
                            try imported_file.imported_by.append(try self.allocator.dupe(u8, test_barrel_path));
                        }
                        self.allocator.free(path);
                    }
                }
            }
        }
    }

    fn resolveImportPath(self: *TestCoverageAnalyzer, test_barrel_path: []const u8, import_path: []const u8) !?[]const u8 {
        const test_dir = std.fs.path.dirname(test_barrel_path) orelse return null;

        // Handle relative imports (POSIX paths only)
        if (std.mem.startsWith(u8, import_path, "../") or !std.mem.startsWith(u8, import_path, "/")) {
            // Simple POSIX path resolution
            var path_parts = ArrayList([]const u8).init(self.allocator);
            defer path_parts.deinit();

            // Split test_dir into parts
            var dir_iter = std.mem.splitScalar(u8, test_dir, '/');
            while (dir_iter.next()) |part| {
                if (part.len > 0) try path_parts.append(part);
            }

            // Process import_path
            var import_iter = std.mem.splitScalar(u8, import_path, '/');
            while (import_iter.next()) |part| {
                if (std.mem.eql(u8, part, "..")) {
                    if (path_parts.items.len > 0) {
                        _ = path_parts.pop();
                    }
                } else if (std.mem.eql(u8, part, ".")) {
                    // Skip current directory
                } else if (part.len > 0) {
                    try path_parts.append(part);
                }
            }

            // Reconstruct path
            var resolved = ArrayList(u8).init(self.allocator);
            defer resolved.deinit();

            for (path_parts.items, 0..) |part, i| {
                if (i > 0) try resolved.append('/');
                try resolved.appendSlice(part);
            }

            const resolved_str = try resolved.toOwnedSlice();

            // Ensure it ends with .zig
            if (!std.mem.endsWith(u8, resolved_str, ".zig")) {
                const with_zig = try std.fmt.allocPrint(self.allocator, "{s}.zig", .{resolved_str});
                self.allocator.free(resolved_str);
                return with_zig;
            }
            return resolved_str;
        }

        return null;
    }

    pub fn generateReport(self: *TestCoverageAnalyzer) !void {
        print("\nTEST COVERAGE ANALYSIS REPORT\n", .{});
        print("=" ** 50 ++ "\n\n", .{});

        var uncovered_files = ArrayList([]const u8).init(self.allocator);
        defer uncovered_files.deinit();

        var test_barrels = ArrayList([]const u8).init(self.allocator);
        defer test_barrels.deinit();

        var total_files_with_tests: u32 = 0;
        var files_with_coverage: u32 = 0;

        // Collect data for reporting
        var iterator = self.files.iterator();
        while (iterator.next()) |entry| {
            const test_file = entry.value_ptr;

            if (test_file.is_test_barrel) {
                try test_barrels.append(test_file.relative_path);
            } else if (test_file.has_tests) {
                total_files_with_tests += 1;

                // A file is covered if it's imported by any test.zig file
                if (test_file.imported_by.items.len > 0) {
                    files_with_coverage += 1;
                } else {
                    try uncovered_files.append(test_file.relative_path);
                }
            }
        }

        // Sort all lists for consistent output
        std.mem.sort([]const u8, test_barrels.items, {}, struct {
            fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.order(u8, a, b) == .lt;
            }
        }.lessThan);

        std.mem.sort([]const u8, uncovered_files.items, {}, struct {
            fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.order(u8, a, b) == .lt;
            }
        }.lessThan);

        // Show existing test barrels first
        print("\x1b[32m▓ Existing test.zig files:\x1b[0m\n", .{});
        for (test_barrels.items) |path| {
            print("  \x1b[32m•\x1b[0m {s}\n", .{path});
        }
        print("\n", .{});

        // Show uncovered files
        if (uncovered_files.items.len > 0) {
            print("\x1b[31m▓ Files with tests not imported by any test.zig:\x1b[0m\n", .{});
            for (uncovered_files.items) |path| {
                print("  \x1b[31m•\x1b[0m {s}\n", .{path});
            }
            print("\n", .{});
        }

        // Print comprehensive summary at the end
        const coverage_percent = @as(f64, @floatFromInt(files_with_coverage)) * 100.0 / @as(f64, @floatFromInt(total_files_with_tests));

        print("═" ** 60 ++ "\n", .{});
        print("\x1b[1m\x1b[36m■ TEST COVERAGE SUMMARY\x1b[0m\n", .{});
        print("═" ** 60 ++ "\n", .{});

        print("  \x1b[1mTotal files analyzed:\x1b[0m     {} files with test blocks\n", .{total_files_with_tests});
        print("  \x1b[1mTest barrels found:\x1b[0m       \x1b[32m{}\x1b[0m test.zig files\n", .{test_barrels.items.len});
        print("  \x1b[1mProperly covered:\x1b[0m         \x1b[32m{}\x1b[0m files imported by test.zig\n", .{files_with_coverage});
        print("  \x1b[1mMissing coverage:\x1b[0m         \x1b[31m{}\x1b[0m files not imported\n", .{uncovered_files.items.len});
        print("\n", .{});

        // Coverage percentage - red unless 100%
        if (coverage_percent >= 100.0) {
            print("  \x1b[1m\x1b[32mCOVERAGE: {d:.1}%\x1b[0m\n", .{coverage_percent});
        } else {
            print("  \x1b[1m\x1b[31mCOVERAGE: {d:.1}%\x1b[0m\n", .{coverage_percent});
        }

        print("\n", .{});
        print("▓ \x1b[2mNext steps: Import uncovered files into appropriate test.zig barrels\x1b[0m\n", .{});

        if (self.config.export_zon) {
            try self.exportToZon();
        }
    }

    fn exportToZon(self: *TestCoverageAnalyzer) !void {
        print("\n💾 Exporting analysis to {s}\n", .{self.config.zon_path});

        const file = try std.fs.cwd().createFile(self.config.zon_path, .{});
        defer file.close();

        const writer = file.writer();
        try writer.print(".{{\n", .{});
        try writer.print("    .analysis_timestamp = \"{}\",\n", .{std.time.timestamp()});
        try writer.print("    .config = .{{\n", .{});
        try writer.print("        .depth_tolerance = {},\n", .{self.config.depth_tolerance});
        try writer.print("        .src_root = \"{s}\",\n", .{self.config.src_root});
        try writer.print("    }},\n", .{});
        try writer.print("    .files = .{{\n", .{});

        var iterator = self.files.iterator();
        while (iterator.next()) |entry| {
            const test_file = entry.value_ptr;
            try writer.print("        .@\"{s}\" = .{{\n", .{test_file.relative_path});
            try writer.print("            .has_tests = {},\n", .{test_file.has_tests});
            try writer.print("            .is_test_barrel = {},\n", .{test_file.is_test_barrel});
            try writer.print("            .imported_by_count = {},\n", .{test_file.imported_by.items.len});
            if (test_file.expected_test_barrel) |barrel| {
                try writer.print("            .expected_test_barrel = \"{s}\",\n", .{barrel});
            }
            try writer.print("        }},\n", .{});
        }

        try writer.print("    }},\n", .{});
        try writer.print("}}\n", .{});
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var config = Config{};

    // Simple argument parsing
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--export-zon")) {
            config.export_zon = true;
            if (i + 1 < args.len and !std.mem.startsWith(u8, args[i + 1], "--")) {
                i += 1;
                config.zon_path = args[i];
            }
        } else if (std.mem.startsWith(u8, arg, "--depth=")) {
            const depth_str = arg[8..];
            config.depth_tolerance = std.fmt.parseInt(u32, depth_str, 10) catch {
                print("❌ Invalid depth value: {s}\n", .{depth_str});
                return;
            };
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            print("Test Coverage Checker\n\n", .{});
            print("Usage: zig run src/scripts/check_test_coverage.zig [options]\n\n", .{});
            print("Options:\n", .{});
            print("  --export-zon [file]    Export analysis to ZON format (default: test_coverage.zon)\n", .{});
            print("  --depth=N              Set depth tolerance for test.zig search (default: 1)\n", .{});
            print("  --help, -h             Show this help\n\n", .{});
            print("Examples:\n", .{});
            print("  zig run src/scripts/check_test_coverage.zig\n", .{});
            print("  zig run src/scripts/check_test_coverage.zig -- --export-zon\n", .{});
            print("  zig run src/scripts/check_test_coverage.zig -- --depth=2 --export-zon coverage.zon\n", .{});
            return;
        }
    }

    var analyzer = TestCoverageAnalyzer.init(allocator, config);
    defer analyzer.deinit();

    try analyzer.analyze();
    try analyzer.generateReport();
}
