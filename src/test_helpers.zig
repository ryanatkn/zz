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
            std.debug.print("\n📊 Test Suite Summary\n", .{});
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
                std.debug.print("│ {s:<12} │ {d:>3} tests │ {d:>6.1}ms ({d:>4.1}%) │ {d:>3}KB\n", 
                    .{ stat.name, stat.test_count, stat.duration_ms, percent, stat.memory_peak_kb });
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
