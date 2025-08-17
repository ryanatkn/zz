const std = @import("std");
const LineBuilder = @import("../../parsing/formatter.zig").LineBuilder;
const FormatterOptions = @import("../../parsing/formatter.zig").FormatterOptions;

pub const TypeScriptParameterFormatter = struct {
    /// Format TypeScript parameter with proper spacing (space before and after colon)
    pub fn formatSingleParameter(param: []const u8, builder: *LineBuilder) !void {
        var i: usize = 0;
        var in_string = false;
        var string_char: u8 = 0;
        var escape_next = false;
        var in_generic = false;
        var generic_depth: u32 = 0;

        while (i < param.len) {
            const c = param[i];

            if (escape_next) {
                try builder.append(&[_]u8{c});
                escape_next = false;
                i += 1;
                continue;
            }

            if (c == '\\' and in_string) {
                escape_next = true;
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            if (!in_string and (c == '"' or c == '\'' or c == '`')) {
                in_string = true;
                string_char = c;
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            if (in_string and c == string_char) {
                in_string = false;
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            if (in_string) {
                try builder.append(&[_]u8{c});
                i += 1;
                continue;
            }

            // Track generic type parameters
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
                // TypeScript style: no space before colon, space after colon
                try builder.append(":");
                i += 1;
                
                // Ensure space after colon if next char isn't space
                if (i < param.len and param[i] != ' ') {
                    try builder.append(" ");
                }
                continue;
            }

            if (c == '=') {
                // Ensure space around default value assignment
                if (builder.buffer.items.len > 0 and 
                    builder.buffer.items[builder.buffer.items.len - 1] != ' ') {
                    try builder.append(" ");
                }
                try builder.append("=");
                i += 1;
                
                // Ensure space after equals
                if (i < param.len and param[i] != ' ') {
                    try builder.append(" ");
                }
                continue;
            }

            if (c == '|' or c == '&') {
                // Ensure space around union and intersection types
                if (builder.buffer.items.len > 0 and 
                    builder.buffer.items[builder.buffer.items.len - 1] != ' ') {
                    try builder.append(" ");
                }
                try builder.append(&[_]u8{c});
                i += 1;
                
                // Ensure space after operator
                if (i < param.len and param[i] != ' ') {
                    try builder.append(" ");
                }
                continue;
            }

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

    /// Format parameter list with proper comma spacing
    pub fn formatParameterList(params: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
        // Remove outer parentheses if present
        var content = params;
        if (std.mem.startsWith(u8, content, "(") and std.mem.endsWith(u8, content, ")")) {
            content = content[1..content.len-1];
        }

        if (content.len == 0) {
            try builder.append("()");
            return;
        }

        try builder.append("(");

        // Check if we need multiline formatting
        if (content.len > options.line_width or std.mem.indexOf(u8, content, "\n") != null) {
            try formatParametersMultiline(content, builder, options);
        } else {
            try formatParametersSingleLine(content, builder);
        }

        try builder.append(")");
    }

    /// Format parameters in multiline style
    fn formatParametersMultiline(params: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
        try builder.newline();
        builder.indent();
        
        var param_start: usize = 0;
        var depth: i32 = 0;
        var in_string: bool = false;
        var string_char: u8 = 0;
        
        for (params, 0..) |char, i| {
            // Track string boundaries
            if (!in_string and (char == '\'' or char == '"' or char == '`')) {
                in_string = true;
                string_char = char;
            } else if (in_string and char == string_char) {
                in_string = false;
            }
            
            // Skip processing inside strings
            if (in_string) continue;
            
            // Track parentheses and angle bracket depth for nested types
            if (char == '(' or char == '<') {
                depth += 1;
            } else if (char == ')' or char == '>') {
                depth -= 1;
            } else if (char == ',' and depth == 0) {
                // Found parameter boundary
                const param = std.mem.trim(u8, params[param_start..i], " \t\n");
                if (param.len > 0) {
                    try builder.appendIndent();
                    try formatSingleParameter(param, builder);
                    try builder.append(",");
                    try builder.newline();
                }
                param_start = i + 1;
            }
        }
        
        // Handle last parameter
        const last_param = std.mem.trim(u8, params[param_start..], " \t\n");
        if (last_param.len > 0) {
            try builder.appendIndent();
            try formatSingleParameter(last_param, builder);
            if (options.trailing_comma) {
                try builder.append(",");
            }
            try builder.newline();
        }
        
        builder.dedent();
        try builder.appendIndent();
    }

    /// Format parameters in single line style
    fn formatParametersSingleLine(params: []const u8, builder: *LineBuilder) !void {
        var param_start: usize = 0;
        var depth: i32 = 0;
        var in_string: bool = false;
        var string_char: u8 = 0;
        var first_param = true;
        
        for (params, 0..) |char, i| {
            // Track string boundaries
            if (!in_string and (char == '\'' or char == '"' or char == '`')) {
                in_string = true;
                string_char = char;
            } else if (in_string and char == string_char) {
                in_string = false;
            }
            
            // Skip processing inside strings
            if (in_string) continue;
            
            // Track parentheses and angle bracket depth for nested types
            if (char == '(' or char == '<') {
                depth += 1;
            } else if (char == ')' or char == '>') {
                depth -= 1;
            } else if (char == ',' and depth == 0) {
                // Found parameter boundary
                const param = std.mem.trim(u8, params[param_start..i], " \t\n");
                if (param.len > 0) {
                    if (!first_param) {
                        try builder.append(", ");
                    }
                    try formatSingleParameter(param, builder);
                    first_param = false;
                }
                param_start = i + 1;
            }
        }
        
        // Handle last parameter
        const last_param = std.mem.trim(u8, params[param_start..], " \t\n");
        if (last_param.len > 0) {
            if (!first_param) {
                try builder.append(", ");
            }
            try formatSingleParameter(last_param, builder);
        }
    }

    /// Check if parameter has default value
    pub fn hasDefaultValue(param: []const u8) bool {
        return std.mem.indexOf(u8, param, "=") != null;
    }

    /// Check if parameter is optional (ends with ?)
    pub fn isOptional(param: []const u8) bool {
        // Look for ? before : or =
        if (std.mem.indexOf(u8, param, ":")) |colon_pos| {
            const before_colon = param[0..colon_pos];
            return std.mem.endsWith(u8, std.mem.trim(u8, before_colon, " \t"), "?");
        }
        return std.mem.indexOf(u8, param, "?") != null;
    }

    /// Check if parameter is a rest parameter (...param)
    pub fn isRestParameter(param: []const u8) bool {
        return std.mem.startsWith(u8, std.mem.trim(u8, param, " \t"), "...");
    }

    /// Extract parameter name from declaration
    pub fn extractParameterName(param: []const u8) ?[]const u8 {
        const trimmed = std.mem.trim(u8, param, " \t");
        
        // Handle rest parameters
        var param_text = trimmed;
        if (std.mem.startsWith(u8, param_text, "...")) {
            param_text = param_text[3..];
        }
        
        // Find the parameter name (before : or = or ?)
        var end_pos: usize = param_text.len;
        
        if (std.mem.indexOf(u8, param_text, ":")) |colon_pos| {
            end_pos = colon_pos;
        }
        
        if (std.mem.indexOf(u8, param_text, "=")) |equals_pos| {
            if (equals_pos < end_pos) {
                end_pos = equals_pos;
            }
        }
        
        var name = std.mem.trim(u8, param_text[0..end_pos], " \t");
        
        // Remove optional marker
        if (std.mem.endsWith(u8, name, "?")) {
            name = name[0..name.len-1];
        }
        
        name = std.mem.trim(u8, name, " \t");
        
        if (name.len > 0) {
            return name;
        }
        
        return null;
    }

    /// Extract parameter type from declaration
    pub fn extractParameterType(param: []const u8) ?[]const u8 {
        if (std.mem.indexOf(u8, param, ":")) |colon_pos| {
            const after_colon = param[colon_pos + 1..];
            
            // Find the end of type (before = for default value)
            var type_end = after_colon.len;
            if (std.mem.indexOf(u8, after_colon, "=")) |equals_pos| {
                type_end = equals_pos;
            }
            
            const type_text = std.mem.trim(u8, after_colon[0..type_end], " \t");
            if (type_text.len > 0) {
                return type_text;
            }
        }
        
        return null;
    }
};