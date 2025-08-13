const std = @import("std");

/// String operations helper module to consolidate common string patterns
/// Provides Zig-idiomatic, POSIX-aware string utilities for high-performance operations
pub const StringHelpers = struct {

    // ============================================================================
    // Core String Splitting and Tokenization
    // ============================================================================

    /// Result of string tokenization operations
    pub const TokenizeResult = struct {
        tokens: std.ArrayList([]const u8),
        
        pub fn deinit(self: *TokenizeResult) void {
            self.tokens.deinit();
        }
        
        pub fn items(self: *const TokenizeResult) []const []const u8 {
            return self.tokens.items;
        }
    };

    /// Split string by delimiter and collect into ArrayList with error handling
    pub fn splitToList(allocator: std.mem.Allocator, str: []const u8, delimiter: []const u8) !TokenizeResult {
        var result = TokenizeResult{ .tokens = std.ArrayList([]const u8).init(allocator) };
        errdefer result.deinit();
        
        var iter = std.mem.splitSequence(u8, str, delimiter);
        while (iter.next()) |token| {
            try result.tokens.append(token);
        }
        
        return result;
    }

    /// Tokenize string by delimiter (skip empty tokens) and collect into ArrayList
    pub fn tokenizeToList(allocator: std.mem.Allocator, str: []const u8, delimiter: []const u8) !TokenizeResult {
        var result = TokenizeResult{ .tokens = std.ArrayList([]const u8).init(allocator) };
        errdefer result.deinit();
        
        var iter = std.mem.tokenizeSequence(u8, str, delimiter);
        while (iter.next()) |token| {
            try result.tokens.append(token);
        }
        
        return result;
    }

    /// Split string by scalar delimiter (more efficient for single character)
    pub fn splitScalarToList(allocator: std.mem.Allocator, str: []const u8, delimiter: u8) !TokenizeResult {
        var result = TokenizeResult{ .tokens = std.ArrayList([]const u8).init(allocator) };
        errdefer result.deinit();
        
        var iter = std.mem.splitScalar(u8, str, delimiter);
        while (iter.next()) |token| {
            try result.tokens.append(token);
        }
        
        return result;
    }

    /// Tokenize by scalar delimiter (skip empty)
    pub fn tokenizeScalarToList(allocator: std.mem.Allocator, str: []const u8, delimiter: u8) !TokenizeResult {
        var result = TokenizeResult{ .tokens = std.ArrayList([]const u8).init(allocator) };
        errdefer result.deinit();
        
        var iter = std.mem.tokenizeScalar(u8, str, delimiter);
        while (iter.next()) |token| {
            try result.tokens.append(token);
        }
        
        return result;
    }

    // ============================================================================
    // String Search and Index Operations
    // ============================================================================

    /// Find first occurrence of needle in haystack, return null if not found
    pub fn findFirst(haystack: []const u8, needle: []const u8) ?usize {
        return std.mem.indexOf(u8, haystack, needle);
    }

    /// Find last occurrence of needle in haystack, return null if not found
    pub fn findLast(haystack: []const u8, needle: []const u8) ?usize {
        return std.mem.lastIndexOf(u8, haystack, needle);
    }

    /// Find first occurrence of any character from set
    pub fn findFirstOfAny(haystack: []const u8, char_set: []const u8) ?usize {
        return std.mem.indexOfAny(u8, haystack, char_set);
    }

    /// Find first occurrence of scalar character
    pub fn findScalar(haystack: []const u8, needle: u8) ?usize {
        return std.mem.indexOfScalar(u8, haystack, needle);
    }

    /// Count occurrences of needle in haystack
    pub fn countOccurrences(haystack: []const u8, needle: []const u8) usize {
        if (needle.len == 0) return 0;
        
        var count: usize = 0;
        var pos: usize = 0;
        
        while (pos < haystack.len) {
            if (std.mem.indexOf(u8, haystack[pos..], needle)) |found| {
                count += 1;
                pos += found + needle.len;
            } else {
                break;
            }
        }
        
        return count;
    }

    // ============================================================================
    // String Trimming and Normalization  
    // ============================================================================

    /// Trim whitespace from both ends
    pub fn trim(str: []const u8) []const u8 {
        return std.mem.trim(u8, str, " \t\r\n");
    }

    /// Trim specific characters from both ends
    pub fn trimChars(str: []const u8, chars: []const u8) []const u8 {
        return std.mem.trim(u8, str, chars);
    }

    /// Trim whitespace from left only
    pub fn trimLeft(str: []const u8) []const u8 {
        return std.mem.trimLeft(u8, str, " \t\r\n");
    }

    /// Trim whitespace from right only
    pub fn trimRight(str: []const u8) []const u8 {
        return std.mem.trimRight(u8, str, " \t\r\n");
    }

    // ============================================================================
    // POSIX-Aware Path String Operations
    // ============================================================================

    /// Normalize path separators (POSIX-only, replace multiple slashes with single)
    pub fn normalizePath(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
        if (path.len == 0) return try allocator.dupe(u8, "");
        
        var result = std.ArrayList(u8).init(allocator);
        errdefer result.deinit();
        
        var i: usize = 0;
        while (i < path.len) {
            if (path[i] == '/') {
                try result.append('/');
                // Skip additional slashes
                while (i + 1 < path.len and path[i + 1] == '/') {
                    i += 1;
                }
            } else {
                try result.append(path[i]);
            }
            i += 1;
        }
        
        return result.toOwnedSlice();
    }

    /// Remove trailing slash from path (unless it's root "/")
    pub fn trimTrailingSlash(path: []const u8) []const u8 {
        if (path.len <= 1) return path;
        if (path[path.len - 1] == '/') {
            return path[0..path.len - 1];
        }
        return path;
    }

    /// Ensure path has trailing slash (for directory paths)
    pub fn ensureTrailingSlash(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
        if (path.len == 0) return try allocator.dupe(u8, "/");
        if (path[path.len - 1] == '/') return try allocator.dupe(u8, path);
        
        var result = try allocator.alloc(u8, path.len + 1);
        @memcpy(result[0..path.len], path);
        result[path.len] = '/';
        return result;
    }

    // ============================================================================
    // String Comparison and Validation
    // ============================================================================

    /// Case-insensitive string comparison
    pub fn eqlIgnoreCase(a: []const u8, b: []const u8) bool {
        if (a.len != b.len) return false;
        for (a, b) |char_a, char_b| {
            if (std.ascii.toLower(char_a) != std.ascii.toLower(char_b)) {
                return false;
            }
        }
        return true;
    }

    /// Check if string starts with prefix
    pub fn startsWith(str: []const u8, prefix: []const u8) bool {
        return std.mem.startsWith(u8, str, prefix);
    }

    /// Check if string ends with suffix
    pub fn endsWith(str: []const u8, suffix: []const u8) bool {
        return std.mem.endsWith(u8, str, suffix);
    }

    /// Check if string contains substring
    pub fn contains(str: []const u8, substring: []const u8) bool {
        return std.mem.indexOf(u8, str, substring) != null;
    }

    /// Check if string is valid UTF-8
    pub fn isValidUtf8(str: []const u8) bool {
        return std.unicode.utf8ValidateSlice(str);
    }

    /// Check if string contains only ASCII characters
    pub fn isAscii(str: []const u8) bool {
        for (str) |byte| {
            if (byte > 127) return false;
        }
        return true;
    }

    // ============================================================================
    // String Building and Joining
    // ============================================================================

    /// Join strings with separator
    pub fn join(allocator: std.mem.Allocator, separator: []const u8, strings: []const []const u8) ![]u8 {
        if (strings.len == 0) return try allocator.alloc(u8, 0);
        if (strings.len == 1) return try allocator.dupe(u8, strings[0]);
        
        // Calculate total length
        var total_len: usize = 0;
        for (strings) |str| {
            total_len += str.len;
        }
        total_len += separator.len * (strings.len - 1);
        
        var result = try allocator.alloc(u8, total_len);
        var pos: usize = 0;
        
        for (strings, 0..) |str, i| {
            @memcpy(result[pos..pos + str.len], str);
            pos += str.len;
            
            if (i < strings.len - 1) {
                @memcpy(result[pos..pos + separator.len], separator);
                pos += separator.len;
            }
        }
        
        return result;
    }

    /// Repeat string n times
    pub fn repeat(allocator: std.mem.Allocator, str: []const u8, count: usize) ![]u8 {
        if (count == 0 or str.len == 0) return try allocator.alloc(u8, 0);
        
        const total_len = str.len * count;
        var result = try allocator.alloc(u8, total_len);
        
        var pos: usize = 0;
        var i: usize = 0;
        while (i < count) : (i += 1) {
            @memcpy(result[pos..pos + str.len], str);
            pos += str.len;
        }
        
        return result;
    }

    // ============================================================================
    // Safe String Allocation Helpers
    // ============================================================================

    /// Safely duplicate string with null check
    pub fn safeDupe(allocator: std.mem.Allocator, str: ?[]const u8) !?[]u8 {
        return if (str) |s| try allocator.dupe(u8, s) else null;
    }

    /// Allocate and copy string with size limit for safety
    pub fn dupeWithLimit(allocator: std.mem.Allocator, str: []const u8, max_len: usize) ![]u8 {
        const len = @min(str.len, max_len);
        return try allocator.dupe(u8, str[0..len]);
    }

    /// Replace all occurrences of old with new in string
    pub fn replaceAll(allocator: std.mem.Allocator, str: []const u8, old: []const u8, new: []const u8) ![]u8 {
        if (old.len == 0) return try allocator.dupe(u8, str);
        
        const count = countOccurrences(str, old);
        if (count == 0) return try allocator.dupe(u8, str);
        
        const new_len = str.len - (count * old.len) + (count * new.len);
        var result = try allocator.alloc(u8, new_len);
        
        var result_pos: usize = 0;
        var str_pos: usize = 0;
        
        while (str_pos < str.len) {
            if (str_pos + old.len <= str.len and std.mem.eql(u8, str[str_pos..str_pos + old.len], old)) {
                @memcpy(result[result_pos..result_pos + new.len], new);
                result_pos += new.len;
                str_pos += old.len;
            } else {
                result[result_pos] = str[str_pos];
                result_pos += 1;
                str_pos += 1;
            }
        }
        
        return result;
    }
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "string splitting and tokenization" {
    const allocator = testing.allocator;
    
    // Test splitting
    {
        var result = try StringHelpers.splitToList(allocator, "a,b,c", ",");
        defer result.deinit();
        try testing.expect(result.items().len == 3);
        try testing.expectEqualStrings("a", result.items()[0]);
        try testing.expectEqualStrings("b", result.items()[1]);
        try testing.expectEqualStrings("c", result.items()[2]);
    }
    
    // Test tokenization (skips empty)
    {
        var result = try StringHelpers.tokenizeToList(allocator, "a,,b,c", ",");
        defer result.deinit();
        try testing.expect(result.items().len == 3);
        try testing.expectEqualStrings("a", result.items()[0]);
        try testing.expectEqualStrings("b", result.items()[1]);
        try testing.expectEqualStrings("c", result.items()[2]);
    }
}

test "string search operations" {
    try testing.expect(StringHelpers.findFirst("hello world", "world") == 6);
    try testing.expect(StringHelpers.findFirst("hello world", "xyz") == null);
    try testing.expect(StringHelpers.findLast("hello world hello", "hello") == 12);
    try testing.expect(StringHelpers.countOccurrences("hello hello hello", "hello") == 3);
}

test "string trimming" {
    try testing.expectEqualStrings("hello", StringHelpers.trim("  hello  "));
    try testing.expectEqualStrings("hello", StringHelpers.trimChars("...hello...", "."));
    try testing.expectEqualStrings("hello  ", StringHelpers.trimLeft("  hello  "));
    try testing.expectEqualStrings("  hello", StringHelpers.trimRight("  hello  "));
}

test "path string operations" {
    const allocator = testing.allocator;
    
    // Test path normalization
    {
        const result = try StringHelpers.normalizePath(allocator, "path//to///file");
        defer allocator.free(result);
        try testing.expectEqualStrings("path/to/file", result);
    }
    
    // Test trailing slash operations
    try testing.expectEqualStrings("path", StringHelpers.trimTrailingSlash("path/"));
    try testing.expectEqualStrings("/", StringHelpers.trimTrailingSlash("/"));
    
    {
        const result = try StringHelpers.ensureTrailingSlash(allocator, "path");
        defer allocator.free(result);
        try testing.expectEqualStrings("path/", result);
    }
}

test "string comparison and validation" {
    try testing.expect(StringHelpers.eqlIgnoreCase("Hello", "HELLO"));
    try testing.expect(StringHelpers.startsWith("hello world", "hello"));
    try testing.expect(StringHelpers.endsWith("hello world", "world"));
    try testing.expect(StringHelpers.contains("hello world", "lo wo"));
    try testing.expect(StringHelpers.isValidUtf8("hello"));
    try testing.expect(StringHelpers.isAscii("hello"));
    try testing.expect(!StringHelpers.isAscii("héllo"));
}

test "string building and joining" {
    const allocator = testing.allocator;
    
    // Test join
    {
        const strings = [_][]const u8{ "a", "b", "c" };
        const result = try StringHelpers.join(allocator, ",", &strings);
        defer allocator.free(result);
        try testing.expectEqualStrings("a,b,c", result);
    }
    
    // Test repeat
    {
        const result = try StringHelpers.repeat(allocator, "abc", 3);
        defer allocator.free(result);
        try testing.expectEqualStrings("abcabcabc", result);
    }
    
    // Test replace all
    {
        const result = try StringHelpers.replaceAll(allocator, "hello world hello", "hello", "hi");
        defer allocator.free(result);
        try testing.expectEqualStrings("hi world hi", result);
    }
}

test "safe string operations" {
    const allocator = testing.allocator;
    
    // Test safe dupe
    {
        const result = try StringHelpers.safeDupe(allocator, "hello");
        defer if (result) |r| allocator.free(r);
        try testing.expectEqualStrings("hello", result.?);
    }
    
    {
        const result = try StringHelpers.safeDupe(allocator, null);
        try testing.expect(result == null);
    }
    
    // Test dupe with limit
    {
        const result = try StringHelpers.dupeWithLimit(allocator, "hello world", 5);
        defer allocator.free(result);
        try testing.expectEqualStrings("hello", result);
    }
}