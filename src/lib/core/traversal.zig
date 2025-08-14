const std = @import("std");
const FilesystemInterface = @import("filesystem.zig").FilesystemInterface;
const SharedConfig = @import("../../config.zig").SharedConfig;
const shouldIgnorePath = @import("../../config.zig").shouldIgnorePath;
const shouldHideFile = @import("../../config.zig").shouldHideFile;
const path_utils = @import("path.zig");
const filesystem_utils = @import("filesystem.zig");

// Configuration constants
const MAX_TRAVERSAL_DEPTH = 20; // Maximum directory depth for traversal

/// Callback function type for handling discovered files during traversal
pub const FileCallback = *const fn (allocator: std.mem.Allocator, file_path: []const u8, context: ?*anyopaque) anyerror!void;

/// Callback function type for handling discovered directories during traversal  
pub const DirectoryCallback = *const fn (allocator: std.mem.Allocator, dir_path: []const u8, context: ?*anyopaque) anyerror!void;

/// Configuration for directory traversal behavior
pub const TraversalOptions = struct {
    /// Maximum depth to traverse (null = unlimited)
    max_depth: ?u32 = null,
    /// Whether to include hidden files/directories in results
    include_hidden: bool = false,
    /// Callback for each file encountered
    on_file: ?FileCallback = null,
    /// Callback for each directory encountered
    on_directory: ?DirectoryCallback = null,
    /// Context passed to callbacks
    context: ?*anyopaque = null,
    /// Whether to follow symlinks (default: false)
    follow_symlinks: bool = false,
};

/// Unified directory traversal utility with filesystem abstraction support
pub const DirectoryTraverser = struct {
    allocator: std.mem.Allocator,
    filesystem: FilesystemInterface,
    config: SharedConfig,
    options: TraversalOptions,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, filesystem: FilesystemInterface, config: SharedConfig, options: TraversalOptions) Self {
        return Self{
            .allocator = allocator,
            .filesystem = filesystem,
            .config = config,
            .options = options,
        };
    }

    /// Traverse a directory and collect all matching files into an ArrayList
    /// Caller owns the returned strings and must free them
    pub fn collectFiles(self: Self, start_path: []const u8, pattern: ?[]const u8) !std.ArrayList([]u8) {
        var results = std.ArrayList([]u8).init(self.allocator);
        errdefer {
            for (results.items) |path| {
                self.allocator.free(path);
            }
            results.deinit();
        }

        const context = TraversalContext{
            .results = &results,
            .pattern = pattern,
            .traverser = &self,
        };

        // Don't check ignore patterns for the initial directory
        try self.traverseRecursiveInternal(start_path, 0, &context, fileCollector, null, true);
        return results;
    }

    /// Traverse a directory recursively, calling provided callbacks for files/directories
    pub fn traverse(self: Self, start_path: []const u8) !void {
        // Don't check ignore patterns for the initial directory
        try self.traverseRecursiveInternal(start_path, 0, self.options.context, self.options.on_file, self.options.on_directory, true);
    }

    /// Public wrapper for recursive traversal (for backward compatibility)
    fn traverseRecursive(
        self: Self,
        dir_path: []const u8,
        depth: u32,
        context: ?*anyopaque,
        file_callback: ?FileCallback,
        dir_callback: ?DirectoryCallback,
    ) !void {
        // When called from subdirectories, check ignore patterns
        try self.traverseRecursiveInternal(dir_path, depth, context, file_callback, dir_callback, false);
    }

    /// Core recursive traversal implementation
    fn traverseRecursiveInternal(
        self: Self,
        dir_path: []const u8,
        depth: u32,
        context: ?*anyopaque,
        file_callback: ?FileCallback,
        dir_callback: ?DirectoryCallback,
        is_initial: bool,
    ) !void {
        // Check depth limit
        if (self.options.max_depth) |max_depth| {
            if (depth >= max_depth) return;
        }

        // Safety check for infinite recursion
        if (depth > MAX_TRAVERSAL_DEPTH) return;

        // Skip directories that match ignore patterns (but not the initial directory)
        if (!is_initial and shouldIgnorePath(self.config, dir_path)) {
            return;
        }

        // Call directory callback if provided
        if (dir_callback) |callback| {
            try callback(self.allocator, dir_path, context);
        }

        // Open directory for iteration using consolidated error handling
        const dir = try filesystem_utils.Operations.openDirSafely(
            self.filesystem, 
            self.allocator, 
            dir_path, 
            .{ .iterate = true }
        );
        const dir_handle = dir orelse return; // Safe to ignore common errors
        defer dir_handle.close();

        // Iterate through directory entries
        var iter = try dir_handle.iterate(self.allocator);
        while (try iter.next(self.allocator)) |entry| {
            // Build full path for this entry
            const full_path = try path_utils.joinPath(self.allocator, dir_path, entry.name);
            defer self.allocator.free(full_path);

            // Skip hidden files if not including them
            if (!self.options.include_hidden and path_utils.isHiddenFile(entry.name)) {
                continue;
            }

            // Skip files/directories that should be hidden
            if (shouldHideFile(self.config, entry.name)) {
                continue;
            }

            // Handle files
            if (entry.kind == .file) {
                if (file_callback) |callback| {
                    try callback(self.allocator, full_path, context);
                }
            }
            // Handle directories - recurse if not ignored
            else if (entry.kind == .directory) {
                if (!shouldIgnorePath(self.config, full_path)) {
                    try self.traverseRecursiveInternal(full_path, depth + 1, context, file_callback, dir_callback, false);
                }
            }
            // Handle symlinks if following them
            else if (entry.kind == .sym_link and self.options.follow_symlinks) {
                // Try to stat the symlink target to determine its type using consolidated error handling
                const stat = filesystem_utils.Operations.statFileSafely(self.filesystem, self.allocator, full_path) catch continue;
                if (stat) |s| {
                    if (s.kind == .file) {
                        if (file_callback) |callback| {
                            try callback(self.allocator, full_path, context);
                        }
                    } else if (s.kind == .directory and !shouldIgnorePath(self.config, full_path)) {
                        try self.traverseRecursiveInternal(full_path, depth + 1, context, file_callback, dir_callback, false);
                    }
                }
            }
        }
    }
};

/// Context structure for file collection
const TraversalContext = struct {
    results: *std.ArrayList([]u8),
    pattern: ?[]const u8,
    traverser: *const DirectoryTraverser,
};

/// File collector callback for building lists of matching files
fn fileCollector(allocator: std.mem.Allocator, file_path: []const u8, context_ptr: ?*anyopaque) !void {
    const context: *TraversalContext = @ptrCast(@alignCast(context_ptr.?));

    // If a pattern is specified, check if the file matches
    if (context.pattern) |pattern| {
        const filename = path_utils.basename(file_path);
        
        // Import glob patterns for matching - this creates a dependency but avoids duplication
        const glob_patterns = @import("../parsing/glob.zig");
        if (!glob_patterns.matchSimplePattern(filename, pattern)) {
            return; // File doesn't match pattern
        }
    }

    // Add matching file to results
    const owned_path = try allocator.dupe(u8, file_path);
    try context.results.append(owned_path);
}