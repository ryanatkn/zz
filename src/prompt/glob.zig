const std = @import("std");

pub const PatternResult = struct {
    pattern: []const u8,
    files: std.ArrayList([]u8),
    is_glob: bool,
};

pub const GlobExpander = struct {
    allocator: std.mem.Allocator,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }
    
    pub fn isGlobPattern(pattern: []const u8) bool {
        return std.mem.indexOf(u8, pattern, "*") != null or
               std.mem.indexOf(u8, pattern, "?") != null or
               std.mem.indexOf(u8, pattern, "{") != null;
    }
    
    pub fn expandPatternsWithInfo(self: Self, patterns: []const []const u8) !std.ArrayList(PatternResult) {
        var results = std.ArrayList(PatternResult).init(self.allocator);
        errdefer results.deinit();
        
        for (patterns) |pattern| {
            var pattern_result = PatternResult{
                .pattern = pattern,
                .files = std.ArrayList([]u8).init(self.allocator),
                .is_glob = isGlobPattern(pattern),
            };
            errdefer {
                for (pattern_result.files.items) |file| {
                    self.allocator.free(file);
                }
                pattern_result.files.deinit();
            }
            
            try self.expandGlob(pattern, &pattern_result.files);
            try results.append(pattern_result);
        }
        
        return results;
    }
    
    pub fn expandGlobs(self: Self, patterns: []const []const u8) !std.ArrayList([]u8) {
        var results = std.ArrayList([]u8).init(self.allocator);
        errdefer {
            for (results.items) |item| {
                self.allocator.free(item);
            }
            results.deinit();
        }
        
        for (patterns) |pattern| {
            try self.expandGlob(pattern, &results);
        }
        
        return results;
    }
    
    pub fn expandGlob(self: Self, pattern: []const u8, results: *std.ArrayList([]u8)) !void {
        // Handle recursive patterns like src/**/*.zig
        if (std.mem.indexOf(u8, pattern, "**")) |idx| {
            const prefix = pattern[0..idx];
            const suffix = if (idx + 2 < pattern.len and pattern[idx + 2] == '/') 
                pattern[idx + 3..] 
            else 
                pattern[idx + 2..];
            
            try self.expandRecursive(prefix, suffix, results);
            return;
        }
        
        // Handle simple wildcard patterns
        if (std.mem.indexOf(u8, pattern, "*") != null or
            std.mem.indexOf(u8, pattern, "?") != null or
            std.mem.indexOf(u8, pattern, "{") != null) {
            try self.expandWildcard(pattern, results);
            return;
        }
        
        // No glob patterns, treat as literal file path
        // Check if file exists
        std.fs.cwd().access(pattern, .{}) catch {
            // File doesn't exist, don't add to results
            // The main loop will detect this as a missing pattern
            return;
        };
        const path_copy = try self.allocator.dupe(u8, pattern);
        try results.append(path_copy);
    }
    
    fn expandRecursive(self: Self, prefix: []const u8, pattern: []const u8, results: *std.ArrayList([]u8)) !void {
        const search_dir = if (prefix.len == 0) "." else prefix;
        
        var dir = std.fs.cwd().openDir(search_dir, .{ .iterate = true }) catch |err| {
            // Directory doesn't exist, skip silently
            if (err == error.FileNotFound) return;
            return err;
        };
        defer dir.close();
        
        try self.walkDir(&dir, search_dir, pattern, results);
    }
    
    fn walkDir(self: Self, dir: *std.fs.Dir, base_path: []const u8, pattern: []const u8, results: *std.ArrayList([]u8)) !void {
        var iterator = dir.iterate();
        
        while (try iterator.next()) |entry| {
            const full_path = try std.fs.path.join(self.allocator, &.{ base_path, entry.name });
            defer self.allocator.free(full_path);
            
            switch (entry.kind) {
                .file, .sym_link => {
                    // Skip hidden files unless pattern explicitly starts with .
                    if (entry.name[0] == '.' and pattern[0] != '.') continue;
                    
                    if (self.matchPattern(entry.name, pattern)) {
                        const path_copy = try self.allocator.dupe(u8, full_path);
                        try results.append(path_copy);
                    }
                },
                .directory => {
                    // Skip hidden directories
                    if (entry.name[0] == '.') continue;
                    
                    var sub_dir = try dir.openDir(entry.name, .{ .iterate = true });
                    defer sub_dir.close();
                    
                    try self.walkDir(&sub_dir, full_path, pattern, results);
                },
                else => {},
            }
        }
    }
    
    fn expandWildcard(self: Self, pattern: []const u8, results: *std.ArrayList([]u8)) !void {
        // Extract directory and file pattern
        const last_sep = std.mem.lastIndexOf(u8, pattern, "/");
        const dir_path = if (last_sep) |idx| pattern[0..idx] else ".";
        const file_pattern = if (last_sep) |idx| pattern[idx + 1..] else pattern;
        
        var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch |err| {
            if (err == error.FileNotFound) return;
            return err;
        };
        defer dir.close();
        
        var iterator = dir.iterate();
        while (try iterator.next()) |entry| {
            // Accept both regular files and symlinks to files
            if (entry.kind != .file and entry.kind != .sym_link) continue;
            
            // Skip hidden files unless pattern explicitly starts with .
            if (entry.name[0] == '.' and file_pattern[0] != '.') continue;
            
            if (self.matchPattern(entry.name, file_pattern)) {
                const full_path = if (std.mem.eql(u8, dir_path, "."))
                    try self.allocator.dupe(u8, entry.name)
                else
                    try std.fs.path.join(self.allocator, &.{ dir_path, entry.name });
                    
                try results.append(full_path);
            }
        }
    }
    
    pub fn matchPattern(_: Self, name: []const u8, pattern: []const u8) bool {
        // Handle {a,b,c} alternatives
        if (std.mem.indexOf(u8, pattern, "{")) |start| {
            if (std.mem.indexOf(u8, pattern[start..], "}")) |end_offset| {
                const end = start + end_offset;
                const prefix = pattern[0..start];
                const suffix = pattern[end + 1..];
                const alternatives = pattern[start + 1..end];
                
                var iter = std.mem.tokenizeScalar(u8, alternatives, ',');
                while (iter.next()) |alt| {
                    var test_pattern_buf: [std.fs.max_path_bytes]u8 = undefined;
                    const test_pattern = std.fmt.bufPrint(&test_pattern_buf, "{s}{s}{s}", .{prefix, alt, suffix}) catch continue;
                    // Recursively handle remaining patterns (in case of nested braces)
                    if (Self.matchPattern(.{.allocator = undefined}, name, test_pattern)) return true;
                }
                return false;
            }
        }
        
        return matchSimplePattern(name, pattern);
    }
};

