const std = @import("std");
const AstCache = @import("cache.zig").AstCache;
const AstCacheKey = @import("cache.zig").AstCacheKey;
const file_helpers = @import("file_helpers.zig");
const error_helpers = @import("error_helpers.zig");
const collection_helpers = @import("collection_helpers.zig");

/// File state for incremental processing
pub const FileState = struct {
    path: []const u8,
    hash: u64,              // Content hash using xxHash
    mtime: i64,             // Modification time (nanoseconds since epoch)
    size: usize,            // File size in bytes
    ast_cache_key: ?u64,    // Reference to cached AST
    imports: [][]const u8,  // What this file imports
    exports: [][]const u8,  // What this file exports
    dependents: [][]const u8, // Files that depend on this

    pub fn deinit(self: *FileState, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
        for (self.imports) |import| {
            allocator.free(import);
        }
        allocator.free(self.imports);
        for (self.exports) |export_name| {
            allocator.free(export_name);
        }
        allocator.free(self.exports);
        for (self.dependents) |dependent| {
            allocator.free(dependent);
        }
        allocator.free(self.dependents);
    }
};

/// Dependency graph for tracking file relationships
pub const DependencyGraph = struct {
    allocator: std.mem.Allocator,
    // path -> set of paths that depend on it
    dependents: std.HashMap([]const u8, std.ArrayList([]const u8), std.hash_map.StringContext, 80),
    // path -> set of paths it depends on
    dependencies: std.HashMap([]const u8, std.ArrayList([]const u8), std.hash_map.StringContext, 80),

    pub fn init(allocator: std.mem.Allocator) DependencyGraph {
        return DependencyGraph{
            .allocator = allocator,
            .dependents = std.HashMap([]const u8, std.ArrayList([]const u8), std.hash_map.StringContext, 80).init(allocator),
            .dependencies = std.HashMap([]const u8, std.ArrayList([]const u8), std.hash_map.StringContext, 80).init(allocator),
        };
    }

    pub fn deinit(self: *DependencyGraph) void {
        var dep_iter = self.dependents.iterator();
        while (dep_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            // Free all strings in the ArrayList
            for (entry.value_ptr.items) |item| {
                self.allocator.free(item);
            }
            entry.value_ptr.deinit();
        }
        self.dependents.deinit();

        var deps_iter = self.dependencies.iterator();
        while (deps_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            // Free all strings in the ArrayList
            for (entry.value_ptr.items) |item| {
                self.allocator.free(item);
            }
            entry.value_ptr.deinit();
        }
        self.dependencies.deinit();
    }

    /// Add a dependency relationship: from_file depends on to_file
    pub fn addDependency(self: *DependencyGraph, from_file: []const u8, to_file: []const u8) !void {
        // Add to dependencies map (from_file -> to_file)
        const from_key = try self.allocator.dupe(u8, from_file);
        const to_key = try self.allocator.dupe(u8, to_file);
        
        var result = try self.dependencies.getOrPut(from_key);
        if (!result.found_existing) {
            result.value_ptr.* = std.ArrayList([]const u8).init(self.allocator);
        }
        try result.value_ptr.append(to_key);

        // Add to dependents map (to_file -> from_file)
        const to_key_dup = try self.allocator.dupe(u8, to_file);
        const from_key_dup = try self.allocator.dupe(u8, from_file);
        
        var dependents_result = try self.dependents.getOrPut(to_key_dup);
        if (!dependents_result.found_existing) {
            dependents_result.value_ptr.* = std.ArrayList([]const u8).init(self.allocator);
        }
        try dependents_result.value_ptr.append(from_key_dup);
    }

    /// Get all files that depend on the given file (directly or indirectly)
    pub fn getDependents(self: *DependencyGraph, file_path: []const u8, result: *std.ArrayList([]const u8)) !void {
        var visited = std.HashMap([]const u8, void, std.hash_map.StringContext, 80).init(self.allocator);
        defer visited.deinit();
        
        try self.getDependentsRecursive(file_path, &visited, result);
    }

    fn getDependentsRecursive(self: *DependencyGraph, file_path: []const u8, visited: *std.HashMap([]const u8, void, std.hash_map.StringContext, 80), result: *std.ArrayList([]const u8)) !void {
        if (visited.contains(file_path)) return;
        try visited.put(file_path, {});

        if (self.dependents.get(file_path)) |direct_dependents| {
            for (direct_dependents.items) |dependent| {
                try result.append(dependent);
                try self.getDependentsRecursive(dependent, visited, result);
            }
        }
    }
};

