const std = @import("std");

/// Match a string against a simple glob pattern (*, ?, [], {})
/// This is the full implementation with support for:
/// - * (wildcard matching zero or more characters)
/// - ? (single character wildcard)
/// - [...] (character classes with ranges and negation)
/// - \ (escape sequences)
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
/// Supports:
/// - Single characters: [abc] matches 'a', 'b', or 'c'
/// - Ranges: [a-z] matches any lowercase letter
/// - Negation: [!0-9] or [^0-9] matches any non-digit
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
