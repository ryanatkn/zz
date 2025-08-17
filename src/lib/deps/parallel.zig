const std = @import("std");
const config = @import("config.zig");
const Git = @import("../core/git.zig").Git;
const collections = @import("../core/collections.zig");
const FilesystemInterface = @import("../filesystem/interface.zig").FilesystemInterface;

/// Result of checking a single dependency
pub const CheckResult = struct {
    name: []const u8,
    status: Status,
    current_version: ?[]const u8 = null,
    latest_version: ?[]const u8 = null,
    error_message: ?[]const u8 = null,
    
    pub const Status = enum {
        up_to_date,
        needs_update,
        missing,
        failed,
    };
    
    pub fn deinit(self: *CheckResult, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        if (self.current_version) |v| allocator.free(v);
        if (self.latest_version) |v| allocator.free(v);
        if (self.error_message) |msg| allocator.free(msg);
    }
};

/// Context for a single dependency check
const CheckContext = struct {
    dependency: config.Dependency,
    git: Git,
    deps_dir: []const u8,
    result: *CheckResult,
    allocator: std.mem.Allocator,
};

/// Parallel dependency checker
pub const ParallelChecker = struct {
    allocator: std.mem.Allocator,
    filesystem: FilesystemInterface,
    deps_dir: []const u8,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator, filesystem: FilesystemInterface, deps_dir: []const u8) Self {
        return Self{
            .allocator = allocator,
            .filesystem = filesystem,
            .deps_dir = deps_dir,
        };
    }
    
    /// Check all dependencies in parallel
    pub fn checkAll(self: *Self, dependencies: []const config.Dependency) ![]CheckResult {
        if (dependencies.len == 0) {
            return &.{};
        }
        
        // Allocate results array
        var results = try self.allocator.alloc(CheckResult, dependencies.len);
        errdefer {
            for (results) |*result| {
                result.deinit(self.allocator);
            }
            self.allocator.free(results);
        }
        
        // Single-threaded fallback for small numbers or unsupported platforms
        if (dependencies.len < 3 or !std.Thread.use_pthreads) {
            return self.checkSequential(dependencies, results);
        }
        
        // Parallel execution for larger workloads
        return self.checkParallel(dependencies, results);
    }
    
    /// Sequential fallback implementation
    fn checkSequential(self: *Self, dependencies: []const config.Dependency, results: []CheckResult) ![]CheckResult {
        for (dependencies, 0..) |dep, i| {
            results[i] = try self.checkSingle(dep);
        }
        return results;
    }
    
    /// Parallel implementation using thread pool
    fn checkParallel(self: *Self, dependencies: []const config.Dependency, results: []CheckResult) ![]CheckResult {
        const max_threads = @min(dependencies.len, 4); // Limit to 4 concurrent checks
        var threads = try self.allocator.alloc(std.Thread, max_threads);
        defer self.allocator.free(threads);
        
        var contexts = try self.allocator.alloc(CheckContext, dependencies.len);
        defer self.allocator.free(contexts);
        
        // Initialize contexts
        for (dependencies, 0..) |dep, i| {
            contexts[i] = CheckContext{
                .dependency = dep,
                .git = Git.initWithFilesystem(self.allocator, self.filesystem),
                .deps_dir = self.deps_dir,
                .result = &results[i],
                .allocator = self.allocator,
            };
        }
        
        // Process dependencies in batches
        var completed: usize = 0;
        while (completed < dependencies.len) {
            const batch_size = @min(max_threads, dependencies.len - completed);
            
            // Start threads for current batch
            for (0..batch_size) |i| {
                const ctx_index = completed + i;
                threads[i] = try std.Thread.spawn(.{}, checkSingleThreaded, .{&contexts[ctx_index]});
            }
            
            // Wait for batch to complete
            for (0..batch_size) |i| {
                threads[i].join();
            }
            
            completed += batch_size;
        }
        
        return results;
    }
    
    /// Thread entry point for parallel checking
    fn checkSingleThreaded(context: *CheckContext) void {
        context.result.* = checkSingleInContext(context) catch |err| CheckResult{
            .name = context.allocator.dupe(u8, context.dependency.name) catch "unknown",
            .status = .failed,
            .error_message = context.allocator.dupe(u8, @errorName(err)) catch null,
        };
    }
    
    /// Check a single dependency (thread-safe)
    fn checkSingleInContext(context: *CheckContext) !CheckResult {
        const dep = context.dependency;
        const allocator = context.allocator;
        
        // Check if dependency directory exists
        const dep_dir = try std.fs.path.join(allocator, &.{ context.deps_dir, dep.name });
        defer allocator.free(dep_dir);
        
        const dep_exists = context.git.filesystem.directoryExists(dep_dir);
        
        if (!dep_exists) {
            return CheckResult{
                .name = try allocator.dupe(u8, dep.name),
                .status = .missing,
            };
        }
        
        // Read current version
        const current_version = getCurrentVersion(allocator, dep_dir) catch |err| {
            return CheckResult{
                .name = try allocator.dupe(u8, dep.name),
                .status = .failed,
                .error_message = try allocator.dupe(u8, @errorName(err)),
            };
        };
        
        // For now, we'll use a simplified check since implementing getLatestVersion
        // requires significant Git infrastructure. We'll check if we have the requested version.
        const needs_update = !std.mem.eql(u8, current_version, dep.version);
        
        return CheckResult{
            .name = try allocator.dupe(u8, dep.name),
            .status = if (needs_update) .needs_update else .up_to_date,
            .current_version = current_version,
            .latest_version = try allocator.dupe(u8, dep.version),
        };
    }
    
    /// Check a single dependency (sequential)
    fn checkSingle(self: *Self, dep: config.Dependency) !CheckResult {
        var context = CheckContext{
            .dependency = dep,
            .git = Git.initWithFilesystem(self.allocator, self.filesystem),
            .deps_dir = self.deps_dir,
            .result = undefined,
            .allocator = self.allocator,
        };
        
        return checkSingleInContext(&context);
    }
    
    /// Read current version from .version file
    fn getCurrentVersion(allocator: std.mem.Allocator, dep_dir: []const u8) ![]const u8 {
        const version_file = try std.fs.path.join(allocator, &.{ dep_dir, ".version" });
        defer allocator.free(version_file);
        
        const content = std.fs.cwd().readFileAlloc(allocator, version_file, 1024) catch |err| switch (err) {
            error.FileNotFound => return allocator.dupe(u8, "unknown"),
            else => return err,
        };
        defer allocator.free(content);
        
        // Parse version from content (simple format)
        var lines = std.mem.splitSequence(u8, content, "\n");
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r\n");
            if (std.mem.startsWith(u8, trimmed, "Version: ")) {
                return allocator.dupe(u8, trimmed[9..]);
            }
        }
        
        return allocator.dupe(u8, "unknown");
    }
};