/// Change detection result
pub const ChangeType = enum {
    unchanged,      // File hasn't changed
    content,        // File content changed
    dependencies,   // File dependencies changed (imports/exports)
    new,           // New file
    deleted,       // File was deleted
};

pub const FileChange = struct {
    path: []const u8,
    change_type: ChangeType,
    old_state: ?FileState,
    new_state: ?FileState,
};

/// Fast file hashing using xxHash - now using shared file helpers
pub fn hashFile(allocator: std.mem.Allocator, file_path: []const u8) !u64 {
    return file_helpers.FileHelpers.hashFile(allocator, file_path);
}

/// Get file modification time in nanoseconds since epoch - using shared file helpers
pub fn getFileModTime(file_path: []const u8) !i64 {
    if (try file_helpers.FileHelpers.getModTime(file_path)) |mtime| {
        return mtime * std.time.ns_per_s; // Convert to nanoseconds
    }
    return 0;
}

/// Get file size
pub fn getFileSize(file_path: []const u8) !usize {
    const stat = std.fs.cwd().statFile(file_path) catch |err| switch (err) {
        error.FileNotFound => return 0,
        else => return err,
    };
    
    return @intCast(stat.size);
}

/// File change detector for incremental processing
pub const ChangeDetector = struct {
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) ChangeDetector {
        return ChangeDetector{
            .allocator = allocator,
        };
    }

    /// Detect changes between old and new file states - using improved error handling
    pub fn detectFileChange(self: *ChangeDetector, file_path: []const u8, old_state: ?FileState) !FileChange {
        // Check if file still exists using enhanced error handling
        const mtime_result = error_helpers.ErrorHelpers.safeFileOperation(
            i64, 
            getFileModTime(file_path)
        );
        
        const new_mtime = switch (mtime_result) {
            .success => |mtime| mtime,
            .not_found => {
                return FileChange{
                    .path = file_path,
                    .change_type = if (old_state != null) .deleted else .unchanged,
                    .old_state = old_state,
                    .new_state = null,
                };
            },
            .access_denied => {
                error_helpers.ErrorHelpers.handleFsError(error.AccessDenied, "detecting file change", file_path);
                return FileChange{
                    .path = file_path,
                    .change_type = .unchanged, // Can't determine, assume unchanged
                    .old_state = old_state,
                    .new_state = old_state,
                };
            },
            .other_error => |err| return err,
        };

        // If we have no old state, this is a new file
        if (old_state == null) {
            const new_hash = try hashFile(self.allocator, file_path);
            const new_size = try getFileSize(file_path);
            const path_copy = try self.allocator.dupe(u8, file_path);
            
            return FileChange{
                .path = file_path,
                .change_type = .new,
                .old_state = null,
                .new_state = FileState{
                    .path = path_copy,
                    .hash = new_hash,
                    .mtime = new_mtime,
                    .size = new_size,
                    .ast_cache_key = null,
                    .imports = &.{},
                    .exports = &.{},
                    .dependents = &.{},
                },
            };
        }

        const old = old_state.?;

        // Fast path: check modification time and size first
        const new_size = try getFileSize(file_path);
        if (new_mtime == old.mtime and new_size == old.size) {
            return FileChange{
                .path = file_path,
                .change_type = .unchanged,
                .old_state = old_state,
                .new_state = old_state,
            };
        }

        // Content might have changed, compute hash
        const new_hash = try hashFile(self.allocator, file_path);
        if (new_hash == old.hash) {
            // File touched but content unchanged
            return FileChange{
                .path = file_path,
                .change_type = .unchanged,
                .old_state = old_state,
                .new_state = old_state,
            };
        }

        // Content changed - need to determine if dependencies changed too
        // For now, assume content change (dependency analysis comes later)
        const path_copy = try self.allocator.dupe(u8, file_path);
        return FileChange{
            .path = file_path,
            .change_type = .content,
            .old_state = old_state,
            .new_state = FileState{
                .path = path_copy,
                .hash = new_hash,
                .mtime = new_mtime,
                .size = new_size,
                .ast_cache_key = null, // Will be updated after parsing
                .imports = &.{},       // Will be updated after analysis
                .exports = &.{},       // Will be updated after analysis  
                .dependents = &.{},    // Will be updated after analysis
            },
        };
    }
};