pub fn matchSimplePattern(text: []const u8, pattern: []const u8) bool {
    var t_idx: usize = 0;
    var p_idx: usize = 0;
    var star_idx: ?usize = null;
    var star_match: usize = 0;
    
    while (t_idx < text.len) {
        if (p_idx < pattern.len and (pattern[p_idx] == '?' or pattern[p_idx] == text[t_idx])) {
            t_idx += 1;
            p_idx += 1;
        } else if (p_idx < pattern.len and pattern[p_idx] == '*') {
            star_idx = p_idx;
            star_match = t_idx;
            p_idx += 1;
        } else if (star_idx != null) {
            p_idx = star_idx.? + 1;
            star_match += 1;
            t_idx = star_match;
        } else {
            return false;
        }
    }
    
    while (p_idx < pattern.len and pattern[p_idx] == '*') {
        p_idx += 1;
    }
    
    return p_idx == pattern.len;
}

test "glob pattern matching" {
    try std.testing.expect(matchSimplePattern("test.zig", "*.zig"));
    try std.testing.expect(matchSimplePattern("main.zig", "*.zig"));
    try std.testing.expect(!matchSimplePattern("test.txt", "*.zig"));
    
    try std.testing.expect(matchSimplePattern("test.zig", "test.*"));
    try std.testing.expect(matchSimplePattern("a.txt", "?.txt"));
    try std.testing.expect(!matchSimplePattern("ab.txt", "?.txt"));
}

test "glob alternatives" {
    const expander = GlobExpander.init(std.testing.allocator);
    
    try std.testing.expect(expander.matchPattern("test.zig", "*.{zig,txt}"));
    try std.testing.expect(expander.matchPattern("test.txt", "*.{zig,txt}"));
    try std.testing.expect(!expander.matchPattern("test.md", "*.{zig,txt}"));
}