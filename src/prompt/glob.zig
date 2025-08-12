const std = @import("std");
const FilesystemInterface = @import("../filesystem.zig").FilesystemInterface;
const DirHandle = @import("../filesystem.zig").DirHandle;
const SharedConfig = @import("../config.zig").SharedConfig;
const shouldIgnorePath = @import("../config.zig").shouldIgnorePath;
const shouldHideFile = @import("../config.zig").shouldHideFile;

// Configuration constants
const MAX_GLOB_DEPTH = 20; // Maximum directory depth for ** patterns
const MAX_PATTERN_LENGTH = 4096; // Maximum pattern length to prevent DOS

/// Check if a filename represents a hidden file (starts with '.')
fn isHiddenFile(filename: []const u8) bool {
    return filename.len > 0 and filename[0] == '.';
}

/// Check if a glob pattern explicitly matches hidden files (starts with '.')
fn patternMatchesHidden(pattern: []const u8) bool {
    return pattern.len > 0 and pattern[0] == '.';
}

/// Join directory path and filename with '/' separator
fn joinPath(allocator: std.mem.Allocator, dir_path: []const u8, filename: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir_path, filename });
}

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

    /// Expand multiple glob patterns
    pub fn expandGlobs(self: Self, patterns: []const []const u8) !std.ArrayList([]u8) {
        var results = std.ArrayList([]u8).init(self.allocator);
        errdefer {
            for (results.items) |path| {
                self.allocator.free(path);
            }
            results.deinit();
        }

        for (patterns) |pattern| {
            var expanded = try self.expandSingleGlobOwned(pattern);
            defer expanded.deinit();

            // Transfer ownership by moving paths from expanded to results
            try transferPaths(expanded.items, &results);
            
            // Clear the expanded list without freeing the strings (ownership transferred)
            expanded.clearRetainingCapacity();
        }

        return results;
    }

    /// Expand patterns with detailed information about each pattern
    pub fn expandPatternsWithInfo(self: Self, patterns: []const []const u8) !std.ArrayList(PatternResult) {
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

        for (patterns) |pattern| {
            const is_glob = isGlobPattern(pattern);
            var files = std.ArrayList([]u8).init(self.allocator);
            
            if (is_glob) {
                var expanded = try self.expandSingleGlobOwned(pattern);
                defer expanded.deinit();

                // Transfer ownership by moving paths from expanded to files
                try transferPaths(expanded.items, &files);
                
                // Clear the expanded list without freeing the strings (ownership transferred)
                expanded.clearRetainingCapacity();
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

    /// Expand a single glob pattern, returning owned strings
    fn expandSingleGlobOwned(self: Self, pattern: []const u8) !std.ArrayList([]u8) {
        var results = std.ArrayList([]u8).init(self.allocator);
        errdefer {
            for (results.items) |path| {
                self.allocator.free(path);
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
                var pattern_results = try self.expandSingleGlobOwned(expanded_pattern);
                defer pattern_results.deinit();
                
                // Transfer ownership by moving paths from pattern_results to results
                try transferPaths(pattern_results.items, &results);
                
                // Clear the pattern_results list without freeing the strings (ownership transferred)
                pattern_results.clearRetainingCapacity();
            }
            return results;
        }

        // Handle recursive patterns (**)
        if (std.mem.indexOf(u8, pattern, "**") != null) {
            return self.expandRecursiveGlob(pattern);
        }

        // Handle simple glob patterns
        if (isGlobPattern(pattern)) {
            return self.expandSimpleGlob(pattern);
        }

        // Not a glob pattern, return as-is if it exists
        const stat = self.filesystem.statFile(self.allocator, pattern) catch |err| switch (err) {
            error.FileNotFound => return results,
            else => return err,
        };
        
        if (stat.kind == .file) {
            const owned_path = try self.allocator.dupe(u8, pattern);
            try results.append(owned_path);
        }
        
        return results;
    }

    /// Expand a single glob pattern (internal use - returns borrowed strings)
    fn expandSingleGlob(self: Self, pattern: []const u8) !std.ArrayList([]const u8) {
        var results = std.ArrayList([]const u8).init(self.allocator);
        errdefer results.deinit();

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
                var pattern_results = try self.expandSingleGlob(expanded_pattern);
                defer pattern_results.deinit();
                
                for (pattern_results.items) |path| {
                    try results.append(path);
                }
            }
            return results;
        }

        // Handle recursive patterns (**)
        if (std.mem.indexOf(u8, pattern, "**") != null) {
            return self.expandRecursiveGlobBorrowed(pattern);
        }

        // Handle simple glob patterns
        if (isGlobPattern(pattern)) {
            return self.expandSimpleGlobBorrowed(pattern);
        }

        // Not a glob pattern, return as-is if it exists
        const stat = self.filesystem.statFile(self.allocator, pattern) catch |err| switch (err) {
            error.FileNotFound => return results,
            else => return err,
        };
        
        if (stat.kind == .file) {
            try results.append(pattern);
        }
        
        return results;
    }

    /// Expand brace patterns like {a,b,c}
    fn expandBraces(self: Self, pattern: []const u8) !std.ArrayList([]u8) {
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
                    try joinPath(self.allocator, dir_path, entry.name)
                else
                    try self.allocator.dupe(u8, entry.name);
                
                try results.append(full_path);
            }
        }

        return results;
    }

    /// Expand simple glob patterns (*, ?, []) - returns borrowed strings (internal use)
    fn expandSimpleGlobBorrowed(self: Self, pattern: []const u8) !std.ArrayList([]const u8) {
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

    /// Recursively search directories for matching files
    fn searchRecursive(self: Self, results: *std.ArrayList([]u8), dir_path: []const u8, pattern: []const u8, depth: usize) !void {
        if (depth > MAX_GLOB_DEPTH) return;

        const dir = self.filesystem.openDir(self.allocator, dir_path, .{ .iterate = true }) catch |err| switch (err) {
            error.FileNotFound, error.NotDir => return,
            else => return err,
        };
        defer dir.close();

        var iter = try dir.iterate(self.allocator);
        while (try iter.next(self.allocator)) |entry| {
            const full_path = try joinPath(self.allocator, dir_path, entry.name);
            defer self.allocator.free(full_path);

            // If pattern is empty, match all files (except hidden ones)
            if (pattern.len == 0) {
                if (entry.kind == .file and !isHiddenFile(entry.name)) {
                    const owned = try self.allocator.dupe(u8, full_path);
                    try results.append(owned);
                }
            } else if (entry.kind == .file) {
                // Unix-like behavior: patterns not starting with '.' don't match hidden files
                if (isHiddenFile(entry.name) and !patternMatchesHidden(pattern)) {
                    // Skip this hidden file
                } else if (self.matchPattern(entry.name, pattern)) {
                    const owned = try self.allocator.dupe(u8, full_path);
                    try results.append(owned);
                }
            }

            // Recurse into directories (but skip ignored ones)
            if (entry.kind == .directory) {
                // Skip ignored directories (like hidden dirs starting with '.')
                if (!shouldIgnorePath(self.config, full_path)) {
                    try self.searchRecursive(results, full_path, pattern, depth + 1);
                }
            }
        }
    }

    /// Expand directory recursively, adding all files to the list
    fn expandDirectoryRecursively(self: Self, files: *std.ArrayList([]u8), dir_path: []const u8) !void {
        // Skip directories that match ignore patterns
        if (shouldIgnorePath(self.config, dir_path)) {
            return;
        }

        const dir = self.filesystem.openDir(self.allocator, dir_path, .{ .iterate = true }) catch |err| switch (err) {
            error.FileNotFound, error.NotDir, error.AccessDenied => return,
            else => return err,
        };
        defer dir.close();

        var iter = try dir.iterate(self.allocator);
        while (try iter.next(self.allocator)) |entry| {
            const full_path = try joinPath(self.allocator, dir_path, entry.name);
            
            if (entry.kind == .file) {
                // Skip hidden files if configured
                if (shouldHideFile(self.config, entry.name)) {
                    self.allocator.free(full_path);
                    continue;
                }
                try files.append(full_path);
            } else if (entry.kind == .directory) {
                // Skip ignored directories - check full path for ignore patterns
                if (!shouldIgnorePath(self.config, full_path)) {
                    // Recursively expand subdirectories
                    try self.expandDirectoryRecursively(files, full_path);
                }
                self.allocator.free(full_path);
            } else {
                // Not a file or directory, free the path
                self.allocator.free(full_path);
            }
        }
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
                if (matchSimplePattern(str, expanded_pattern)) {
                    return true;
                }
            }
            return false;
        }
        
        // No braces, use simple pattern matching
        return matchSimplePattern(str, pattern);
    }
};