/// File tracker for maintaining incremental state
pub const FileTracker = struct {
    allocator: std.mem.Allocator,
    files: std.HashMap([]const u8, FileState, std.hash_map.StringContext, 80),
    dependency_graph: DependencyGraph,
    change_detector: ChangeDetector,
    ast_cache: ?*AstCache, // Optional AST cache for invalidation

    pub fn init(allocator: std.mem.Allocator) FileTracker {
        return FileTracker{
            .allocator = allocator,
            .files = std.HashMap([]const u8, FileState, std.hash_map.StringContext, 80).init(allocator),
            .dependency_graph = DependencyGraph.init(allocator),
            .change_detector = ChangeDetector.init(allocator),
            .ast_cache = null,
        };
    }

    pub fn initWithAstCache(allocator: std.mem.Allocator, ast_cache: *AstCache) FileTracker {
        return FileTracker{
            .allocator = allocator,
            .files = std.HashMap([]const u8, FileState, std.hash_map.StringContext, 80).init(allocator),
            .dependency_graph = DependencyGraph.init(allocator),
            .change_detector = ChangeDetector.init(allocator),
            .ast_cache = ast_cache,
        };
    }

    pub fn deinit(self: *FileTracker) void {
        var iter = self.files.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(self.allocator);
        }
        self.files.deinit();
        self.dependency_graph.deinit();
    }

    /// Track a new file or update existing file state
    pub fn trackFile(self: *FileTracker, file_path: []const u8) !void {
        const change = try self.change_detector.detectFileChange(file_path, self.files.get(file_path));
        
        switch (change.change_type) {
            .unchanged => {
                // Nothing to do
            },
            .new, .content => {
                if (change.new_state) |new_state| {
                    const key = try self.allocator.dupe(u8, file_path);
                    
                    // Invalidate AST cache entries for this file
                    if (self.ast_cache) |cache| {
                        try self.invalidateAstCacheForFile(cache, file_path);
                    }
                    
                    // Remove old state if it exists
                    if (self.files.fetchRemove(key)) |old_entry| {
                        self.allocator.free(old_entry.key);
                        var mutable_value = old_entry.value;
                        mutable_value.deinit(self.allocator);
                    }
                    
                    // Add new state
                    try self.files.put(key, new_state);
                }
            },
            .deleted => {
                if (self.files.fetchRemove(file_path)) |old_entry| {
                    self.allocator.free(old_entry.key);
                    var mutable_value = old_entry.value;
                    mutable_value.deinit(self.allocator);
                }
            },
            .dependencies => {
                // TODO: Handle dependency changes
            },
        }
    }

    /// Get current state of a tracked file
    pub fn getFileState(self: *FileTracker, file_path: []const u8) ?FileState {
        return self.files.get(file_path);
    }

    /// Get all tracked files
    pub fn getAllFiles(self: *FileTracker) []const []const u8 {
        var result = self.allocator.alloc([]const u8, self.files.count()) catch unreachable;
        var iter = self.files.keyIterator();
        var i: usize = 0;
        while (iter.next()) |key| {
            result[i] = key.*;
            i += 1;
        }
        return result;
    }

    /// Get files that have changed since last tracking
    pub fn getChangedFiles(self: *FileTracker, file_paths: []const []const u8, result: *std.ArrayList([]const u8)) !void {
        for (file_paths) |file_path| {
            const change = try self.change_detector.detectFileChange(file_path, self.files.get(file_path));
            if (change.change_type != .unchanged) {
                try result.append(file_path);
            }
        }
    }

    /// Invalidate AST cache entries for a file
    fn invalidateAstCacheForFile(self: *FileTracker, cache: *AstCache, file_path: []const u8) !void {
        // Get the file's current hash (if it exists)
        if (self.files.get(file_path)) |file_state| {
            // Invalidate all cache entries for this file by removing entries with matching file hash
            try cache.invalidateByFileHash(file_state.hash);
        }
    }

    /// Invalidate AST cache entries for multiple files
    pub fn invalidateAstCacheForFiles(self: *FileTracker, file_paths: []const []const u8) !void {
        if (self.ast_cache) |cache| {
            for (file_paths) |file_path| {
                try self.invalidateAstCacheForFile(cache, file_path);
            }
        }
    }

    /// Get or create AST cache key for a file with extraction flags
    pub fn getAstCacheKey(self: *FileTracker, file_path: []const u8, extraction_flags_hash: u64) ?AstCacheKey {
        if (self.files.get(file_path)) |file_state| {
            return AstCacheKey.init(
                file_state.hash,
                1, // parser version - could be made configurable
                extraction_flags_hash
            );
        }
        return null;
    }

    /// Cascade invalidation for dependent files
    pub fn cascadeInvalidation(self: *FileTracker, changed_file: []const u8) !void {
        if (self.ast_cache == null) return;
        
        var dependents = collection_helpers.CollectionHelpers.ManagedArrayList([]const u8).init(self.allocator);
        defer dependents.deinit();
        
        // Get all files that depend on the changed file
        try self.dependency_graph.getDependents(changed_file, &dependents);
        
        // Invalidate cache for all dependent files
        try self.invalidateAstCacheForFiles(dependents.items);
    }
};

