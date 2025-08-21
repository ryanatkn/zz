//! Test Coverage Analyzer
//!
//! Analyzes import relationships between .zig files with tests and test.zig barrel files.
//! Reports which test files are not imported by any test.zig file.
//!
//! ## Usage
//!
//! Minimal output (default, CI-friendly):
//!   zig run src/scripts/check_test_coverage.zig
//!
//! Pretty human-readable report:
//!   zig run src/scripts/check_test_coverage.zig -- --pretty
//!
//! Export results to ZON format:
//!   zig run src/scripts/check_test_coverage.zig -- -o
//!   zig run src/scripts/check_test_coverage.zig -- --output my_coverage.zon
//!
//! Combined options:
//!   zig run src/scripts/check_test_coverage.zig -- --pretty -o coverage.zon
//!
//! ## What it checks
//!
//! 1. **Test Discovery**: Finds all .zig files containing `test {` blocks
//! 2. **Import Analysis**: Parses all test.zig files to see what they import
//! 3. **Coverage Reporting**: Lists files with tests that aren't imported anywhere
//! 4. **Exit Code**: Returns 1 if uncovered files found, 0 if all files covered
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
//! **Default (minimal)**:
//! - One line per uncovered file (empty if all covered)
//! - Exit code 1 if any uncovered files, 0 if all covered
//!
//! **Pretty mode (--pretty)**:
//! - Coverage percentage and statistics
//! - List of existing test.zig barrel files
//! - Files with tests not imported by any test.zig
//! - Detailed summary with recommendations
//!
//! **Optional ZON export** with complete analysis data

const std = @import("std");
const print = std.debug.print;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;
const Allocator = std.mem.Allocator;

// ANSI color codes for output formatting
const ANSI = struct {
    const GREEN = "\x1b[32m";
    const RED = "\x1b[31m";
    const CYAN = "\x1b[36m";
    const BOLD = "\x1b[1m";
    const DIM = "\x1b[2m";
    const RESET = "\x1b[0m";
};

const Config = struct {
    output_file: ?[]const u8 = null,
    src_root: []const u8 = "src",
    pretty: bool = false,
};

