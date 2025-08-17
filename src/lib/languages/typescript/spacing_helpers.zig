const std = @import("std");
const LineBuilder = @import("../../parsing/formatter.zig").LineBuilder;
const DelimiterTracker = @import("../../text/delimiters.zig").DelimiterTracker;

/// TypeScript-specific spacing helpers for operator formatting
/// Separated from main formatting_helpers to keep operator logic modular
pub const TypeScriptSpacingHelpers = struct {

    /// Format colon spacing with TypeScript rules (no space before, space after)
    /// Used in type annotations, interface properties, object types
    pub fn formatColonSpacing(text: []const u8, builder: *LineBuilder) !void {
        var i: usize = 0;
        var tracker = DelimiterTracker{};
        var in_generic = false;
        var generic_depth: u32 = 0;

        while (i < text.len) {
            const c = text[i];
            tracker.trackChar(c);

            if (tracker.in_string) {
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            // Track generic parameters to avoid spacing inside <T>
            if (c == '<') {
                in_generic = true;
                generic_depth += 1;
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            if (c == '>') {
                if (generic_depth > 0) {
                    generic_depth -= 1;
                    if (generic_depth == 0) {
                        in_generic = false;
                    }
                }
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            if (c == ':' and !in_generic) {
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

            try builder.append(&[_]u8{c});
            i += 1;
        }
    }

    /// Format union and intersection type spacing (| and &)
    /// Ensures space before and after union/intersection operators
    pub fn formatUnionIntersectionSpacing(text: []const u8, builder: *LineBuilder) !void {
        var i: usize = 0;
        var tracker = DelimiterTracker{};

        while (i < text.len) {
            const c = text[i];
            tracker.trackChar(c);

            if (tracker.in_string) {
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            if (c == '|' or c == '&') {
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

            try builder.append(&[_]u8{c});
            i += 1;
        }
    }

    /// Format arrow function operator (=>) with proper spacing
    /// Handles both function expressions and method chaining
    pub fn formatArrowOperator(text: []const u8, builder: *LineBuilder) !void {
        var i: usize = 0;
        var tracker = DelimiterTracker{};

        while (i < text.len) {
            const c = text[i];
            tracker.trackChar(c);

            if (tracker.in_string) {
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            if (c == '=' and i + 1 < text.len and text[i + 1] == '>') {
                // Ensure space before =>
                if (builder.buffer.items.len > 0 and 
                    builder.buffer.items[builder.buffer.items.len - 1] != ' ') {
                    try builder.append(" ");
                }
                try builder.append("=> ");
                i += 2;
                continue;
            }

            try builder.append(&[_]u8{c});
            i += 1;
        }
    }

    /// Format assignment operators (=, +=, -=, etc.) with proper spacing
    /// Ensures space before and after assignment operators
    pub fn formatAssignmentSpacing(text: []const u8, builder: *LineBuilder) !void {
        var i: usize = 0;
        var tracker = DelimiterTracker{};

        while (i < text.len) {
            const c = text[i];
            tracker.trackChar(c);

            if (tracker.in_string) {
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            if (c == '=') {
                // Check for compound assignment operators (+=, -=, etc.)
                if (i > 0) {
                    const prev = text[i - 1];
                    if (prev == '+' or prev == '-' or prev == '*' or prev == '/' or 
                       prev == '%' or prev == '&' or prev == '|' or prev == '^') {
                        // This is a compound assignment, handled by the previous character
                        try builder.append("=");
                        i += 1;
                        // Ensure space after =
                        if (i < text.len and text[i] != ' ') {
                            try builder.append(" ");
                        }
                        continue;
                    }
                }

                // Check for equality operators (==, ===)
                if (i + 1 < text.len and text[i + 1] == '=') {
                    // Ensure space before ==
                    if (builder.buffer.items.len > 0 and 
                        builder.buffer.items[builder.buffer.items.len - 1] != ' ') {
                        try builder.append(" ");
                    }
                    if (i + 2 < text.len and text[i + 2] == '=') {
                        try builder.append("===");
                        i += 3;
                    } else {
                        try builder.append("==");
                        i += 2;
                    }
                    
                    // Ensure space after operator
                    if (i < text.len and text[i] != ' ') {
                        try builder.append(" ");
                    }
                    continue;
                }

                // Check for arrow operator (handled separately)
                if (i + 1 < text.len and text[i + 1] == '>') {
                    try formatArrowOperator(text[i..], builder);
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

            // Handle compound assignment operators
            if ((c == '+' or c == '-' or c == '*' or c == '/' or 
                 c == '%' or c == '&' or c == '|' or c == '^') and
                i + 1 < text.len and text[i + 1] == '=') {
                
                // Ensure space before compound operator
                if (builder.buffer.items.len > 0 and 
                    builder.buffer.items[builder.buffer.items.len - 1] != ' ') {
                    try builder.append(" ");
                }
                try builder.append(&[_]u8{c});
                // Continue to handle the = in the next iteration
            } else {
                try builder.append(&[_]u8{c});
            }
            i += 1;
        }
    }

    /// Format comma spacing with TypeScript rules
    /// Ensures space after comma for parameters, array elements, etc.
    pub fn formatCommaSpacing(text: []const u8, builder: *LineBuilder) !void {
        var i: usize = 0;
        var tracker = DelimiterTracker{};

        while (i < text.len) {
            const c = text[i];
            tracker.trackChar(c);

            if (tracker.in_string) {
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            if (c == ',') {
                try builder.append(",");
                i += 1;
                
                // Ensure space after comma if next char isn't space or newline
                if (i < text.len and text[i] != ' ' and text[i] != '\n') {
                    try builder.append(" ");
                }
                continue;
            }

            try builder.append(&[_]u8{c});
            i += 1;
        }
    }

    /// Format optional parameter/property operator (?) spacing
    /// Handles both optional parameters (param?) and optional chaining (obj?.prop)
    pub fn formatOptionalSpacing(text: []const u8, builder: *LineBuilder) !void {
        var i: usize = 0;
        var tracker = DelimiterTracker{};

        while (i < text.len) {
            const c = text[i];
            tracker.trackChar(c);

            if (tracker.in_string) {
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            if (c == '?') {
                // Check for optional chaining (?.)
                if (i + 1 < text.len and text[i + 1] == '.') {
                    try builder.append("?.");
                    i += 2;
                    continue;
                }

                // Check for nullish coalescing (??)
                if (i + 1 < text.len and text[i + 1] == '?') {
                    // Ensure space before ??
                    if (builder.buffer.items.len > 0 and 
                        builder.buffer.items[builder.buffer.items.len - 1] != ' ') {
                        try builder.append(" ");
                    }
                    try builder.append("??");
                    i += 2;
                    
                    // Ensure space after ??
                    if (i < text.len and text[i] != ' ') {
                        try builder.append(" ");
                    }
                    continue;
                }

                // Regular optional parameter/property
                try builder.append("?");
                i += 1;
                continue;
            }

            try builder.append(&[_]u8{c});
            i += 1;
        }
    }

    /// Format template literal spacing and embedded expressions
    /// Handles template literals with ${} expressions
    pub fn formatTemplateLiteralSpacing(text: []const u8, builder: *LineBuilder) !void {
        var i: usize = 0;
        var in_template = false;
        var template_depth: u32 = 0;
        var tracker = DelimiterTracker{};

        while (i < text.len) {
            const c = text[i];

            if (!tracker.in_string and c == '`') {
                in_template = !in_template;
                if (in_template) {
                    template_depth = 1;
                } else {
                    template_depth = 0;
                }
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            if (in_template) {
                if (c == '$' and i + 1 < text.len and text[i + 1] == '{') {
                    try builder.append("${");
                    template_depth += 1;
                    i += 2;
                    continue;
                } else if (c == '}' and template_depth > 1) {
                    try builder.append("}");
                    template_depth -= 1;
                    i += 1;
                    continue;
                }
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            if (!in_template) {
                tracker.trackChar(c);
            }

            try builder.append(&[_]u8{c});
            i += 1;
        }
    }

    /// Format all TypeScript spacing rules in one pass
    /// Comprehensive spacing formatter that handles all operators and punctuation
    pub fn formatAllSpacing(text: []const u8, builder: *LineBuilder) !void {
        var i: usize = 0;
        var tracker = DelimiterTracker{};
        var escape_next = false;
        var in_comment = false;
        var in_template = false;
        var template_depth: u32 = 0;
        var in_generic = false;
        var generic_depth: u32 = 0;

        while (i < text.len) {
            const c = text[i];

            // Handle escape sequences
            if (escape_next) {
                try builder.append(&[_]u8{c});
                escape_next = false;
                i += 1;
                continue;
            }

            if (c == '\\' and (tracker.in_string or in_template)) {
                escape_next = true;
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            // Handle comment detection
            if (!tracker.in_string and !in_template and i + 1 < text.len and c == '/' and text[i + 1] == '/') {
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

            // Handle template literals
            if (!tracker.in_string and c == '`') {
                in_template = !in_template;
                if (in_template) {
                    template_depth = 1;
                } else {
                    template_depth = 0;
                }
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            if (in_template) {
                if (c == '$' and i + 1 < text.len and text[i + 1] == '{') {
                    try builder.append("${");
                    template_depth += 1;
                    i += 2;
                    continue;
                } else if (c == '}' and template_depth > 1) {
                    try builder.append("}");
                    template_depth -= 1;
                    i += 1;
                    continue;
                }
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

            // Track generic parameters
            if (c == '<') {
                in_generic = true;
                generic_depth += 1;
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            if (c == '>') {
                if (generic_depth > 0) {
                    generic_depth -= 1;
                    if (generic_depth == 0) {
                        in_generic = false;
                    }
                }
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            // Apply specific spacing rules
            switch (c) {
                ':' => {
                    if (!in_generic) {
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
                    try builder.append(&[_]u8{c});
                    i += 1;
                },
                '=' => {
                    // Handle various equals-based operators
                    if (i + 1 < text.len and text[i + 1] == '=') {
                        // == or ===
                        if (builder.buffer.items.len > 0 and 
                            builder.buffer.items[builder.buffer.items.len - 1] != ' ') {
                            try builder.append(" ");
                        }
                        if (i + 2 < text.len and text[i + 2] == '=') {
                            try builder.append("===");
                            i += 3;
                        } else {
                            try builder.append("==");
                            i += 2;
                        }
                        if (i < text.len and text[i] != ' ') {
                            try builder.append(" ");
                        }
                        continue;
                    } else if (i + 1 < text.len and text[i + 1] == '>') {
                        // Arrow operator =>
                        if (builder.buffer.items.len > 0 and 
                            builder.buffer.items[builder.buffer.items.len - 1] != ' ') {
                            try builder.append(" ");
                        }
                        try builder.append("=> ");
                        i += 2;
                        continue;
                    } else {
                        // Regular assignment
                        if (builder.buffer.items.len > 0 and 
                            builder.buffer.items[builder.buffer.items.len - 1] != ' ') {
                            try builder.append(" ");
                        }
                        try builder.append("=");
                        i += 1;
                        if (i < text.len and text[i] != ' ') {
                            try builder.append(" ");
                        }
                        continue;
                    }
                },
                '|', '&' => {
                    // Union and intersection types
                    if (builder.buffer.items.len > 0 and 
                        builder.buffer.items[builder.buffer.items.len - 1] != ' ') {
                        try builder.append(" ");
                    }
                    try builder.append(&[_]u8{c});
                    i += 1;
                    if (i < text.len and text[i] != ' ') {
                        try builder.append(" ");
                    }
                    continue;
                },
                ',' => {
                    try builder.append(",");
                    i += 1;
                    if (i < text.len and text[i] != ' ' and text[i] != '\n') {
                        try builder.append(" ");
                    }
                    continue;
                },
                '?' => {
                    // Optional chaining, nullish coalescing, or optional parameters
                    if (i + 1 < text.len and text[i + 1] == '.') {
                        try builder.append("?.");
                        i += 2;
                    } else if (i + 1 < text.len and text[i + 1] == '?') {
                        if (builder.buffer.items.len > 0 and 
                            builder.buffer.items[builder.buffer.items.len - 1] != ' ') {
                            try builder.append(" ");
                        }
                        try builder.append("??");
                        i += 2;
                        if (i < text.len and text[i] != ' ') {
                            try builder.append(" ");
                        }
                    } else {
                        try builder.append("?");
                        i += 1;
                    }
                    continue;
                },
                ' ' => {
                    // Only add space if we haven't just added one
                    if (builder.buffer.items.len > 0 and
                        builder.buffer.items[builder.buffer.items.len - 1] != ' ') {
                        try builder.append(" ");
                    }
                    i += 1;
                    continue;
                },
                else => {
                    try builder.append(&[_]u8{c});
                    i += 1;
                },
            }
        }
    }
};