/// Incremental state for persistence
pub const IncrementalState = struct {
    files: std.HashMap([]const u8, FileState, std.hash_map.StringContext, 80),
    dependency_graph: DependencyGraph,
    cache_version: u32,
    last_run: i64,
    
    pub fn init(allocator: std.mem.Allocator) IncrementalState {
        return IncrementalState{
            .files = std.HashMap([]const u8, FileState, std.hash_map.StringContext, 80).init(allocator),
            .dependency_graph = DependencyGraph.init(allocator),
            .cache_version = 1,
            .last_run = @as(i64, @intCast(std.time.nanoTimestamp())),
        };
    }
    
    pub fn deinit(self: *IncrementalState, allocator: std.mem.Allocator) void {
        var iter = self.files.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(allocator);
        }
        self.files.deinit();
        self.dependency_graph.deinit();
    }
    
    /// Save state to file
    pub fn saveToFile(self: *IncrementalState, allocator: std.mem.Allocator, file_path: []const u8) !void {
        // Create .zz directory if it doesn't exist - using shared file helpers
        try file_helpers.FileHelpers.ensureDir(".zz");
        
        // Serialize state to JSON
        var json_data = collection_helpers.CollectionHelpers.ManagedArrayList(u8).init(allocator);
        defer json_data.deinit();
        
        try self.writeJson(&json_data);
        
        // Write to file atomically (write to temp file, then rename)
        const temp_path = try std.fmt.allocPrint(allocator, "{s}.tmp", .{file_path});
        defer allocator.free(temp_path);
        
        const file = try std.fs.cwd().createFile(temp_path, .{});
        defer file.close();
        
        try file.writeAll(json_data.items);
        
        // Atomic rename
        try std.fs.cwd().rename(temp_path, file_path);
    }
    
    /// Load state from file - using shared file helpers
    pub fn loadFromFile(allocator: std.mem.Allocator, file_path: []const u8) !IncrementalState {
        const reader = file_helpers.FileHelpers.SafeFileReader.init(allocator);
        const content = reader.readToStringOptional(file_path, 16 * 1024 * 1024) catch |err| {
            error_helpers.ErrorHelpers.handleFsError(err, "loading incremental state", file_path);
            return err;
        };
        
        if (content) |file_content| {
            defer allocator.free(file_content);
            return try parseJson(allocator, file_content);
        } else {
            // File doesn't exist, return empty state
            return IncrementalState.init(allocator);
        }
    }
    
    /// Write state as JSON
    fn writeJson(self: *IncrementalState, writer: *std.ArrayList(u8)) !void {
        try writer.appendSlice("{\n");
        try writer.writer().print("  \"cache_version\": {},\n", .{self.cache_version});
        try writer.writer().print("  \"last_run\": {},\n", .{self.last_run});
        try writer.appendSlice("  \"files\": {\n");
        
        var file_iter = self.files.iterator();
        var first_file = true;
        while (file_iter.next()) |entry| {
            if (!first_file) try writer.appendSlice(",\n");
            first_file = false;
            
            try writer.writer().print("    \"{s}\": {{\n", .{entry.key_ptr.*});
            try writer.writer().print("      \"hash\": {},\n", .{entry.value_ptr.hash});
            try writer.writer().print("      \"mtime\": {},\n", .{entry.value_ptr.mtime});
            try writer.writer().print("      \"size\": {}\n", .{entry.value_ptr.size});
            try writer.appendSlice("    }");
        }
        
        try writer.appendSlice("\n  }\n");
        try writer.appendSlice("}\n");
    }
    
    /// Parse state from JSON
    fn parseJson(allocator: std.mem.Allocator, json_content: []const u8) !IncrementalState {
        // For now, use a simple JSON parser
        // In production, you'd want to use a proper JSON library
        
        var state = IncrementalState.init(allocator);
        
        // Parse basic fields (simplified parsing)
        if (std.mem.indexOf(u8, json_content, "\"cache_version\": ")) |start| {
            const num_start = start + "\"cache_version\": ".len;
            if (std.mem.indexOf(u8, json_content[num_start..], ",")) |end| {
                const version_str = json_content[num_start..num_start + end];
                state.cache_version = std.fmt.parseInt(u32, version_str, 10) catch 1;
            }
        }
        
        if (std.mem.indexOf(u8, json_content, "\"last_run\": ")) |start| {
            const num_start = start + "\"last_run\": ".len;
            if (std.mem.indexOf(u8, json_content[num_start..], ",")) |end| {
                const time_str = json_content[num_start..num_start + end];
                state.last_run = std.fmt.parseInt(i64, time_str, 10) catch @as(i64, @intCast(std.time.nanoTimestamp()));
            }
        }
        
        // TODO: Parse files section properly
        // This is a simplified implementation
        
        return state;
    }
};