const TestFile = struct {
    path: []const u8,
    relative_path: []const u8,
    has_tests: bool,
    is_test_barrel: bool, // is a test.zig file
    imported_by: ArrayList([]const u8),

    fn init(allocator: Allocator, path: []const u8, relative_path: []const u8) TestFile {
        return TestFile{
            .path = path,
            .relative_path = relative_path,
            .has_tests = false,
            .is_test_barrel = false,
            .imported_by = ArrayList([]const u8).init(allocator),
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
        // Pre-size HashMap for better performance, estimating ~200 files
        var files_map = HashMap([]const u8, TestFile, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator);
        files_map.ensureTotalCapacity(200) catch {}; // Ignore allocation errors, will just be slower

        return TestCoverageAnalyzer{
            .allocator = allocator,
            .config = config,
            .files = files_map,
        };
    }

    pub fn deinit(self: *TestCoverageAnalyzer) void {
        var iterator = self.files.iterator();
        while (iterator.next()) |entry| {
            // Free the key (file path)
            self.allocator.free(entry.key_ptr.*);
            // Free the relative path
            self.allocator.free(entry.value_ptr.relative_path);
            // Deinit the test file
            entry.value_ptr.deinit(self.allocator);
        }
        self.files.deinit();
    }

    /// Recursively scan directory for .zig files and analyze them
    pub fn analyze(self: *TestCoverageAnalyzer) !void {
        // Use std.fs to recursively scan directory
        try self.scanDirectory(self.config.src_root);

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
        // Convert to null-terminated string for AST parser
        const source = try self.allocator.dupeZ(u8, content);
        defer self.allocator.free(source);

        var ast = std.zig.Ast.parse(self.allocator, source, .zig) catch {
            // Fall back to string parsing if AST parsing fails
            return self.parseImportsStringBased(test_barrel_path, content);
        };
        defer ast.deinit(self.allocator);

        const node_tags = ast.nodes.items(.tag);
        const node_datas = ast.nodes.items(.data);
        const main_tokens = ast.nodes.items(.main_token);

        for (node_tags, 0..) |tag, i| {
            // Check for @import builtin calls
            if (tag == .builtin_call_two or tag == .builtin_call_two_comma) {
                const main_token = main_tokens[i];
                const builtin_name = ast.tokenSlice(main_token);
                if (std.mem.eql(u8, builtin_name, "@import")) {
                    const data = node_datas[i];
                    // First argument is the import path
                    const arg_node = data.lhs;
                    const arg_tag = node_tags[arg_node];
                    if (arg_tag == .string_literal) {
                        const str_token = main_tokens[arg_node];
                        const import_path = ast.tokenSlice(str_token);
                        // Remove quotes
                        const clean_path = import_path[1 .. import_path.len - 1];

                        // Resolve relative import to absolute path
                        const resolved_path = try self.resolveImportPath(test_barrel_path, clean_path);
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
    }

    fn parseImportsStringBased(self: *TestCoverageAnalyzer, test_barrel_path: []const u8, content: []const u8) !void {
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

    pub fn generateReport(self: *TestCoverageAnalyzer) !u8 {
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

        if (self.config.pretty) {
            try self.generatePrettyReport(test_barrels.items, uncovered_files.items, total_files_with_tests, files_with_coverage);
        } else {
            try self.generateMinimalReport(uncovered_files.items);
        }

        if (self.config.output_file) |_| {
            try self.exportToZon();
        }

        // Return exit code: 0 if all files covered, 1 if any uncovered
        return if (uncovered_files.items.len == 0) 0 else 1;
    }

    fn generateMinimalReport(self: *TestCoverageAnalyzer, uncovered_files: [][]const u8) !void {
        if (uncovered_files.len > 0) {
            print("# Found {} uncovered test files\n", .{uncovered_files.len});
            for (uncovered_files) |path| {
                print("./{s}/{s}\n", .{ self.config.src_root, path });
            }
        }
    }

    fn generatePrettyReport(self: *TestCoverageAnalyzer, test_barrels: [][]const u8, uncovered_files: [][]const u8, total_files_with_tests: u32, files_with_coverage: u32) !void {
        print("\nTEST COVERAGE ANALYSIS REPORT\n", .{});
        print("=" ** 50 ++ "\n\n", .{});

        // Show existing test barrels first
        print("{s}▓ Existing test.zig files:{s}\n", .{ ANSI.GREEN, ANSI.RESET });
        for (test_barrels) |path| {
            print("  {s}•{s} ./{s}/{s}\n", .{ ANSI.GREEN, ANSI.RESET, self.config.src_root, path });
        }
        print("\n", .{});

        // Show uncovered files
        if (uncovered_files.len > 0) {
            print("{s}▓ Files with tests not imported by any test.zig:{s}\n", .{ ANSI.RED, ANSI.RESET });
            for (uncovered_files) |path| {
                print("  {s}•{s} ./{s}/{s}\n", .{ ANSI.RED, ANSI.RESET, self.config.src_root, path });
            }
            print("\n", .{});
        }

        // Print comprehensive summary at the end
        const coverage_percent = if (total_files_with_tests > 0)
            @as(f64, @floatFromInt(files_with_coverage)) * 100.0 / @as(f64, @floatFromInt(total_files_with_tests))
        else
            100.0;

        print("═" ** 60 ++ "\n", .{});
        print("{s}{s}■ TEST COVERAGE SUMMARY{s}\n", .{ ANSI.BOLD, ANSI.CYAN, ANSI.RESET });
        print("═" ** 60 ++ "\n", .{});

        print("  {s}Total files analyzed:{s}     {} files with test blocks\n", .{ ANSI.BOLD, ANSI.RESET, total_files_with_tests });
        print("  {s}Test barrels found:{s}       {s}{}{s} test.zig files\n", .{ ANSI.BOLD, ANSI.RESET, ANSI.GREEN, test_barrels.len, ANSI.RESET });
        print("  {s}Properly covered:{s}         {s}{}{s} files imported by test.zig\n", .{ ANSI.BOLD, ANSI.RESET, ANSI.GREEN, files_with_coverage, ANSI.RESET });
        print("  {s}Missing coverage:{s}         {s}{}{s} files not imported\n", .{ ANSI.BOLD, ANSI.RESET, ANSI.RED, uncovered_files.len, ANSI.RESET });
        print("\n", .{});

        // Coverage percentage - red unless 100%
        if (coverage_percent >= 100.0) {
            print("  {s}{s}COVERAGE: {d:.1}%{s}\n", .{ ANSI.BOLD, ANSI.GREEN, coverage_percent, ANSI.RESET });
        } else {
            print("  {s}{s}COVERAGE: {d:.1}%{s}\n", .{ ANSI.BOLD, ANSI.RED, coverage_percent, ANSI.RESET });
        }

        print("\n", .{});
        print("▓ {s}Next steps: Import uncovered files into appropriate test.zig barrels{s}\n", .{ ANSI.DIM, ANSI.RESET });
    }

    fn exportToZon(self: *TestCoverageAnalyzer) !void {
        const output_path = self.config.output_file.?;
        if (self.config.pretty) {
            print("\n💾 Exporting analysis to {s}\n", .{output_path});
        }

        const file = try std.fs.cwd().createFile(output_path, .{});
        defer file.close();

        const writer = file.writer();
        try writer.print(".{{\n", .{});
        try writer.print("    .timestamp = \"{}\",\n", .{std.time.timestamp()});

        // Collect all files with tests (not test barrels)
        var test_files = ArrayList(*TestFile).init(self.allocator);
        defer test_files.deinit();

        var iterator = self.files.iterator();
        while (iterator.next()) |entry| {
            const test_file = entry.value_ptr;
            if (test_file.has_tests and !test_file.is_test_barrel) {
                try test_files.append(test_file);
            }
        }

        // Sort for consistent output
        std.mem.sort(*TestFile, test_files.items, {}, struct {
            fn lessThan(_: void, a: *TestFile, b: *TestFile) bool {
                return std.mem.order(u8, a.relative_path, b.relative_path) == .lt;
            }
        }.lessThan);

        try writer.print("    .files = .{{\n", .{});
        for (test_files.items) |test_file| {
            try writer.print("        .@\"./{s}/{s}\" = .{{\n", .{ self.config.src_root, test_file.relative_path });
            try writer.print("            .covered = {},\n", .{test_file.imported_by.items.len > 0});
            try writer.print("            .imported_by = .{{\n", .{});
            for (test_file.imported_by.items) |importer_path| {
                // Convert absolute path to relative with ./src/ prefix
                const relative_importer = if (std.mem.startsWith(u8, importer_path, self.config.src_root))
                    importer_path[self.config.src_root.len + 1 ..] // +1 to skip the '/'
                else
                    importer_path;
                try writer.print("                \"./{s}/{s}\",\n", .{ self.config.src_root, relative_importer });
            }
            try writer.print("            }},\n", .{});
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
        if (std.mem.eql(u8, arg, "--output") or std.mem.eql(u8, arg, "-o")) {
            if (i + 1 < args.len and !std.mem.startsWith(u8, args[i + 1], "--")) {
                i += 1;
                config.output_file = args[i];
            } else {
                config.output_file = "test_coverage.zon";
            }
        } else if (std.mem.eql(u8, arg, "--pretty")) {
            config.pretty = true;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            print("Test Coverage Checker\n\n", .{});
            print("Usage: zig run src/scripts/check_test_coverage.zig [options]\n\n", .{});
            print("Options:\n", .{});
            print("  -o, --output [file]    Export analysis to ZON format (default: test_coverage.zon)\n", .{});
            print("  --pretty               Show detailed human-readable report (default: minimal output)\n", .{});
            print("  --help, -h             Show this help\n\n", .{});
            print("Examples:\n", .{});
            print("  zig run src/scripts/check_test_coverage.zig\n", .{});
            print("  zig run src/scripts/check_test_coverage.zig -- --pretty\n", .{});
            print("  zig run src/scripts/check_test_coverage.zig -- --pretty -o coverage.zon\n", .{});
            return;
        }
    }

    var analyzer = TestCoverageAnalyzer.init(allocator, config);
    defer analyzer.deinit();

    try analyzer.analyze();
    const exit_code = try analyzer.generateReport();
    std.process.exit(exit_code);
}
