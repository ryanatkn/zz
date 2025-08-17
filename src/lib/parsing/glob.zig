const std = @import("std");

/// Simple glob pattern matching implementation
/// Supports basic wildcards: * and ?
pub fn matchSimplePattern(filename: []const u8, pattern: []const u8) bool {
    if (pattern.len == 0) return filename.len == 0;
    if (filename.len == 0) return pattern.len == 0 or std.mem.eql(u8, pattern, "*");
    
    // Handle exact match
    if (std.mem.eql(u8, filename, pattern)) return true;
    
    // Handle wildcard patterns
    if (std.mem.indexOf(u8, pattern, "*")) |_| {
        return matchWildcard(filename, pattern);
    }
    
    if (std.mem.indexOf(u8, pattern, "?")) |_| {
        return matchQuestion(filename, pattern);
    }
    
    return false;
}

/// Match patterns with * wildcard
fn matchWildcard(filename: []const u8, pattern: []const u8) bool {
    // Simple implementation: split on * and check parts
    var parts = std.mem.splitScalar(u8, pattern, '*');
    var remaining = filename;
    
    while (parts.next()) |part| {
        if (part.len == 0) continue;
        
        if (std.mem.indexOf(u8, remaining, part)) |pos| {
            remaining = remaining[pos + part.len..];
        } else {
            return false;
        }
    }
    
    return true;
}

/// Match patterns with ? wildcard
fn matchQuestion(filename: []const u8, pattern: []const u8) bool {
    if (filename.len != pattern.len) return false;
    
    for (filename, pattern) |f_char, p_char| {
        if (p_char != '?' and p_char != f_char) return false;
    }
    
    return true;
}

/// Check if pattern contains glob characters
pub fn isGlobPattern(pattern: []const u8) bool {
    return std.mem.indexOf(u8, pattern, "*") != null or 
           std.mem.indexOf(u8, pattern, "?") != null;
}

test "simple glob matching" {
    const testing = std.testing;
    
    // Exact matches
    try testing.expect(matchSimplePattern("test.txt", "test.txt"));
    try testing.expect(!matchSimplePattern("test.txt", "other.txt"));
    
    // Wildcard matches
    try testing.expect(matchSimplePattern("test.txt", "*.txt"));
    try testing.expect(matchSimplePattern("file.js", "*.js"));
    try testing.expect(!matchSimplePattern("file.js", "*.txt"));
    
    // Question mark matches
    try testing.expect(matchSimplePattern("a.txt", "?.txt"));
    try testing.expect(!matchSimplePattern("ab.txt", "?.txt"));
    
    // Pattern detection
    try testing.expect(isGlobPattern("*.txt"));
    try testing.expect(isGlobPattern("?.js"));
    try testing.expect(!isGlobPattern("file.txt"));
}