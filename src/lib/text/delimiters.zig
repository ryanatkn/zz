const std = @import("std");

/// Language-agnostic delimiter matching and depth tracking
/// Used across all formatters for balanced parsing of braces, brackets, parentheses
pub const DelimiterTracker = struct {
    brace_depth: i32 = 0,      // {}
    bracket_depth: i32 = 0,    // []
    paren_depth: i32 = 0,      // ()
    in_string: bool = false,
    string_char: u8 = 0,

    /// Track a character and update depth counters
    pub fn trackChar(self: *DelimiterTracker, char: u8) void {
        // Handle string boundaries first
        if (!self.in_string and (char == '"' or char == '\'' or char == '`')) {
            self.in_string = true;
            self.string_char = char;
            return;
        }
        
        if (self.in_string) {
            if (char == self.string_char) {
                self.in_string = false;
            }
            return;
        }

        // Track delimiters when not in string
        switch (char) {
            '{' => self.brace_depth += 1,
            '}' => self.brace_depth -= 1,
            '[' => self.bracket_depth += 1,
            ']' => self.bracket_depth -= 1,
            '(' => self.paren_depth += 1,
            ')' => self.paren_depth -= 1,
            else => {},
        }
    }

    /// Get total nesting depth (all delimiter types)
    pub fn totalDepth(self: DelimiterTracker) i32 {
        return self.brace_depth + self.bracket_depth + self.paren_depth;
    }

    /// Check if we're at top level (no nesting)
    pub fn isTopLevel(self: DelimiterTracker) bool {
        return self.totalDepth() == 0 and !self.in_string;
    }

    /// Check if all delimiters are balanced
    pub fn isBalanced(self: DelimiterTracker) bool {
        return self.brace_depth == 0 and 
               self.bracket_depth == 0 and 
               self.paren_depth == 0 and
               !self.in_string;
    }

    /// Reset all counters
    pub fn reset(self: *DelimiterTracker) void {
        self.brace_depth = 0;
        self.bracket_depth = 0;
        self.paren_depth = 0;
        self.in_string = false;
        self.string_char = 0;
    }
};

/// Split text by delimiter, respecting nested structures
/// Language-agnostic utility that works for parameter lists, arrays, objects, etc.
pub fn splitRespectingNesting(
    allocator: std.mem.Allocator,
    text: []const u8,
    delimiter: u8,
) ![][]const u8 {
    var parts = std.ArrayList([]const u8).init(allocator);
    defer parts.deinit();

    var tracker = DelimiterTracker{};
    var start: usize = 0;

    for (text, 0..) |char, i| {
        tracker.trackChar(char);
        
        if (char == delimiter and tracker.isTopLevel()) {
            const part = std.mem.trim(u8, text[start..i], " \t\n\r");
            if (part.len > 0) {
                try parts.append(try allocator.dupe(u8, part));
            }
            start = i + 1;
        }
    }

    // Add final part
    const final_part = std.mem.trim(u8, text[start..], " \t\n\r");
    if (final_part.len > 0) {
        try parts.append(try allocator.dupe(u8, final_part));
    }

    return parts.toOwnedSlice();
}

/// Find matching closing delimiter from a given position
/// Returns the position of the matching closer, or null if not found
pub fn findMatchingDelimiter(
    text: []const u8,
    start_pos: usize,
    open_char: u8,
    close_char: u8,
) ?usize {
    if (start_pos >= text.len or text[start_pos] != open_char) {
        return null;
    }

    var tracker = DelimiterTracker{};
    tracker.trackChar(open_char); // Track the opening character

    for (text[start_pos + 1..], start_pos + 1..) |char, i| {
        tracker.trackChar(char);
        
        if (char == close_char) {
            // Check if this closes our original opening
            switch (open_char) {
                '{' => if (tracker.brace_depth == 0) return i,
                '[' => if (tracker.bracket_depth == 0) return i,
                '(' => if (tracker.paren_depth == 0) return i,
                else => {},
            }
        }
    }

    return null;
}

/// Extract content between balanced delimiters
/// Returns the content between the delimiters, or null if not balanced
pub fn extractBetweenDelimiters(
    text: []const u8,
    open_char: u8,
    close_char: u8,
) ?[]const u8 {
    const open_pos = std.mem.indexOfScalar(u8, text, open_char) orelse return null;
    const close_pos = findMatchingDelimiter(text, open_pos, open_char, close_char) orelse return null;
    
    if (close_pos <= open_pos + 1) return null;
    
    return text[open_pos + 1..close_pos];
}

/// Language-agnostic indentation helper
pub const IndentationHelper = struct {
    /// Format a block with proper indentation
    pub fn formatIndentedBlock(
        allocator: std.mem.Allocator,
        content: []const u8,
        indent_size: u32,
    ) ![]u8 {
        var result = std.ArrayList(u8).init(allocator);
        defer result.deinit();

        var lines = std.mem.splitScalar(u8, content, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t");
            if (trimmed.len > 0) {
                // Add indentation
                for (0..indent_size) |_| {
                    try result.append(' ');
                }
                try result.appendSlice(trimmed);
            }
            try result.append('\n');
        }

        return result.toOwnedSlice();
    }

    /// Count indentation level of a line
    pub fn countIndentLevel(line: []const u8, indent_size: u32) u32 {
        var spaces: u32 = 0;
        for (line) |char| {
            if (char == ' ') {
                spaces += 1;
            } else if (char == '\t') {
                spaces += indent_size; // Tab = 4 spaces by default
            } else {
                break;
            }
        }
        return spaces / indent_size;
    }
};