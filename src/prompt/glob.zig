const std = @import("std");

// Configuration constants
const MAX_BRACE_ALTERNATIVES = 32; // Maximum number of alternatives in brace expansion

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
            std.mem.indexOf(u8, pattern, "{") != null or
            std.mem.indexOf(u8, pattern, "[") != null;
        // Note: We don't include "\\" here because escaped patterns are still globs
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
                pattern[idx + 3 ..]
            else
                pattern[idx + 2 ..];

            try self.expandRecursive(prefix, suffix, results);
            return;
        }

        // Handle simple wildcard patterns (including character classes and escapes)
        if (std.mem.indexOf(u8, pattern, "*") != null or
            std.mem.indexOf(u8, pattern, "?") != null or
            std.mem.indexOf(u8, pattern, "{") != null or
            std.mem.indexOf(u8, pattern, "[") != null or
            std.mem.indexOf(u8, pattern, "\\") != null)
        {
            try self.expandWildcard(pattern, results);
            return;
        }

        // No glob patterns, treat as literal file or directory path
        // Check if path exists and what type it is
        const stat = std.fs.cwd().statFile(pattern) catch {
            // Path doesn't exist, don't add to results
            // The main loop will detect this as a missing pattern
            return;
        };

        switch (stat.kind) {
            .file, .sym_link => {
                // It's a file, add it directly
                const path_copy = try self.allocator.dupe(u8, pattern);
                try results.append(path_copy);
            },
            .directory => {
                // It's a directory, traverse it recursively
                try self.expandDirectory(pattern, results);
            },
            else => {
                // Other types (block device, etc.) - skip
                return;
            },
        }
    }

    fn expandDirectory(self: Self, dir_path: []const u8, results: *std.ArrayList([]u8)) !void {
        var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch |err| {
            if (err == error.FileNotFound) return;
            return err;
        };
        defer dir.close();

        try self.walkDirForFiles(&dir, dir_path, results);
    }

    fn walkDirForFiles(self: Self, dir: *std.fs.Dir, base_path: []const u8, results: *std.ArrayList([]u8)) !void {
        var iterator = dir.iterate();

        while (try iterator.next()) |entry| {
            const full_path = try std.fs.path.join(self.allocator, &.{ base_path, entry.name });
            defer self.allocator.free(full_path);

            switch (entry.kind) {
                .file, .sym_link => {
                    if (self.shouldIncludeFile(entry.name)) {
                        const path_copy = try self.allocator.dupe(u8, full_path);
                        try results.append(path_copy);
                    }
                },
                .directory => {
                    if (self.shouldTraverseDirectory(entry.name)) {
                        var sub_dir = try dir.openDir(entry.name, .{ .iterate = true });
                        defer sub_dir.close();
                        try self.walkDirForFiles(&sub_dir, full_path, results);
                    }
                },
                else => {},
            }
        }
    }

    fn shouldIncludeFile(self: Self, name: []const u8) bool {
        _ = self;
        // Skip hidden files unless explicitly requested
        if (shouldSkipHiddenFile(name, "")) return false;
        // Basic filtering - detailed ignore logic is handled in main.zig
        // This prevents obvious files from being included in directory traversal
        return true;
    }

    fn shouldTraverseDirectory(self: Self, name: []const u8) bool {
        _ = self;
        // Skip hidden directories
        if (name.len > 0 and name[0] == '.') return false;
        
        // Skip common ignore patterns using DRY approach
        const common_ignored = [_][]const u8{
            "node_modules", "target", "build", "zig-out", ".zig-cache"
        };
        
        for (common_ignored) |ignored| {
            if (std.mem.eql(u8, name, ignored)) return false;
        }
        
        return true;
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
                    if (shouldSkipHiddenFile(entry.name, pattern)) continue;

                    if (self.matchPattern(entry.name, pattern)) {
                        const path_copy = try self.allocator.dupe(u8, full_path);
                        try results.append(path_copy);
                    }
                },
                .directory => {
                    // Skip hidden directories
                    if (entry.name.len > 0 and entry.name[0] == '.') continue;

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
        const file_pattern = if (last_sep) |idx| pattern[idx + 1 ..] else pattern;

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
            if (shouldSkipHiddenFile(entry.name, file_pattern)) continue;

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
        return matchPatternStatic(name, pattern);
    }

    fn matchPatternStatic(name: []const u8, pattern: []const u8) bool {
        // Handle {a,b,c} alternatives with proper brace depth tracking
        if (std.mem.indexOf(u8, pattern, "{")) |start| {
            if (findMatchingBrace(pattern[start..])) |end_offset| {
                const end = start + end_offset;
                const prefix = pattern[0..start];
                const suffix = pattern[end + 1 ..];
                const alternatives_str = pattern[start + 1 .. end];

                // Split alternatives with brace depth awareness
                var alternatives_buf: [MAX_BRACE_ALTERNATIVES][]const u8 = undefined;
                const alternatives = splitBraceAlternatives(alternatives_str, &alternatives_buf) catch {
                    // If splitting fails, treat as literal
                    return matchSimplePattern(name, pattern);
                };

                for (alternatives) |alt| {
                    var test_pattern_buf: [std.fs.max_path_bytes]u8 = undefined;
                    const test_pattern = std.fmt.bufPrint(&test_pattern_buf, "{s}{s}{s}", .{ prefix, alt, suffix }) catch continue;
                    // Recursively handle remaining patterns (in case of nested braces)
                    if (matchPatternStatic(name, test_pattern)) return true;
                }
                return false;
            }
        }

        return matchSimplePattern(name, pattern);
    }

    fn findMatchingBrace(text: []const u8) ?usize {
        if (text.len == 0 or text[0] != '{') return null;

        var depth: usize = 0;
        for (text, 0..) |char, i| {
            switch (char) {
                '{' => depth += 1,
                '}' => {
                    depth -= 1;
                    if (depth == 0) return i;
                },
                else => {},
            }
        }
        return null; // Unmatched brace
    }

    fn splitBraceAlternatives(alternatives: []const u8, buffer: [][]const u8) ![][]const u8 {
        var count: usize = 0;
        var depth: usize = 0;
        var start: usize = 0;

        for (alternatives, 0..) |char, i| {
            switch (char) {
                '{' => depth += 1,
                '}' => depth -= 1,
                ',' => {
                    if (depth == 0) {
                        if (count >= buffer.len) {
                            // Too many alternatives (max 32)
                            return error.TooManyBraceAlternatives;
                        }
                        buffer[count] = alternatives[start..i];
                        count += 1;
                        start = i + 1;
                    }
                },
                else => {},
            }
        }

        // Add final alternative
        if (start <= alternatives.len) {
            if (count >= buffer.len) {
                // Too many alternatives (max 32)
                return error.TooManyBraceAlternatives;
            }
            buffer[count] = alternatives[start..];
            count += 1;
        }

        return buffer[0..count];
    }
};

