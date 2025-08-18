const std = @import("std");

/// Common parsing patterns shared across languages
/// 
/// These patterns help with tokenization and parsing of constructs
/// that appear in multiple languages.
pub const Pattern = struct {
    /// Check if character is a valid identifier start
    pub fn isIdentifierStart(char: u8) bool {
        return switch (char) {
            'a'...'z', 'A'...'Z', '_', '$' => true,
            else => false,
        };
    }
    
    /// Check if character is a valid identifier character
    pub fn isIdentifierChar(char: u8) bool {
        return switch (char) {
            'a'...'z', 'A'...'Z', '0'...'9', '_', '$' => true,
            else => false,
        };
    }
    
    /// Check if character is a digit
    pub fn isDigit(char: u8) bool {
        return char >= '0' and char <= '9';
    }
    
    /// Check if character is hexadecimal digit
    pub fn isHexDigit(char: u8) bool {
        return switch (char) {
            '0'...'9', 'a'...'f', 'A'...'F' => true,
            else => false,
        };
    }
    
    /// Check if character is whitespace
    pub fn isWhitespace(char: u8) bool {
        return switch (char) {
            ' ', '\t', '\r' => true,
            else => false,
        };
    }
    
    /// Check if character is newline
    pub fn isNewline(char: u8) bool {
        return char == '\n';
    }
    
    /// Check if character starts a string literal
    pub fn isStringDelimiter(char: u8) bool {
        return switch (char) {
            '"', '\'' => true,
            else => false,
        };
    }
    
    /// Check if character is an operator character
    pub fn isOperatorChar(char: u8) bool {
        return switch (char) {
            '+', '-', '*', '/', '%', '=', '!', '<', '>', '&', '|', '^', '~', '?', ':' => true,
            else => false,
        };
    }
    
    /// Check if character is a delimiter
    pub fn isDelimiterChar(char: u8) bool {
        return switch (char) {
            '(', ')', '{', '}', '[', ']', ';', ',', '.' => true,
            else => false,
        };
    }
    
    /// Scan identifier from input starting at position
    pub fn scanIdentifier(input: []const u8, start: usize) usize {
        if (start >= input.len or !isIdentifierStart(input[start])) {
            return start;
        }
        
        var pos = start + 1;
        while (pos < input.len and isIdentifierChar(input[pos])) {
            pos += 1;
        }
        
        return pos;
    }
    
    /// Scan number from input starting at position
    pub fn scanNumber(input: []const u8, start: usize) NumberScanResult {
        if (start >= input.len or !isDigit(input[start])) {
            return NumberScanResult{ .end = start, .kind = .invalid };
        }
        
        var pos = start;
        var kind = NumberKind.integer;
        
        // Handle negative sign
        if (pos < input.len and input[pos] == '-') {
            pos += 1;
        }
        
        // Scan integer part
        while (pos < input.len and isDigit(input[pos])) {
            pos += 1;
        }
        
        // Check for decimal point
        if (pos < input.len and input[pos] == '.') {
            kind = .float;
            pos += 1;
            
            // Scan fractional part
            while (pos < input.len and isDigit(input[pos])) {
                pos += 1;
            }
        }
        
        // Check for exponent
        if (pos < input.len and (input[pos] == 'e' or input[pos] == 'E')) {
            kind = .float;
            pos += 1;
            
            // Optional sign
            if (pos < input.len and (input[pos] == '+' or input[pos] == '-')) {
                pos += 1;
            }
            
            // Exponent digits
            const exp_start = pos;
            while (pos < input.len and isDigit(input[pos])) {
                pos += 1;
            }
            
            // Must have at least one exponent digit
            if (pos == exp_start) {
                return NumberScanResult{ .end = start, .kind = .invalid };
            }
        }
        
        return NumberScanResult{ .end = pos, .kind = kind };
    }
    
    /// Scan string literal from input starting at position
    pub fn scanString(input: []const u8, start: usize) StringScanResult {
        if (start >= input.len or !isStringDelimiter(input[start])) {
            return StringScanResult{ .end = start, .terminated = false };
        }
        
        const delimiter = input[start];
        var pos = start + 1;
        
        while (pos < input.len) {
            const char = input[pos];
            
            if (char == delimiter) {
                return StringScanResult{ .end = pos + 1, .terminated = true };
            }
            
            // Handle escape sequences
            if (char == '\\' and pos + 1 < input.len) {
                pos += 2; // Skip escaped character
            } else {
                pos += 1;
            }
        }
        
        // Unterminated string
        return StringScanResult{ .end = pos, .terminated = false };
    }
    
    /// Scan line comment from input starting at position
    pub fn scanLineComment(input: []const u8, start: usize, prefix: []const u8) usize {
        if (start + prefix.len > input.len) {
            return start;
        }
        
        // Check for comment prefix
        if (!std.mem.eql(u8, input[start..start + prefix.len], prefix)) {
            return start;
        }
        
        var pos = start + prefix.len;
        
        // Scan to end of line
        while (pos < input.len and !isNewline(input[pos])) {
            pos += 1;
        }
        
        return pos;
    }
    
    /// Scan block comment from input starting at position
    pub fn scanBlockComment(input: []const u8, start: usize, start_delim: []const u8, end_delim: []const u8) BlockCommentResult {
        if (start + start_delim.len > input.len) {
            return BlockCommentResult{ .end = start, .terminated = false };
        }
        
        // Check for comment start
        if (!std.mem.eql(u8, input[start..start + start_delim.len], start_delim)) {
            return BlockCommentResult{ .end = start, .terminated = false };
        }
        
        var pos = start + start_delim.len;
        
        // Scan for end delimiter
        while (pos + end_delim.len <= input.len) {
            if (std.mem.eql(u8, input[pos..pos + end_delim.len], end_delim)) {
                return BlockCommentResult{ .end = pos + end_delim.len, .terminated = true };
            }
            pos += 1;
        }
        
        // Unterminated comment
        return BlockCommentResult{ .end = input.len, .terminated = false };
    }
    
    /// Skip whitespace from input starting at position
    pub fn skipWhitespace(input: []const u8, start: usize) usize {
        var pos = start;
        while (pos < input.len and isWhitespace(input[pos])) {
            pos += 1;
        }
        return pos;
    }
    
    /// Skip whitespace and newlines from input starting at position
    pub fn skipWhitespaceAndNewlines(input: []const u8, start: usize) usize {
        var pos = start;
        while (pos < input.len and (isWhitespace(input[pos]) or isNewline(input[pos]))) {
            pos += 1;
        }
        return pos;
    }
};

pub const NumberKind = enum {
    integer,
    float,
    invalid,
};

pub const NumberScanResult = struct {
    end: usize,
    kind: NumberKind,
};

pub const StringScanResult = struct {
    end: usize,
    terminated: bool,
};

pub const BlockCommentResult = struct {
    end: usize,
    terminated: bool,
};

/// Language-specific comment patterns
pub const CommentPatterns = struct {
    line_comment: ?[]const u8,
    block_comment_start: ?[]const u8,
    block_comment_end: ?[]const u8,
    
    // Common patterns
    pub const c_like = CommentPatterns{
        .line_comment = "//",
        .block_comment_start = "/*",
        .block_comment_end = "*/",
    };
    
    pub const hash_comments = CommentPatterns{
        .line_comment = "#",
        .block_comment_start = null,
        .block_comment_end = null,
    };
    
    pub const html_comments = CommentPatterns{
        .line_comment = null,
        .block_comment_start = "<!--",
        .block_comment_end = "-->",
    };
    
    pub const css_comments = CommentPatterns{
        .line_comment = null,
        .block_comment_start = "/*",
        .block_comment_end = "*/",
    };
};