/// Match a string against a simple glob pattern (*, ?, [], {})
pub fn matchSimplePattern(str: []const u8, pattern: []const u8) bool {
    var s_idx: usize = 0;
    var p_idx: usize = 0;
    var star_idx: ?usize = null;
    var star_match: ?usize = null;

    while (s_idx < str.len) {
        if (p_idx < pattern.len) {
            if (pattern[p_idx] == '\\' and p_idx + 1 < pattern.len) {
                // Escape sequence - match next character literally
                if (str[s_idx] == pattern[p_idx + 1]) {
                    s_idx += 1;
                    p_idx += 2;
                    continue;
                }
            } else if (pattern[p_idx] == '*') {
                // Wildcard - save position for backtracking
                star_idx = p_idx;
                star_match = s_idx;
                p_idx += 1;
                continue;
            } else if (pattern[p_idx] == '?') {
                // Single character wildcard
                s_idx += 1;
                p_idx += 1;
                continue;
            } else if (pattern[p_idx] == '[') {
                // Character class
                const close = std.mem.indexOf(u8, pattern[p_idx + 1 ..], "]");
                if (close) |end| {
                    const class_content = pattern[p_idx + 1 .. p_idx + 1 + end];
                    if (matchCharacterClass(str[s_idx], class_content)) {
                        s_idx += 1;
                        p_idx += end + 2;
                        continue;
                    }
                } else {
                    // No closing bracket, treat as literal
                    if (str[s_idx] == pattern[p_idx]) {
                        s_idx += 1;
                        p_idx += 1;
                        continue;
                    }
                }
            } else if (str[s_idx] == pattern[p_idx]) {
                // Exact match
                s_idx += 1;
                p_idx += 1;
                continue;
            }
        }

        // No match, try backtracking to last wildcard
        if (star_idx) |star| {
            p_idx = star + 1;
            star_match = star_match.? + 1;
            s_idx = star_match.?;
        } else {
            return false;
        }
    }

    // Handle remaining pattern characters
    while (p_idx < pattern.len and pattern[p_idx] == '*') {
        p_idx += 1;
    }

    return p_idx == pattern.len;
}

/// Match a character against a character class pattern
fn matchCharacterClass(char: u8, class_content: []const u8) bool {
    if (class_content.len == 0) return false;

    var negate = false;
    var i: usize = 0;

    // Check for negation
    if (class_content[0] == '!' or class_content[0] == '^') {
        negate = true;
        i = 1;
    }

    var matched = false;
    
    while (i < class_content.len) {
        if (i + 2 < class_content.len and class_content[i + 1] == '-') {
            // Range
            if (char >= class_content[i] and char <= class_content[i + 2]) {
                matched = true;
                break;
            }
            i += 3;
        } else {
            // Single character
            if (char == class_content[i]) {
                matched = true;
                break;
            }
            i += 1;
        }
    }

    return if (negate) !matched else matched;
}