fn shouldSkipHiddenFile(filename: []const u8, pattern: []const u8) bool {
    // Skip hidden files unless pattern explicitly starts with .
    return filename.len > 0 and filename[0] == '.' and (pattern.len == 0 or pattern[0] != '.');
}

pub fn matchSimplePattern(text: []const u8, pattern: []const u8) bool {
    var t_idx: usize = 0;
    var p_idx: usize = 0;
    var star_idx: ?usize = null;
    var star_match: usize = 0;

    while (t_idx < text.len) {
        // Handle escape sequences
        if (p_idx < pattern.len and pattern[p_idx] == '\\') {
            // Next character is literal
            if (p_idx + 1 < pattern.len) {
                if (pattern[p_idx + 1] == text[t_idx]) {
                    t_idx += 1;
                    p_idx += 2; // Skip backslash and the escaped char
                } else if (star_idx != null) {
                    p_idx = star_idx.? + 1;
                    star_match += 1;
                    t_idx = star_match;
                } else {
                    return false;
                }
            } else {
                // Backslash at end of pattern - treat as literal
                if ('\\' == text[t_idx]) {
                    t_idx += 1;
                    p_idx += 1;
                } else if (star_idx != null) {
                    p_idx = star_idx.? + 1;
                    star_match += 1;
                    t_idx = star_match;
                } else {
                    return false;
                }
            }
        } else if (p_idx < pattern.len and pattern[p_idx] == '[') {
            // Character class matching
            const class_end = std.mem.indexOfScalarPos(u8, pattern, p_idx + 1, ']');
            if (class_end) |end| {
                const class_content = pattern[p_idx + 1 .. end];
                if (matchCharacterClass(text[t_idx], class_content)) {
                    t_idx += 1;
                    p_idx = end + 1;
                } else if (star_idx != null) {
                    p_idx = star_idx.? + 1;
                    star_match += 1;
                    t_idx = star_match;
                } else {
                    return false;
                }
            } else {
                // Treat [ as literal if no closing ]
                if (pattern[p_idx] == text[t_idx]) {
                    t_idx += 1;
                    p_idx += 1;
                } else if (star_idx != null) {
                    p_idx = star_idx.? + 1;
                    star_match += 1;
                    t_idx = star_match;
                } else {
                    return false;
                }
            }
        } else if (p_idx < pattern.len and (pattern[p_idx] == '?' or pattern[p_idx] == text[t_idx])) {
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

fn matchCharacterClass(char: u8, class: []const u8) bool {
    if (class.len == 0) return false;

    var i: usize = 0;
    var negate = false;

    // Check for negation
    if (class[0] == '!' or class[0] == '^') {
        negate = true;
        i = 1;
    }

    var matched = false;
    while (i < class.len) {
        if (i + 2 < class.len and class[i + 1] == '-') {
            // Range: [a-z]
            if (char >= class[i] and char <= class[i + 2]) {
                matched = true;
                break;
            }
            i += 3;
        } else {
            // Single character
            if (char == class[i]) {
                matched = true;
                break;
            }
            i += 1;
        }
    }

    return if (negate) !matched else matched;
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

    // Test nested braces
    try std.testing.expect(expander.matchPattern("test.zig", "*.{zig,{md,txt}}"));
    try std.testing.expect(expander.matchPattern("test.md", "*.{zig,{md,txt}}"));
    try std.testing.expect(expander.matchPattern("test.txt", "*.{zig,{md,txt}}"));
    try std.testing.expect(!expander.matchPattern("test.rs", "*.{zig,{md,txt}}"));
}

test "character classes" {
    // Single characters
    try std.testing.expect(matchSimplePattern("a", "[abc]"));
    try std.testing.expect(matchSimplePattern("b", "[abc]"));
    try std.testing.expect(matchSimplePattern("c", "[abc]"));
    try std.testing.expect(!matchSimplePattern("d", "[abc]"));

    // Ranges
    try std.testing.expect(matchSimplePattern("a", "[a-z]"));
    try std.testing.expect(matchSimplePattern("m", "[a-z]"));
    try std.testing.expect(matchSimplePattern("z", "[a-z]"));
    try std.testing.expect(!matchSimplePattern("A", "[a-z]"));
    try std.testing.expect(!matchSimplePattern("0", "[a-z]"));

    // Multiple ranges
    try std.testing.expect(matchSimplePattern("a", "[a-zA-Z]"));
    try std.testing.expect(matchSimplePattern("Z", "[a-zA-Z]"));
    try std.testing.expect(matchSimplePattern("m", "[a-zA-Z]"));
    try std.testing.expect(!matchSimplePattern("0", "[a-zA-Z]"));

    // Negation with !
    try std.testing.expect(!matchSimplePattern("a", "[!abc]"));
    try std.testing.expect(matchSimplePattern("d", "[!abc]"));
    try std.testing.expect(matchSimplePattern("z", "[!abc]"));

    // Negation with ^
    try std.testing.expect(!matchSimplePattern("a", "[^abc]"));
    try std.testing.expect(matchSimplePattern("d", "[^abc]"));

    // In patterns
    try std.testing.expect(matchSimplePattern("log1.txt", "log[0-9].txt"));
    try std.testing.expect(matchSimplePattern("log5.txt", "log[0-9].txt"));
    try std.testing.expect(!matchSimplePattern("loga.txt", "log[0-9].txt"));
    try std.testing.expect(!matchSimplePattern("log10.txt", "log[0-9].txt"));

    // Combined with wildcards
    try std.testing.expect(matchSimplePattern("test1.zig", "test[0-9]*.zig"));
    try std.testing.expect(matchSimplePattern("test123.zig", "test[0-9]*.zig"));
    try std.testing.expect(!matchSimplePattern("testa.zig", "test[0-9]*.zig"));
}

test "escape sequences" {
    // Escape special characters
    try std.testing.expect(matchSimplePattern("*.txt", "\\*.txt"));
    try std.testing.expect(!matchSimplePattern("a.txt", "\\*.txt"));

    try std.testing.expect(matchSimplePattern("?.txt", "\\?.txt"));
    try std.testing.expect(!matchSimplePattern("a.txt", "\\?.txt"));

    try std.testing.expect(matchSimplePattern("[abc].txt", "\\[abc\\].txt"));
    try std.testing.expect(!matchSimplePattern("a.txt", "\\[abc\\].txt"));

    // Escape backslash itself
    try std.testing.expect(matchSimplePattern("\\test", "\\\\test"));
    try std.testing.expect(matchSimplePattern("file\\name", "file\\\\name"));

    // Mixed escapes and wildcards
    try std.testing.expect(matchSimplePattern("file*.txt", "file\\*.txt"));
    try std.testing.expect(matchSimplePattern("test[1].log", "test\\[1\\].log"));
    try std.testing.expect(matchSimplePattern("a*b", "a\\*b"));

    // Wildcards still work when not escaped
    try std.testing.expect(matchSimplePattern("file123.txt", "file*.txt"));
    try std.testing.expect(matchSimplePattern("file*.txt", "file*.txt")); // Pattern matches itself
}

test "glob pattern expansion" {
    const allocator = std.testing.allocator;
    var expander = GlobExpander.init(allocator);

    // Test simple wildcard matching
    try std.testing.expect(expander.matchPattern("test.zig", "*.zig"));
    try std.testing.expect(expander.matchPattern("main.zig", "*.zig"));
    try std.testing.expect(!expander.matchPattern("test.txt", "*.zig"));

    // Test alternatives
    try std.testing.expect(expander.matchPattern("test.zig", "*.{zig,txt}"));
    try std.testing.expect(expander.matchPattern("test.txt", "*.{zig,txt}"));
    try std.testing.expect(!expander.matchPattern("test.md", "*.{zig,txt}"));

    // Test question mark
    try std.testing.expect(expander.matchPattern("a.txt", "?.txt"));
    try std.testing.expect(!expander.matchPattern("ab.txt", "?.txt"));
}

test "glob pattern detection" {
    // Test glob patterns
    try std.testing.expect(GlobExpander.isGlobPattern("*.zig") == true);
    try std.testing.expect(GlobExpander.isGlobPattern("src/**/*.zig") == true);
    try std.testing.expect(GlobExpander.isGlobPattern("test?.zig") == true);
    try std.testing.expect(GlobExpander.isGlobPattern("*.{zig,txt}") == true);

    // Test non-glob patterns
    try std.testing.expect(GlobExpander.isGlobPattern("file.zig") == false);
    try std.testing.expect(GlobExpander.isGlobPattern("src/main.zig") == false);
    try std.testing.expect(GlobExpander.isGlobPattern("/absolute/path.txt") == false);
}

test "error on non-matching glob patterns" {
    const allocator = std.testing.allocator;
    var expander = GlobExpander.init(allocator);

    // Test that glob pattern with no matches returns empty
    var patterns = [_][]const u8{"*.nonexistent_extension_xyz"};
    var results = try expander.expandPatternsWithInfo(&patterns);
    defer {
        for (results.items) |*result| {
            for (result.files.items) |path| {
                allocator.free(path);
            }
            result.files.deinit();
        }
        results.deinit();
    }

    try std.testing.expect(results.items.len == 1);
    try std.testing.expect(results.items[0].files.items.len == 0);
    try std.testing.expect(results.items[0].is_glob == true);
}

test "error on explicit missing files" {
    const allocator = std.testing.allocator;
    var expander = GlobExpander.init(allocator);

    // Test that explicit file path with no file returns empty
    var patterns = [_][]const u8{"/nonexistent/path/to/file.zig"};
    var results = try expander.expandPatternsWithInfo(&patterns);
    defer {
        for (results.items) |*result| {
            for (result.files.items) |path| {
                allocator.free(path);
            }
            result.files.deinit();
        }
        results.deinit();
    }

    try std.testing.expect(results.items.len == 1);
    try std.testing.expect(results.items[0].files.items.len == 0);
    try std.testing.expect(results.items[0].is_glob == false);
}