/// Enhanced file tracker with persistence
pub const PersistentFileTracker = struct {
    base_tracker: FileTracker,
    state_file_path: []const u8,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, state_file_path: []const u8) PersistentFileTracker {
        return PersistentFileTracker{
            .base_tracker = FileTracker.init(allocator),
            .state_file_path = state_file_path,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *PersistentFileTracker) void {
        self.base_tracker.deinit();
    }
    
    /// Load state from disk
    pub fn loadState(self: *PersistentFileTracker) !void {
        var state = IncrementalState.loadFromFile(self.allocator, self.state_file_path) catch |err| switch (err) {
            error.FileNotFound => {
                // No existing state, start fresh
                return;
            },
            else => return err,
        };
        defer state.deinit(self.allocator);
        
        // Copy loaded state to tracker
        var iter = state.files.iterator();
        while (iter.next()) |entry| {
            const key = try self.allocator.dupe(u8, entry.key_ptr.*);
            try self.base_tracker.files.put(key, entry.value_ptr.*);
        }
    }
    
    /// Save state to disk
    pub fn saveState(self: *PersistentFileTracker) !void {
        var state = IncrementalState{
            .files = self.base_tracker.files,
            .dependency_graph = self.base_tracker.dependency_graph,
            .cache_version = 1,
            .last_run = @as(i64, @intCast(std.time.nanoTimestamp())),
        };
        
        try state.saveToFile(self.allocator, self.state_file_path);
    }
    
    /// Forward methods to base tracker
    pub fn trackFile(self: *PersistentFileTracker, file_path: []const u8) !void {
        return self.base_tracker.trackFile(file_path);
    }
    
    pub fn getFileState(self: *PersistentFileTracker, file_path: []const u8) ?FileState {
        return self.base_tracker.getFileState(file_path);
    }
    
    pub fn getChangedFiles(self: *PersistentFileTracker, file_paths: []const []const u8, result: *std.ArrayList([]const u8)) !void {
        return self.base_tracker.getChangedFiles(file_paths, result);
    }
};

// Tests
test "file hashing" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Create a temporary file
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const content = "test content for hashing";
    try tmp_dir.dir.writeFile(.{ .sub_path = "test.txt", .data = content });

    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, "test.txt");
    defer allocator.free(tmp_path);

    const hash1 = try hashFile(allocator, tmp_path);
    const hash2 = try hashFile(allocator, tmp_path);
    
    try testing.expect(hash1 == hash2);
    try testing.expect(hash1 != 0);
}

test "change detection" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var detector = ChangeDetector.init(allocator);

    // Test new file detection
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.writeFile(.{ .sub_path = "new.txt", .data = "content" });
    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, "new.txt");
    defer allocator.free(tmp_path);

    const change = try detector.detectFileChange(tmp_path, null);
    try testing.expect(change.change_type == .new);
    
    // Clean up allocated path in new_state
    if (change.new_state) |*state| {
        var mutable_state = state.*;
        mutable_state.deinit(allocator);
    }
}

test "file tracker" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var tracker = FileTracker.init(allocator);
    defer tracker.deinit();

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.writeFile(.{ .sub_path = "track.txt", .data = "content" });
    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, "track.txt");
    defer allocator.free(tmp_path);

    try tracker.trackFile(tmp_path);
    
    const state = tracker.getFileState(tmp_path);
    try testing.expect(state != null);
    try testing.expect(state.?.hash != 0);
}

test "dependency graph" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var graph = DependencyGraph.init(allocator);
    defer graph.deinit();

    try graph.addDependency("a.zig", "b.zig");
    try graph.addDependency("b.zig", "c.zig");
    
    var dependents = std.ArrayList([]const u8).init(allocator);
    defer dependents.deinit();
    
    try graph.getDependents("c.zig", &dependents);
    try testing.expect(dependents.items.len == 2); // a.zig and b.zig depend on c.zig
}