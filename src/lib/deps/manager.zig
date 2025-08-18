const std = @import("std");
const config = @import("config.zig");
const docs = @import("docs/mod.zig");
const Git = @import("../core/git.zig").Git;
const Versioning = @import("versioning.zig").Versioning;
const Operations = @import("operations.zig").Operations;
const LockGuard = @import("lock.zig").LockGuard;
// const parallel = @import("parallel.zig"); // TODO: Re-enable when compilation issues are fixed
const io = @import("../core/io.zig");
const path = @import("../core/path.zig");
const errors = @import("../core/errors.zig");
const collections = @import("../core/collections.zig");
const FilesystemInterface = @import("../filesystem/interface.zig").FilesystemInterface;
const RealFilesystem = @import("../filesystem/real.zig").RealFilesystem;

// Import terminal utilities for colored output and progress indicators
const terminal = @import("../terminal/terminal.zig");
const Color = @import("../terminal/colors.zig").Color;
const ProgressIndicator = @import("../terminal/progress.zig").ProgressIndicator;
const SimpleProgress = @import("../terminal/progress.zig").SimpleProgress;

/// Core dependency management functionality
pub const DependencyManager = struct {
    allocator: std.mem.Allocator,
    git: Git,
    versioning: Versioning,
    operations: Operations,
    deps_dir: []const u8,
    filesystem: FilesystemInterface,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, deps_dir: []const u8) Self {
        return Self.initWithFilesystem(allocator, deps_dir, RealFilesystem.init());
    }

    pub fn initWithFilesystem(allocator: std.mem.Allocator, deps_dir: []const u8, filesystem: FilesystemInterface) Self {
        return Self{
            .allocator = allocator,
            .git = Git.initWithFilesystem(allocator, filesystem),
            .versioning = Versioning.initWithFilesystem(allocator, filesystem),
            .operations = Operations.initWithFilesystem(allocator, filesystem),
            .deps_dir = deps_dir,
            .filesystem = filesystem,
        };
    }

    /// Update all dependencies based on configuration
    pub fn updateDependencies(self: *Self, dependencies: []const config.Dependency, options: config.UpdateOptions) !UpdateResult {
        var result = UpdateResult.init(self.allocator);
        errdefer result.deinit();

        // Acquire lock to prevent concurrent updates
        var lock_guard = LockGuard.acquire(self.allocator, self.deps_dir) catch |err| switch (err) {
            error.LockHeld => {
                try self.logError("Another dependency update is already running", .{});
                return error.LockHeld;
            },
            else => return err,
        };
        defer lock_guard.deinit();

        // Create deps directory if it doesn't exist
        try io.ensureDir(self.deps_dir);

        if (options.dry_run) {
            return try self.performDryRun(dependencies, options);
        }

        // Process each dependency
        for (dependencies) |dep| {
            if (options.force_dep) |forced_dep| {
                if (!std.mem.eql(u8, dep.name, forced_dep)) {
                    continue;
                }
            }

            if (options.update_pattern) |pattern| {
                if (!self.matchesPattern(dep.name, pattern)) {
                    continue;
                }
            }

            const update_needed = if (options.force_all or options.force_dep != null)
                true
            else
                try self.versioning.needsUpdate(dep.name, dep.version, self.deps_dir);

            if (!update_needed) {
                try result.skipped.append(dep.name);
                try self.logSkip("Skipping {s} (already up to date: {s})", .{ dep.name, dep.version });
                continue;
            }

            // Update dependency
            self.updateSingleDependency(&dep, options, &result) catch |err| {
                try result.failed.append(dep.name);

                // Provide specific error messages for dependency validation errors
                if (errors.isDependencyError(err)) {
                    try self.logError("Failed to update {s}: {s}", .{ dep.name, errors.getMessage(err) });
                } else {
                    try self.logError("Failed to update {s}: {}", .{ dep.name, err });
                }
                continue;
            };

            try result.updated.append(dep.name);
            try self.logSuccess("{s} updated successfully", .{dep.name});
        }

        // Generate documentation after successful updates
        if (result.updated.items.len > 0) {
            self.generateDocumentation(dependencies) catch |err| {
                try self.logWarning("Failed to generate dependency documentation: {}", .{err});
                // Don't fail the update operation for documentation errors
            };
        }

        return result;
    }

    /// Check status of all dependencies
    pub fn checkDependencies(self: *Self, dependencies: []const config.Dependency) !CheckResult {
        var result = CheckResult.init(self.allocator);
        errdefer result.deinit();

        for (dependencies) |dep| {
            const needs_update = try self.versioning.needsUpdate(dep.name, dep.version, self.deps_dir);

            const dep_dir = try path.joinPath(self.allocator, self.deps_dir, dep.name);
            defer self.allocator.free(dep_dir);

            const exists = io.fileExists(dep_dir) or io.isDirectory(dep_dir);

            if (!exists) {
                try result.missing.append(dep.name);
            } else if (needs_update) {
                try result.need_update.append(dep.name);
            } else {
                try result.up_to_date.append(dep.name);
            }
        }

        return result;
    }

    // TODO: Implement parallel checking - currently disabled due to compilation issues
    // /// Check status of all dependencies using parallel execution for better performance
    // pub fn checkDependenciesParallel(self: *Self, dependencies: []const config.Dependency) !CheckResult {
    //     // Implementation temporarily disabled
    //     return self.checkDependencies(dependencies);
    // }

    /// List all dependencies with their status
    pub fn listDependencies(self: *Self, dependencies: []const config.Dependency, options: config.UpdateOptions) !void {
        if (options.color) {
            try self.printColoredTable(dependencies);
        } else {
            try self.printPlainTable(dependencies);
        }
    }

    /// Perform dry run showing what would be updated
    fn performDryRun(self: *Self, dependencies: []const config.Dependency, options: config.UpdateOptions) !UpdateResult {
        var result = UpdateResult.init(self.allocator);
        errdefer result.deinit();

        try self.logInfo("Dry run: analyzing what would be updated...", .{});

        for (dependencies) |dep| {
            if (options.force_dep) |forced_dep| {
                if (!std.mem.eql(u8, dep.name, forced_dep)) {
                    continue;
                }
            }

            if (options.update_pattern) |pattern| {
                if (!self.matchesPattern(dep.name, pattern)) {
                    continue;
                }
            }

            const dep_dir = try path.joinPath(self.allocator, self.deps_dir, dep.name);
            defer self.allocator.free(dep_dir);

            const exists = io.fileExists(dep_dir) or io.isDirectory(dep_dir);

            if (!exists) {
                try self.logStep("Would INSTALL {s} ({s})", .{ dep.name, dep.version });
                try result.would_install.append(dep.name);
            } else {
                const needs_update = if (options.force_all or options.force_dep != null)
                    true
                else
                    try self.versioning.needsUpdate(dep.name, dep.version, self.deps_dir);

                if (needs_update) {
                    const version_info = try self.versioning.loadVersionInfo(dep_dir);
                    if (version_info) |vi| {
                        defer vi.deinit(self.allocator);
                        const force_msg = if (options.force_all or options.force_dep != null) " (forced)" else "";
                        try self.logStep("Would UPDATE {s} from {s} to {s}{s}", .{ dep.name, vi.version, dep.version, force_msg });
                    } else {
                        const force_msg = if (options.force_all or options.force_dep != null) " (forced)" else "";
                        try self.logStep("Would UPDATE {s} to {s}{s}", .{ dep.name, dep.version, force_msg });
                    }
                    try result.would_update.append(dep.name);
                } else {
                    try self.logStep("Would SKIP {s} (already {s})", .{ dep.name, dep.version });
                    try result.skipped.append(dep.name);
                }
            }
        }

        return result;
    }

    /// Update a single dependency
    fn updateSingleDependency(self: *Self, dep: *const config.Dependency, options: config.UpdateOptions, result: *UpdateResult) !void {
        _ = result;
        const dep_dir = try path.joinPath(self.allocator, self.deps_dir, dep.name);
        defer self.allocator.free(dep_dir);

        const temp_name = try std.fmt.allocPrint(self.allocator, "{s}-{d}", .{ dep.name, std.time.timestamp() });
        defer self.allocator.free(temp_name);
        const temp_parent = try path.joinPath(self.allocator, self.deps_dir, ".tmp");
        defer self.allocator.free(temp_parent);
        const temp_dir = try path.joinPath(self.allocator, temp_parent, temp_name);
        defer self.allocator.free(temp_dir);

        // Create temp directory
        try io.ensureDir(temp_parent);

        // Create backup if directory exists and backup is enabled
        var backup_path: ?[]u8 = null;
        defer if (backup_path) |bp| self.allocator.free(bp);

        if (options.backup) {
            const exists = io.fileExists(dep_dir) or io.isDirectory(dep_dir);

            if (exists) {
                backup_path = try self.operations.createBackup(dep_dir);
            }
        }

        // Preserve files if specified
        var preserved_files: [][]u8 = &.{};
        defer self.operations.freePreservedFiles(preserved_files);

        if (dep.preserve_files.len > 0) {
            const exists = io.fileExists(dep_dir) or io.isDirectory(dep_dir);

            if (exists) {
                preserved_files = try self.operations.preserveFiles(dep_dir, dep.preserve_files);
            }
        }

        // Clone to temp directory with progress indicator
        const clone_message = try std.fmt.allocPrint(self.allocator, "Fetching {s} ({s})", .{ dep.name, dep.version });
        defer self.allocator.free(clone_message);

        var progress = ProgressIndicator.init(self.allocator, clone_message);
        var frame_count: u32 = 0;

        // Show initial progress
        try progress.tick();

        // Start clone operation and get commit hash with pattern filtering
        const commit_hash = try self.git.cloneWithProgress(dep.url, dep.version, temp_dir, dep.include, dep.exclude, &progress, &frame_count);
        defer self.allocator.free(commit_hash);

        // Create version info
        const version_info = config.VersionInfo{
            .repository = dep.url,
            .version = dep.version,
            .commit = commit_hash,
            .updated = std.time.timestamp(),
            .updated_by = "", // Will be filled by toContent()
        };

        try self.versioning.saveVersionInfo(temp_dir, &version_info);

        // Atomic move to final location
        try SimpleProgress.show("Installing dependency");
        // Safe to ignore: If directory doesn't exist, that's fine - we're about to create it
        io.deleteTree(dep_dir) catch {};

        try self.operations.atomicMove(temp_dir, dep_dir);

        // Restore preserved files
        if (preserved_files.len > 0) {
            try self.operations.restorePreservedFiles(dep_dir, preserved_files);
        }
    }

    // Table layout constants
    const NAME_COL_WIDTH = 24;
    const VERSION_COL_WIDTH = 15;
    const STATUS_COL_WIDTH = 13;
    const DATE_COL_WIDTH = 24;

    /// Print colored status table
    fn printColoredTable(self: *Self, dependencies: []const config.Dependency) !void {
        const stdout = std.io.getStdOut().writer();

        try stdout.print("{s}Dependency Status Report{s}\n", .{ Color.bold, Color.reset });
        try stdout.writeAll("╔══════════════════════════════════════════════════════════════════════════════════════╗\n");
        try stdout.writeAll("║                                 Dependencies                                         ║\n");
        try stdout.writeAll("╠════════════════════════╦═════════════════╦═══════════════╦══════════════════════════╣\n");
        try stdout.writeAll("║ Name                   ║ Expected        ║ Status        ║ Last Updated             ║\n");
        try stdout.writeAll("╠════════════════════════╬═════════════════╬═══════════════╬══════════════════════════╣\n");

        for (dependencies) |dep| {
            const dep_dir = try path.joinPath(self.allocator, self.deps_dir, dep.name);
            defer self.allocator.free(dep_dir);

            var status: []const u8 = "Missing";
            var status_color: []const u8 = Color.red;
            var last_updated: []const u8 = "Never";

            const version_info = try self.versioning.loadVersionInfo(dep_dir);
            if (version_info) |vi| {
                defer vi.deinit(self.allocator);

                if (std.mem.eql(u8, vi.version, dep.version)) {
                    status = "Up to date";
                    status_color = Color.green;
                } else {
                    status = "Outdated";
                    status_color = Color.yellow;
                }
                // Format timestamp to human-readable date
                if (vi.updated > 0) {
                    const time_info = std.time.epoch.EpochSeconds{ .secs = @intCast(vi.updated) };
                    const epoch_day = time_info.getEpochDay();
                    const year_day = epoch_day.calculateYearDay();
                    const month_day = year_day.calculateMonthDay();

                    const formatted = try std.fmt.allocPrint(self.allocator, "{d:0>4}-{d:0>2}-{d:0>2}", .{
                        year_day.year,
                        month_day.month.numeric(),
                        month_day.day_index + 1,
                    });
                    defer self.allocator.free(formatted);

                    // Copy to a buffer that won't be freed immediately
                    var date_buf: [24]u8 = undefined;
                    const copied = std.fmt.bufPrint(&date_buf, "{s}", .{formatted}) catch "Invalid date";
                    last_updated = copied;
                } else {
                    last_updated = "Unknown";
                }
            }

            try stdout.print("║ {s:<24} ║ {s:<15} ║ {s}{s:<13}{s} ║ {s:<24} ║\n", .{
                dep.name,
                dep.version,
                status_color,
                status,
                Color.reset,
                last_updated,
            });
        }

        try stdout.writeAll("╚════════════════════════╩═════════════════╩═══════════════╩══════════════════════════╝\n");
    }

    /// Print plain status table
    fn printPlainTable(self: *Self, dependencies: []const config.Dependency) !void {
        const stdout = std.io.getStdOut().writer();

        try stdout.writeAll("Dependency Status Report\n");
        try stdout.writeAll("================================\n");
        try stdout.writeAll("Name                     | Expected        | Status        | Last Updated\n");
        try stdout.writeAll("------------------------|-----------------|---------------|------------------------\n");

        for (dependencies) |dep| {
            const dep_dir = try path.joinPath(self.allocator, self.deps_dir, dep.name);
            defer self.allocator.free(dep_dir);

            var status: []const u8 = "Missing";
            var last_updated: []const u8 = "Never";

            const version_info = try self.versioning.loadVersionInfo(dep_dir);
            if (version_info) |vi| {
                defer vi.deinit(self.allocator);

                if (std.mem.eql(u8, vi.version, dep.version)) {
                    status = "Up to date";
                } else {
                    status = "Outdated";
                }

                // Format timestamp to human-readable date
                if (vi.updated > 0) {
                    const time_info = std.time.epoch.EpochSeconds{ .secs = @intCast(vi.updated) };
                    const epoch_day = time_info.getEpochDay();
                    const year_day = epoch_day.calculateYearDay();
                    const month_day = year_day.calculateMonthDay();

                    const formatted = try std.fmt.allocPrint(self.allocator, "{d:0>4}-{d:0>2}-{d:0>2}", .{
                        year_day.year,
                        month_day.month.numeric(),
                        month_day.day_index + 1,
                    });
                    defer self.allocator.free(formatted);

                    // Copy to a buffer that won't be freed immediately
                    var date_buf: [24]u8 = undefined;
                    const copied = std.fmt.bufPrint(&date_buf, "{s}", .{formatted}) catch "Invalid date";
                    last_updated = copied;
                } else {
                    last_updated = "Unknown";
                }
            }

            try stdout.print("{s:<24} | {s:<15} | {s:<13} | {s:<24}\n", .{
                dep.name,
                dep.version,
                status,
                last_updated,
            });
        }
    }

    /// Pattern matching for dependency names
    pub fn matchesPattern(self: *Self, name: []const u8, pattern: []const u8) bool {
        _ = self;
        // Simple glob matching for now
        if (std.mem.eql(u8, pattern, "*")) return true;
        if (std.mem.endsWith(u8, pattern, "*")) {
            const prefix = pattern[0 .. pattern.len - 1];
            return std.mem.startsWith(u8, name, prefix);
        }
        if (std.mem.startsWith(u8, pattern, "*")) {
            const suffix = pattern[1..];
            return std.mem.endsWith(u8, name, suffix);
        }
        return std.mem.eql(u8, name, pattern);
    }

    // Logging functions
    fn logInfo(self: *Self, comptime fmt: []const u8, args: anytype) !void {
        _ = self;
        const stdout = std.io.getStdOut().writer();
        try stdout.print("📦 " ++ fmt ++ "\n", args);
    }

    fn logSuccess(self: *Self, comptime fmt: []const u8, args: anytype) !void {
        _ = self;
        const stdout = std.io.getStdOut().writer();
        try stdout.print("  ✓ " ++ fmt ++ "\n", args);
    }

    fn logStep(self: *Self, comptime fmt: []const u8, args: anytype) !void {
        _ = self;
        const stdout = std.io.getStdOut().writer();
        try stdout.print("  → " ++ fmt ++ "\n", args);
    }

    fn logSkip(self: *Self, comptime fmt: []const u8, args: anytype) !void {
        _ = self;
        const stdout = std.io.getStdOut().writer();
        try stdout.print("  ⏭ " ++ fmt ++ "\n", args);
    }

    fn logError(self: *Self, comptime fmt: []const u8, args: anytype) !void {
        _ = self;
        const stderr = std.io.getStdErr().writer();
        try stderr.print("  ✗ " ++ fmt ++ "\n", args);
    }

    fn logWarning(self: *Self, comptime fmt: []const u8, args: anytype) !void {
        _ = self;
        const stderr = std.io.getStdErr().writer();
        try stderr.print("  ⚠ " ++ fmt ++ "\n", args);
    }

    /// Generate dependency manifest.json
    fn generateDocumentation(self: *Self, dependencies: []const config.Dependency) !void {
        try self.logInfo("Generating dependency documentation...", .{});

        var doc_generator = docs.DocumentationGenerator.initWithFilesystem(self.allocator, self.filesystem, self.deps_dir);

        try doc_generator.generateDocumentation(dependencies);
        try self.logSuccess("Generated manifest.json", .{});
    }
};

/// Result of update operation
pub const UpdateResult = struct {
    updated: collections.List([]const u8),
    skipped: collections.List([]const u8),
    failed: collections.List([]const u8),
    would_install: collections.List([]const u8),
    would_update: collections.List([]const u8),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .updated = collections.List([]const u8).init(allocator),
            .skipped = collections.List([]const u8).init(allocator),
            .failed = collections.List([]const u8).init(allocator),
            .would_install = collections.List([]const u8).init(allocator),
            .would_update = collections.List([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.updated.deinit();
        self.skipped.deinit();
        self.failed.deinit();
        self.would_install.deinit();
        self.would_update.deinit();
    }
};

/// Result of check operation
pub const CheckResult = struct {
    up_to_date: collections.List([]const u8),
    need_update: collections.List([]const u8),
    missing: collections.List([]const u8),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .up_to_date = collections.List([]const u8).init(allocator),
            .need_update = collections.List([]const u8).init(allocator),
            .missing = collections.List([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.up_to_date.deinit();
        self.need_update.deinit();
        self.missing.deinit();
    }
};
