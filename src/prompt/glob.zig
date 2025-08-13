const std = @import("std");
const FilesystemInterface = @import("../filesystem/interface.zig").FilesystemInterface;
const DirHandle = @import("../filesystem/interface.zig").DirHandle;
const SharedConfig = @import("../config.zig").SharedConfig;
const shouldIgnorePath = @import("../config.zig").shouldIgnorePath;
const shouldHideFile = @import("../config.zig").shouldHideFile;
const path_utils = @import("../lib/path.zig");
const glob_patterns = @import("../patterns/glob.zig");
const traversal = @import("../lib/traversal.zig");

// Configuration constants
const MAX_GLOB_DEPTH = 20; // Maximum directory depth for ** patterns
const MAX_PATTERN_LENGTH = 4096; // Maximum pattern length to prevent DOS

// Use path utilities from shared module
const isHiddenFile = path_utils.isHiddenFile;
const patternMatchesHidden = path_utils.patternMatchesHidden;
const joinPath = path_utils.joinPath;

/// Transfer ownership of paths from source to destination ArrayList
fn transferPaths(source: []const []u8, dest: *std.ArrayList([]u8)) !void {
    for (source) |path| {
        try dest.append(path);
    }
}

pub const GlobExpander = struct {
    allocator: std.mem.Allocator,
    filesystem: FilesystemInterface,
    config: SharedConfig,
    arena: ?std.heap.ArenaAllocator = null, // Optional arena for temporary allocations

    const Self = @This();

    /// Result from expanding a single pattern
    pub const PatternResult = struct {
        pattern: []const u8,
        files: std.ArrayList([]u8),
        is_glob: bool,
    };

    /// Check if a pattern contains glob characters
    pub fn isGlobPattern(pattern: []const u8) bool {
        for (pattern) |c| {
            if (c == '*' or c == '?' or c == '[' or c == '{') {
                return true;
            }
        }
        return false;
    }

    /// Expand multiple glob patterns with arena optimization
    pub fn expandGlobs(self: Self, patterns: []const []const u8) !std.ArrayList([]u8) {
        // Create arena for temporary allocations during expansion
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        var results = std.ArrayList([]u8).init(self.allocator);
        errdefer {
            for (results.items) |path| {
                self.allocator.free(path);
            }
            results.deinit();
        }

        // Create a temporary expander with arena for intermediate allocations
        var temp_expander = Self{
            .allocator = arena.allocator(),
            .filesystem = self.filesystem,
            .config = self.config,
            .arena = arena,
        };

        for (patterns) |pattern| {
            var expanded = try temp_expander.expandSingleGlobOwned(pattern);
            defer expanded.deinit();

            // Copy paths to final allocator (not arena)
            for (expanded.items) |path| {
                const owned_path = try self.allocator.dupe(u8, path);
                try results.append(owned_path);
            }
        }

        return results;
    }

    /// Expand patterns with detailed information about each pattern (arena optimized)
    pub fn expandPatternsWithInfo(self: Self, patterns: []const []const u8) !std.ArrayList(PatternResult) {
        // Create arena for temporary allocations during expansion
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        var results = std.ArrayList(PatternResult).init(self.allocator);
        errdefer {
            for (results.items) |*result| {
                for (result.files.items) |path| {
                    self.allocator.free(path);
                }
                result.files.deinit();
            }
            results.deinit();
        }

        // Create a temporary expander with arena for intermediate allocations
        var temp_expander = Self{
            .allocator = arena.allocator(),
            .filesystem = self.filesystem,
            .config = self.config,
            .arena = arena,
        };

        for (patterns) |pattern| {
            const is_glob = isGlobPattern(pattern);
            var files = std.ArrayList([]u8).init(self.allocator);

            if (is_glob) {
                var expanded = try temp_expander.expandSingleGlobOwned(pattern);
                defer expanded.deinit();

                // Copy paths to final allocator (not arena)
                for (expanded.items) |path| {
                    const owned_path = try self.allocator.dupe(u8, path);
                    try files.append(owned_path);
                }
            } else {
                // For non-glob patterns, check if file or directory exists
                const stat = self.filesystem.statFile(self.allocator, pattern) catch |err| switch (err) {
                    error.FileNotFound => {
                        // File doesn't exist, add empty result
                        try results.append(.{
                            .pattern = pattern,
                            .files = files,
                            .is_glob = false,
                        });
                        continue;
                    },
                    else => return err,
                };

                if (stat.kind == .file) {
                    const owned_path = try self.allocator.dupe(u8, pattern);
                    try files.append(owned_path);
                } else if (stat.kind == .directory) {
                    // Expand directory recursively
                    try self.expandDirectoryRecursively(&files, pattern);
                }
            }

            try results.append(.{
                .pattern = pattern,
                .files = files,
                .is_glob = is_glob,
            });
        }

        return results;
    }

    /// Expand a single glob pattern with ownership control
    /// If owned=true, returns owned strings; if false, returns borrowed strings
    fn expandSingleGlobGeneric(self: Self, pattern: []const u8, comptime owned: bool) !std.ArrayList(if (owned) []u8 else []const u8) {
        var results = std.ArrayList(if (owned) []u8 else []const u8).init(self.allocator);
        errdefer {
            if (owned) {
                for (results.items) |path| {
                    self.allocator.free(path);
                }
            }
            results.deinit();
        }

        // Handle brace expansion first
        if (std.mem.indexOf(u8, pattern, "{") != null) {
            var expanded_patterns = try self.expandBraces(pattern);
            defer {
                for (expanded_patterns.items) |p| {
                    self.allocator.free(p);
                }
                expanded_patterns.deinit();
            }

            for (expanded_patterns.items) |expanded_pattern| {
                var pattern_results = try self.expandSingleGlobGeneric(expanded_pattern, owned);
                defer pattern_results.deinit();

                if (owned) {
                    // Transfer ownership by moving paths from pattern_results to results
                    for (pattern_results.items) |path| {
                        try results.append(path);
                    }
                    // Clear the pattern_results list without freeing the strings (ownership transferred)
                    pattern_results.clearRetainingCapacity();
                } else {
                    for (pattern_results.items) |path| {
                        try results.append(path);
                    }
                }
            }
            return results;
        }

        // Handle recursive patterns (**)
        if (std.mem.indexOf(u8, pattern, "**") != null) {
            if (owned) {
                return self.expandRecursiveGlob(pattern);
            } else {
                return self.expandRecursiveGlobBorrowed(pattern);
            }
        }

        // Handle simple glob patterns
        if (isGlobPattern(pattern)) {
            if (owned) {
                return self.expandSimpleGlob(pattern);
            } else {
                return self.expandSimpleGlobBorrowed(pattern);
            }
        }

        // Not a glob pattern, return as-is if it exists
        const stat = self.filesystem.statFile(self.allocator, pattern) catch |err| switch (err) {
            error.FileNotFound => return results,
            else => return err,
        };

        if (stat.kind == .file) {
            if (owned) {
                const owned_path = try self.allocator.dupe(u8, pattern);
                try results.append(owned_path);
            } else {
                try results.append(pattern);
            }
        }

        return results;
    }

    /// Expand a single glob pattern, returning owned strings
    fn expandSingleGlobOwned(self: Self, pattern: []const u8) !std.ArrayList([]u8) {
        return self.expandSingleGlobGeneric(pattern, true);
    }

    /// Expand a single glob pattern (internal use - returns borrowed strings)
    fn expandSingleGlob(self: Self, pattern: []const u8) !std.ArrayList([]const u8) {
        return self.expandSingleGlobGeneric(pattern, false);
    }

    /// Expand brace patterns like {a,b,c}
    fn expandBraces(self: Self, pattern: []const u8) !std.ArrayList([]u8) {
        // Fast path: handle common patterns without parsing
        if (std.mem.eql(u8, pattern, "*.{zig,c,h}")) {
            var results = std.ArrayList([]u8).init(self.allocator);
            try results.append(try self.allocator.dupe(u8, "*.zig"));
            try results.append(try self.allocator.dupe(u8, "*.c"));
            try results.append(try self.allocator.dupe(u8, "*.h"));
            return results;
        }
        if (std.mem.eql(u8, pattern, "*.{js,ts}")) {
            var results = std.ArrayList([]u8).init(self.allocator);
            try results.append(try self.allocator.dupe(u8, "*.js"));
            try results.append(try self.allocator.dupe(u8, "*.ts"));
            return results;
        }
        if (std.mem.eql(u8, pattern, "*.{md,txt}")) {
            var results = std.ArrayList([]u8).init(self.allocator);
            try results.append(try self.allocator.dupe(u8, "*.md"));
            try results.append(try self.allocator.dupe(u8, "*.txt"));
            return results;
        }
        
        var results = std.ArrayList([]u8).init(self.allocator);
        errdefer {
            for (results.items) |item| {
                self.allocator.free(item);
            }
            results.deinit();
        }

        const start = std.mem.indexOf(u8, pattern, "{") orelse {
            const copy = try self.allocator.dupe(u8, pattern);
            try results.append(copy);
            return results;
        };

        // Find matching closing brace
        var depth: usize = 1;
        var end: usize = start + 1;
        while (end < pattern.len and depth > 0) : (end += 1) {
            if (pattern[end] == '{') {
                depth += 1;
            } else if (pattern[end] == '}') {
                depth -= 1;
            }
        }

        if (depth != 0) {
            // Unmatched braces, treat as literal
            const copy = try self.allocator.dupe(u8, pattern);
            try results.append(copy);
            return results;
        }

        const prefix = pattern[0..start];
        const suffix = pattern[end..];
        const content = pattern[start + 1 .. end - 1];

        // Split content by commas (but respect nested braces)
        var alternatives = std.ArrayList([]const u8).init(self.allocator);
        defer alternatives.deinit();

        var current_start: usize = 0;
        var i: usize = 0;
        var brace_depth: usize = 0;

        while (i < content.len) : (i += 1) {
            if (content[i] == '{') {
                brace_depth += 1;
            } else if (content[i] == '}') {
                brace_depth -= 1;
            } else if (content[i] == ',' and brace_depth == 0) {
                try alternatives.append(content[current_start..i]);
                current_start = i + 1;
            }
        }
        try alternatives.append(content[current_start..]);

        // Generate all combinations
        for (alternatives.items) |alt| {
            const expanded = try std.fmt.allocPrint(self.allocator, "{s}{s}{s}", .{ prefix, alt, suffix });
            errdefer self.allocator.free(expanded);

            // Recursively expand nested braces
            if (std.mem.indexOf(u8, expanded, "{") != null) {
                var nested_results = try self.expandBraces(expanded);
                self.allocator.free(expanded);

                for (nested_results.items) |nested| {
                    try results.append(nested);
                }
                nested_results.deinit();
            } else {
                try results.append(expanded);
            }
        }

        return results;
    }

    /// Expand simple glob patterns (*, ?, []) - returns owned strings
    fn expandSimpleGlob(self: Self, pattern: []const u8) !std.ArrayList([]u8) {
        var results = std.ArrayList([]u8).init(self.allocator);
        errdefer {
            for (results.items) |path| {
                self.allocator.free(path);
            }
            results.deinit();
        }

        // Split pattern into directory and filename parts
        const last_sep = std.mem.lastIndexOf(u8, pattern, "/");
        const dir_path = if (last_sep) |idx| pattern[0..idx] else ".";
        const file_pattern = if (last_sep) |idx| pattern[idx + 1 ..] else pattern;

        // Open directory
        const dir = self.filesystem.openDir(self.allocator, dir_path, .{ .iterate = true }) catch |err| switch (err) {
            error.FileNotFound, error.NotDir => return results,
            else => return err,
        };
        defer dir.close();

        // Iterate through directory entries
        var iter = try dir.iterate(self.allocator);
        while (try iter.next(self.allocator)) |entry| {
            // Unix-like behavior: patterns not starting with '.' don't match hidden files
            if (isHiddenFile(entry.name) and !patternMatchesHidden(file_pattern)) {
                continue; // Skip hidden files when pattern doesn't explicitly match them
            }

            if (self.matchPattern(entry.name, file_pattern)) {
                const full_path = if (last_sep != null)
                    try path_utils.joinPath(self.allocator, dir_path, entry.name)
                else
                    try self.allocator.dupe(u8, entry.name);

                try results.append(full_path);
            }
        }

        return results;
    }

    /// Expand simple glob patterns (*, ?, []) - returns borrowed strings (internal use)
    fn expandSimpleGlobBorrowed(self: Self, pattern: []const u8) !std.ArrayList([]const u8) {
        // Simply delegate to owned version and convert
        // This is temporary - will be removed once we fully migrate to the generic version
        var results = std.ArrayList([]const u8).init(self.allocator);
        errdefer results.deinit();

        var owned_results = try self.expandSimpleGlob(pattern);
        defer {
            for (owned_results.items) |path| {
                self.allocator.free(path);
            }
            owned_results.deinit();
        }

        for (owned_results.items) |path| {
            try results.append(path);
        }

        return results;
    }

    /// Expand recursive glob patterns (**) - returns owned strings
    fn expandRecursiveGlob(self: Self, pattern: []const u8) !std.ArrayList([]u8) {
        var results = std.ArrayList([]u8).init(self.allocator);
        errdefer {
            for (results.items) |path| {
                self.allocator.free(path);
            }
            results.deinit();
        }

        // Split pattern at **
        const star_star = std.mem.indexOf(u8, pattern, "**") orelse return results;

        const prefix = if (star_star > 0 and pattern[star_star - 1] == '/')
            pattern[0 .. star_star - 1]
        else if (star_star == 0)
            "."
        else
            pattern[0..star_star];

        const suffix = if (star_star + 2 < pattern.len and pattern[star_star + 2] == '/')
            pattern[star_star + 3 ..]
        else if (star_star + 2 == pattern.len)
            ""
        else
            pattern[star_star + 2 ..];

        // Recursively search directories
        try self.searchRecursive(&results, prefix, suffix, 0);

        return results;
    }

    /// Expand recursive glob patterns (**) - returns borrowed strings (internal use)
    fn expandRecursiveGlobBorrowed(self: Self, pattern: []const u8) !std.ArrayList([]const u8) {
        // Simply delegate to owned version and convert
        // This is temporary - will be removed once we fully migrate to the generic version
        var results = std.ArrayList([]const u8).init(self.allocator);
        errdefer results.deinit();

        var owned_results = try self.expandRecursiveGlob(pattern);
        defer {
            for (owned_results.items) |path| {
                self.allocator.free(path);
            }
            owned_results.deinit();
        }

        for (owned_results.items) |path| {
            try results.append(path);
        }

        return results;
    }

    /// Context for pattern-based file collection
    const PatternSearchContext = struct {
        results: *std.ArrayList([]u8),
        pattern: []const u8,
        glob_expander: *const Self,
    };

    /// Callback for collecting files that match a pattern
    fn patternFileCollector(allocator: std.mem.Allocator, file_path: []const u8, context_ptr: ?*anyopaque) !void {
        const context: *PatternSearchContext = @ptrCast(@alignCast(context_ptr.?));
        const filename = path_utils.basename(file_path);

        // If pattern is empty, match all files (except hidden ones)
        if (context.pattern.len == 0) {
            if (!isHiddenFile(filename)) {
                const owned = try allocator.dupe(u8, file_path);
                try context.results.append(owned);
            }
        } else {
            // Unix-like behavior: patterns not starting with '.' don't match hidden files
            if (isHiddenFile(filename) and !patternMatchesHidden(context.pattern)) {
                // Skip this hidden file
            } else if (context.glob_expander.matchPattern(filename, context.pattern)) {
                const owned = try allocator.dupe(u8, file_path);
                try context.results.append(owned);
            }
        }
    }

    /// Recursively search directories for matching files (using shared traversal)
    fn searchRecursive(self: Self, results: *std.ArrayList([]u8), dir_path: []const u8, pattern: []const u8, depth: usize) !void {
        // Use shared traversal utility with pattern matching
        const context = PatternSearchContext{
            .results = results,
            .pattern = pattern,
            .glob_expander = &self,
        };

        const traverser = traversal.DirectoryTraverser.init(
            self.allocator,
            self.filesystem,
            self.config,
            .{
                .max_depth = if (depth >= MAX_GLOB_DEPTH) 0 else @intCast(MAX_GLOB_DEPTH - depth),
                .include_hidden = false, // Let the callback handle hidden file logic
                .on_file = patternFileCollector,
                .context = @ptrCast(@constCast(&context)),
            },
        );

        try traverser.traverse(dir_path);
    }

    /// Context for directory expansion (all files)
    const DirectoryExpansionContext = struct {
        files: *std.ArrayList([]u8),
    };

    /// Callback for collecting all files in directory expansion
    fn directoryFileCollector(allocator: std.mem.Allocator, file_path: []const u8, context_ptr: ?*anyopaque) !void {
        const context: *DirectoryExpansionContext = @ptrCast(@alignCast(context_ptr.?));
        const owned = try allocator.dupe(u8, file_path);
        try context.files.append(owned);
    }

    /// Expand directory recursively, adding all files to the list (using shared traversal)
    fn expandDirectoryRecursively(self: Self, files: *std.ArrayList([]u8), dir_path: []const u8) !void {
        // Use shared traversal utility for all files
        const context = DirectoryExpansionContext{ .files = files };

        const traverser = traversal.DirectoryTraverser.init(
            self.allocator,
            self.filesystem,
            self.config,
            .{
                .max_depth = null, // No depth limit for directory expansion
                .include_hidden = false, // Respect configuration for hidden files
                .on_file = directoryFileCollector,
                .context = @ptrCast(@constCast(&context)),
            },
        );

        try traverser.traverse(dir_path);
    }

    /// Match a string against a glob pattern (handles brace expansion)
    pub fn matchPattern(self: Self, str: []const u8, pattern: []const u8) bool {
        // Handle brace expansion first
        if (std.mem.indexOf(u8, pattern, "{") != null) {
            var expanded_patterns = self.expandBraces(pattern) catch return false;
            defer {
                for (expanded_patterns.items) |p| {
                    self.allocator.free(p);
                }
                expanded_patterns.deinit();
            }

            for (expanded_patterns.items) |expanded_pattern| {
                if (glob_patterns.matchSimplePattern(str, expanded_pattern)) {
                    return true;
                }
            }
            return false;
        }

        // No braces, use simple pattern matching
        return glob_patterns.matchSimplePattern(str, pattern);
    }
};

/// Re-export the pattern matching function for backward compatibility
pub const matchSimplePattern = glob_patterns.matchSimplePattern;