// Tests
test "ParallelChecker - empty dependencies" {
    const testing = std.testing;
    const MockFilesystem = @import("../filesystem/mock.zig").MockFilesystem;
    
    var mock_fs = MockFilesystem.init(testing.allocator);
    defer mock_fs.deinit();
    
    var checker = ParallelChecker.init(testing.allocator, mock_fs.interface(), "deps");
    
    const results = try checker.checkAll(&.{});
    defer testing.allocator.free(results);
    
    try testing.expect(results.len == 0);
}

test "ParallelChecker - single dependency missing" {
    const testing = std.testing;
    const MockFilesystem = @import("../filesystem/mock.zig").MockFilesystem;
    
    var mock_fs = MockFilesystem.init(testing.allocator);
    defer mock_fs.deinit();
    
    var checker = ParallelChecker.init(testing.allocator, mock_fs.interface(), "deps");
    
    const deps = [_]config.Dependency{.{
        .name = "test-dep",
        .url = "https://github.com/test/repo.git",
        .version = "v1.0.0",
        .owns_memory = false,
    }};
    
    const results = try checker.checkAll(&deps);
    defer {
        for (results) |*result| {
            result.deinit(testing.allocator);
        }
        testing.allocator.free(results);
    }
    
    try testing.expect(results.len == 1);
    try testing.expect(results[0].status == .missing);
    try testing.expect(std.mem.eql(u8, results[0].name, "test-dep"));
}