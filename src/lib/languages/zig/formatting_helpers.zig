const std = @import("std");
const ts = @import("tree-sitter");
const LineBuilder = @import("../../parsing/formatter.zig").LineBuilder;
const FormatterOptions = @import("../../parsing/formatter.zig").FormatterOptions;
const ZigUtils = @import("zig_utils.zig").ZigUtils;
const collections = @import("../../core/collections.zig");
const DelimiterTracker = @import("../../text/delimiters.zig").DelimiterTracker;

/// Zig-specific formatting helpers for common patterns
pub const ZigFormattingHelpers = struct {

    /// Format field with Zig-style colon spacing (no space before, space after)
    pub fn formatFieldWithColon(field: []const u8, builder: *LineBuilder) !void {
        if (std.mem.indexOf(u8, field, ":")) |colon_pos| {
            const field_name = std.mem.trim(u8, field[0..colon_pos], " \t");
            const field_type = std.mem.trim(u8, field[colon_pos + 1..], " \t");
            
            try builder.append(field_name);
            try builder.append(": ");
            try builder.append(field_type);
        } else {
            try builder.append(std.mem.trim(u8, field, " \t"));
        }
    }

    /// Format content with braces and proper indentation
    pub fn formatWithBraces(allocator: std.mem.Allocator, builder: *LineBuilder, content: []const u8, formatter_fn: *const fn(std.mem.Allocator, *LineBuilder, []const u8) anyerror!void) !void {
        try builder.append("{");
        
        if (content.len > 0) {
            try builder.newline();
            builder.indent();
            try formatter_fn(allocator, builder, content);
            builder.dedent();
            try builder.appendIndent();
        }
        
        try builder.append("}");
    }

    /// Check if position is inside a string literal
    pub fn isInString(text: []const u8, pos: usize) bool {
        var in_string = false;
        var i: usize = 0;
        while (i < pos and i < text.len) {
            if (text[i] == '"' and (i == 0 or text[i-1] != '\\')) {
                in_string = !in_string;
            }
            i += 1;
        }
        return in_string;
    }

    /// Check if position is inside a comment
    pub fn isInComment(text: []const u8, pos: usize) bool {
        // Look backwards for // comment start
        var i: usize = 0;
        while (i < pos and i + 1 < text.len) {
            if (text[i] == '/' and text[i + 1] == '/') {
                // Found comment start, check if there's a newline between it and pos
                var j = i + 2;
                while (j < pos) {
                    if (text[j] == '\n') return false;
                    j += 1;
                }
                return true;
            }
            i += 1;
        }
        return false;
    }


    /// Parse container content into individual members (fields and methods)
    pub fn parseContainerMembers(allocator: std.mem.Allocator, content: []const u8) ![][]const u8 {
        var members = collections.List([]const u8).init(allocator);
        defer members.deinit();

        var pos: usize = 0;
        
        while (pos < content.len) {
            // Skip whitespace
            while (pos < content.len and (content[pos] == ' ' or content[pos] == '\t' or content[pos] == '\n')) {
                pos += 1;
            }
            
            if (pos >= content.len) break;
            
            // Check if we hit a function 
            if (std.mem.startsWith(u8, content[pos..], "pub fn") or
                std.mem.startsWith(u8, content[pos..], "fn")) {
                // Parse function - find matching braces
                const fn_start = pos;
                
                if (std.mem.indexOfPos(u8, content, pos, "{")) |fn_brace_start| {
                    var brace_depth: u32 = 1;
                    var fn_end = fn_brace_start + 1;
                    
                    while (fn_end < content.len and brace_depth > 0) {
                        if (content[fn_end] == '{') {
                            brace_depth += 1;
                        } else if (content[fn_end] == '}') {
                            brace_depth -= 1;
                        }
                        fn_end += 1;
                    }
                    
                    if (brace_depth == 0) {
                        const function = content[fn_start..fn_end];
                        try members.append(try allocator.dupe(u8, function));
                        pos = fn_end;
                    } else {
                        pos += 1;
                    }
                } else {
                    pos += 1;
                }
            } else {
                // Parse field - find next comma or function start
                const field_start = pos;
                var colon_pos: ?usize = null;
                var field_end: usize = pos;
                
                while (pos < content.len) {
                    if (content[pos] == ':' and colon_pos == null) {
                        colon_pos = pos;
                    }
                    
                    if (content[pos] == ',') {
                        field_end = pos;
                        pos += 1;
                        break;
                    }
                    
                    if (std.mem.startsWith(u8, content[pos..], "pub fn") or 
                        std.mem.startsWith(u8, content[pos..], "fn")) {
                        field_end = pos;
                        break;
                    }
                    
                    pos += 1;
                }
                
                // Accept field with colon (typed field) OR simple identifier (enum value)
                const field = std.mem.trim(u8, content[field_start..field_end], " \t\n\r,");
                if (field.len > 0) {
                    // Check if it's a valid identifier or field declaration
                    if (colon_pos != null or isValidIdentifier(field)) {
                        try members.append(try allocator.dupe(u8, field));
                    }
                }
                
                if (field_end < content.len and (std.mem.startsWith(u8, content[field_end..], "pub fn") or
                                                 std.mem.startsWith(u8, content[field_end..], "fn"))) {
                    pos = field_end;
                }
            }
        }

        return members.toOwnedSlice();
    }

    /// Check if text represents a function declaration
    pub fn isFunctionDeclaration(text: []const u8) bool {
        return std.mem.indexOf(u8, text, "fn ") != null;
    }

    /// Format struct literal field with proper spacing around = signs
    pub fn formatStructLiteralField(builder: *LineBuilder, field: []const u8) !void {
        if (std.mem.indexOf(u8, field, "=")) |equals_pos| {
            const field_name = std.mem.trim(u8, field[0..equals_pos], " \t");
            const field_value = std.mem.trim(u8, field[equals_pos + 1..], " \t");
            
            try builder.append(field_name);
            try builder.append(" = ");
            try builder.append(field_value);
        } else {
            try builder.append(field);
        }
    }

    /// Split text by delimiter while preserving strings
    pub fn splitPreservingStrings(allocator: std.mem.Allocator, text: []const u8, delimiter: u8) ![][]const u8 {
        var result = collections.List([]const u8).init(allocator);
        defer result.deinit();
        
        var start: usize = 0;
        var i: usize = 0;
        var in_string = false;
        
        while (i < text.len) {
            if (text[i] == '"' and (i == 0 or text[i-1] != '\\')) {
                in_string = !in_string;
            } else if (!in_string and text[i] == delimiter) {
                const segment = std.mem.trim(u8, text[start..i], " \t\n\r");
                if (segment.len > 0) {
                    try result.append(try allocator.dupe(u8, segment));
                }
                start = i + 1;
            }
            i += 1;
        }
        
        // Add final segment
        if (start < text.len) {
            const segment = std.mem.trim(u8, text[start..], " \t\n\r");
            if (segment.len > 0) {
                try result.append(try allocator.dupe(u8, segment));
            }
        }
        
        return result.toOwnedSlice();
    }

    /// Format simple spacing around equals
    pub fn formatEqualsSpacing(text: []const u8, builder: *LineBuilder) !void {
        var i: usize = 0;
        while (i < text.len) {
            const c = text[i];
            
            if (c == '=' and i > 0 and text[i-1] != '=' and i + 1 < text.len and text[i+1] != '=') {
                // Ensure no trailing space before equals
                if (builder.buffer.items.len > 0 and
                    builder.buffer.items[builder.buffer.items.len - 1] == ' ') {
                    _ = builder.buffer.pop();
                }
                try builder.append(" = ");
                i += 1;
                // Skip any spaces after equals in original
                while (i < text.len and text[i] == ' ') {
                    i += 1;
                }
                continue;
            }
            
            try builder.append(&[_]u8{c});
            i += 1;
        }
    }
    
    /// Check if text is a valid Zig identifier (for enum values)
    fn isValidIdentifier(text: []const u8) bool {
        if (text.len == 0) return false;
        
        // First character must be letter or underscore
        if (!std.ascii.isAlphabetic(text[0]) and text[0] != '_') {
            return false;
        }
        
        // Rest can be letters, digits, or underscores
        for (text[1..]) |c| {
            if (!std.ascii.isAlphanumeric(c) and c != '_') {
                return false;
            }
        }
        
        return true;
    }

    // === NEW CONSOLIDATED HELPERS ===

    /// Format text with proper Zig spacing for all operators and punctuation
    /// Consolidates spacing logic from format_variable, format_import, format_function, etc.
    pub fn formatWithZigSpacing(text: []const u8, builder: *LineBuilder) !void {
        var tracker = DelimiterTracker{};
        var i: usize = 0;
        var escape_next = false;
        var in_comment = false;

        while (i < text.len) {
            const c = text[i];

            // Handle "test" keyword followed immediately by quote - add space and handle entire string
            if (c == '"' and i >= 4 and 
                std.mem.eql(u8, text[i-4..i], "test") and
                (i == 4 or !std.ascii.isAlphabetic(text[i-5]))) {
                // Add space before the quote for test declarations
                try builder.append(" ");
                
                // Find the closing quote and copy the entire string
                const string_start = i;
                var string_end = i + 1;
                while (string_end < text.len and text[string_end] != '"') {
                    string_end += 1;
                }
                if (string_end < text.len) {
                    string_end += 1; // Include closing quote
                }
                
                // Copy the entire string including quotes
                try builder.append(text[string_start..string_end]);
                i = string_end;
                continue;
            }

            // Handle escape sequences
            if (escape_next) {
                try builder.append(&[_]u8{c});
                escape_next = false;
                i += 1;
                continue;
            }

            if (c == '\\' and tracker.in_string) {
                escape_next = true;
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            // Handle comment detection
            if (!tracker.in_string and i + 1 < text.len and c == '/' and text[i + 1] == '/') {
                in_comment = true;
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            if (in_comment and c == '\n') {
                in_comment = false;
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            if (in_comment) {
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            // Track delimiters and strings
            tracker.trackChar(c);

            if (tracker.in_string) {
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            // Handle colon spacing (Zig style: no space before, space after)
            if (c == ':') {
                // Remove any trailing space before colon
                while (builder.buffer.items.len > 0 and 
                       builder.buffer.items[builder.buffer.items.len - 1] == ' ') {
                    _ = builder.buffer.pop();
                }
                try builder.append(":");
                i += 1;
                
                // Ensure space after colon if next char isn't space
                if (i < text.len and text[i] != ' ') {
                    try builder.append(" ");
                }
                continue;
            }

            // Handle equals spacing (space before and after)
            if (c == '=') {
                // Check for == operator
                if (i + 1 < text.len and text[i + 1] == '=') {
                    // Ensure space before ==
                    if (builder.buffer.items.len > 0 and 
                        builder.buffer.items[builder.buffer.items.len - 1] != ' ') {
                        try builder.append(" ");
                    }
                    try builder.append("==");
                    i += 2;
                    
                    // Ensure space after == if next char isn't space
                    if (i < text.len and text[i] != ' ') {
                        try builder.append(" ");
                    }
                    continue;
                }
                
                // Check for => arrow operator
                if (i + 1 < text.len and text[i + 1] == '>') {
                    // Ensure space before =>
                    if (builder.buffer.items.len > 0 and 
                        builder.buffer.items[builder.buffer.items.len - 1] != ' ') {
                        try builder.append(" ");
                    }
                    try builder.append("=> ");
                    i += 2;
                    continue;
                }
                
                // Regular assignment =
                // Ensure space before =
                if (builder.buffer.items.len > 0 and 
                    builder.buffer.items[builder.buffer.items.len - 1] != ' ') {
                    try builder.append(" ");
                }
                try builder.append("=");
                i += 1;
                
                // Ensure space after = if next char isn't space
                if (i < text.len and text[i] != ' ') {
                    try builder.append(" ");
                }
                continue;
            }

            // Handle parentheses spacing for function signatures
            if (c == ')') {
                try builder.append(&[_]u8{c});
                i += 1;
                
                // Check if next non-space character needs space before it
                // For function return types: `) void` not `)void`
                // But NOT for function calls like `@import("std");`
                if (i < text.len) {
                    var next_i = i;
                    // Skip any existing spaces
                    while (next_i < text.len and text[next_i] == ' ') {
                        next_i += 1;
                    }
                    
                    // Only add space if this looks like a function return type
                    // (next character is alphabetic, not punctuation like ';')
                    if (next_i < text.len and 
                        text[next_i] != '{' and text[next_i] != '\n' and text[next_i] != ';' and
                        std.ascii.isAlphabetic(text[next_i])) {
                        // Skip the spaces we found
                        i = next_i;
                        try builder.append(" ");
                        continue;
                    }
                }
                continue;
            }

            // Handle comma spacing
            if (c == ',') {
                try builder.append(",");
                i += 1;
                
                // Ensure space after comma if next char isn't space or newline
                if (i < text.len and text[i] != ' ' and text[i] != '\n') {
                    try builder.append(" ");
                }
                continue;
            }

            // Handle arithmetic operators
            if ((c == '+' or c == '-' or c == '*' or c == '/') and
                // Avoid double operators like ++, --, etc.
                (i + 1 >= text.len or text[i + 1] != c) and
                // Not part of a negative number
                !(c == '-' and i > 0 and (text[i-1] == '(' or text[i-1] == ',' or text[i-1] == '=' or text[i-1] == ' ')) and
                // Not in a compound assignment
                (i + 1 >= text.len or text[i + 1] != '=')) {
                
                // Ensure space before operator
                if (builder.buffer.items.len > 0 and 
                    builder.buffer.items[builder.buffer.items.len - 1] != ' ') {
                    try builder.append(" ");
                }
                try builder.append(&[_]u8{c});
                i += 1;
                
                // Ensure space after operator if next char isn't space
                if (i < text.len and text[i] != ' ') {
                    try builder.append(" ");
                }
                continue;
            }
            
            // Handle builtin functions like @sqrt
            if (c == '@') {
                // Add space before @ if needed (for "return@sqrt" -> "return @sqrt")
                if (i > 0 and std.ascii.isAlphabetic(text[i-1])) {
                    try builder.append(" ");
                }
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }


            // Handle space normalization
            if (c == ' ') {
                // Only add space if we haven't just added one
                if (builder.buffer.items.len > 0 and
                    builder.buffer.items[builder.buffer.items.len - 1] != ' ') {
                    try builder.append(" ");
                }
                i += 1;
                continue;
            }

            try builder.append(&[_]u8{c});
            i += 1;
        }
    }

    /// Extract declaration name from any Zig declaration pattern
    /// Consolidates name extraction from format_declaration, format_function, etc.
    pub fn extractDeclarationName(text: []const u8) ?[]const u8 {
        const trimmed = std.mem.trim(u8, text, " \t\n\r");
        
        // Handle various declaration patterns
        var start_pos: usize = 0;
        
        if (std.mem.startsWith(u8, trimmed, "pub const ")) {
            start_pos = 10; // length of "pub const "
        } else if (std.mem.startsWith(u8, trimmed, "const ")) {
            start_pos = 6; // length of "const "
        } else if (std.mem.startsWith(u8, trimmed, "pub fn ")) {
            start_pos = 7; // length of "pub fn "
        } else if (std.mem.startsWith(u8, trimmed, "fn ")) {
            start_pos = 3; // length of "fn "
        } else if (std.mem.startsWith(u8, trimmed, "pub var ")) {
            start_pos = 8; // length of "pub var "
        } else if (std.mem.startsWith(u8, trimmed, "var ")) {
            start_pos = 4; // length of "var "
        } else if (std.mem.startsWith(u8, trimmed, "test ")) {
            start_pos = 5; // length of "test "
        } else {
            return null;
        }
        
        // Find the end of the name (before " =", "(", ":", or "{")
        var end_pos: usize = trimmed.len;
        const delimiters = [_][]const u8{ " =", "(", ":", "{", " " };
        
        for (delimiters) |delimiter| {
            if (std.mem.indexOfPos(u8, trimmed, start_pos, delimiter)) |pos| {
                end_pos = @min(end_pos, pos);
            }
        }
        
        if (end_pos > start_pos) {
            const name = std.mem.trim(u8, trimmed[start_pos..end_pos], " \t");
            if (name.len > 0) {
                return name;
            }
        }
        
        return null;
    }

    /// Format block content with braces, proper indentation, and consistent spacing
    /// Consolidates brace formatting from format_function, format_container, format_test, etc.
    pub fn formatBlockWithBraces(builder: *LineBuilder, signature: []const u8, body: []const u8, newline_before_close: bool) !void {
        // Format signature with proper spacing
        try formatWithZigSpacing(signature, builder);
        
        // Add opening brace with space
        if (builder.buffer.items.len > 0 and 
            builder.buffer.items[builder.buffer.items.len - 1] != ' ') {
            try builder.append(" ");
        }
        try builder.append("{");
        
        // Format body if present
        if (body.len > 0) {
            try builder.newline();
            builder.indent();
            try formatBodyContent(body, builder);
            builder.dedent();
            
            if (newline_before_close) {
                try builder.appendIndent();
            }
        }
        
        try builder.append("}");
    }

    /// Format body content with proper statement separation
    /// Used by formatBlockWithBraces and standalone body formatting
    pub fn formatBodyContent(body: []const u8, builder: *LineBuilder) !void {
        const trimmed = std.mem.trim(u8, body, " \t\n\r");
        if (trimmed.len == 0) return;
        
        // Split by semicolons for Zig statements, then by lines
        var statements = std.mem.splitSequence(u8, trimmed, ";");
        while (statements.next()) |statement| {
            const stmt_trimmed = std.mem.trim(u8, statement, " \t\n\r");
            if (stmt_trimmed.len > 0) {
                try builder.appendIndent();
                try formatWithZigSpacing(stmt_trimmed, builder);
                try builder.append(";");
                try builder.newline();
            }
        }
    }

    /// Classify declaration type for consistent handling
    /// Consolidates type checking from multiple format modules
    pub const DeclarationType = enum {
        function,
        constant,
        variable,
        type_definition, // struct, enum, union
        import,
        test_decl,
        unknown,
    };

    pub fn classifyDeclaration(text: []const u8) DeclarationType {
        const trimmed = std.mem.trim(u8, text, " \t\n\r");
        
        // Check for imports first (most specific)
        if (std.mem.indexOf(u8, trimmed, "@import") != null) {
            return .import;
        }
        
        // Check for test declarations
        if (std.mem.startsWith(u8, trimmed, "test ")) {
            return .test_decl;
        }
        
        // Check for function declarations
        if (std.mem.startsWith(u8, trimmed, "fn ") or 
            std.mem.startsWith(u8, trimmed, "pub fn ") or
            std.mem.startsWith(u8, trimmed, "inline fn ") or
            std.mem.startsWith(u8, trimmed, "export fn ")) {
            return .function;
        }
        
        // Check for type definitions
        if ((std.mem.startsWith(u8, trimmed, "const ") or std.mem.startsWith(u8, trimmed, "pub const ")) and
            (std.mem.indexOf(u8, trimmed, "struct") != null or
             std.mem.indexOf(u8, trimmed, "enum") != null or
             std.mem.indexOf(u8, trimmed, "union") != null)) {
            return .type_definition;
        }
        
        // Check for constants
        if (std.mem.startsWith(u8, trimmed, "const ") or std.mem.startsWith(u8, trimmed, "pub const ")) {
            return .constant;
        }
        
        // Check for variables
        if (std.mem.startsWith(u8, trimmed, "var ") or std.mem.startsWith(u8, trimmed, "pub var ")) {
            return .variable;
        }
        
        return .unknown;
    }

    /// Split parameters/fields by comma while preserving strings and nested structures
    /// Enhanced version that uses DelimiterTracker for reliability
    pub fn splitByCommaPreservingStructure(allocator: std.mem.Allocator, text: []const u8) ![][]const u8 {
        var result = collections.List([]const u8).init(allocator);
        defer result.deinit();
        
        var start: usize = 0;
        var i: usize = 0;
        var tracker = DelimiterTracker{};
        
        while (i < text.len) {
            const c = text[i];
            tracker.trackChar(c);
            
            // Split on comma only when at top level
            if (c == ',' and tracker.isTopLevel()) {
                const segment = std.mem.trim(u8, text[start..i], " \t\n\r");
                if (segment.len > 0) {
                    try result.append(try allocator.dupe(u8, segment));
                }
                start = i + 1;
            }
            
            i += 1;
        }
        
        // Add final segment
        if (start < text.len) {
            const segment = std.mem.trim(u8, text[start..], " \t\n\r");
            if (segment.len > 0) {
                try result.append(try allocator.dupe(u8, segment));
            }
        }
        
        return result.toOwnedSlice();
    }

    /// Format function call with proper spacing around parentheses
    /// Consolidates function call formatting patterns (switch(x) vs switch (x))
    pub fn formatFunctionCall(text: []const u8, builder: *LineBuilder) !void {
        var i: usize = 0;
        while (i < text.len) {
            const c = text[i];
            
            if (c == '(' and i > 0) {
                // Check if previous character is alphanumeric (function name)
                const prev = text[i - 1];
                if (std.ascii.isAlphanumeric(prev) or prev == '_') {
                    // Add space before parenthesis for function calls like "switch (x)"
                    if (builder.buffer.items.len > 0 and 
                        builder.buffer.items[builder.buffer.items.len - 1] != ' ') {
                        try builder.append(" ");
                    }
                }
            }
            
            try builder.append(&[_]u8{c});
            i += 1;
        }
    }
};