const std = @import("std");
const ts = @import("tree-sitter");
const LineBuilder = @import("../../parsing/formatter.zig").LineBuilder;
const FormatterOptions = @import("../../parsing/formatter.zig").FormatterOptions;
const TypeScriptUtils = @import("typescript_utils.zig").TypeScriptUtils;
const collections = @import("../../core/collections.zig");
const DelimiterTracker = @import("../../text/delimiters.zig").DelimiterTracker;
const processing = @import("../../text/processing.zig");

/// TypeScript-specific formatting helpers - Consolidated from all format modules
pub const TypeScriptFormattingHelpers = struct {

    /// Format TypeScript interface with proper spacing
    pub fn formatInterface(allocator: std.mem.Allocator, builder: *LineBuilder, interface_text: []const u8, options: FormatterOptions) !void {
        // Find the interface name and body
        if (std.mem.indexOf(u8, interface_text, "{")) |brace_pos| {
            const signature = std.mem.trim(u8, interface_text[0..brace_pos], " \t");
            try TypeScriptUtils.formatDeclarationWithSpacing(signature, builder);
            
            const body_end = std.mem.lastIndexOf(u8, interface_text, "}") orelse interface_text.len;
            const body = std.mem.trim(u8, interface_text[brace_pos + 1..body_end], " \t\n\r");
            
            try builder.append(" {");
            try builder.newline();
            
            if (body.len > 0) {
                builder.indent();
                try formatInterfaceBody(allocator, builder, body, options);
                builder.dedent();
            }
            
            try builder.appendIndent();
            try builder.append("}");
        }
    }

    /// Format interface body with properties
    fn formatInterfaceBody(allocator: std.mem.Allocator, builder: *LineBuilder, body: []const u8, options: FormatterOptions) !void {
        const properties = try TypeScriptUtils.splitByDelimiter(allocator, body, ';');
        defer allocator.free(properties);

        for (properties) |property| {
            const trimmed = std.mem.trim(u8, property, " \t\n\r");
            if (trimmed.len > 0) {
                try builder.appendIndent();
                try formatInterfaceProperty(trimmed, builder, options);
                try builder.append(";");
                try builder.newline();
            }
        }
    }

    /// Format single interface property with type annotation
    fn formatInterfaceProperty(property: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
        _ = options;
        
        // Check if this is a method signature
        if (std.mem.indexOf(u8, property, "(") != null and std.mem.indexOf(u8, property, ")") != null) {
            try formatInterfaceMethodSignature(property, builder);
        } else {
            try TypeScriptUtils.formatFieldDeclaration(property, builder);
        }
    }

    /// Format method signature in interface
    fn formatInterfaceMethodSignature(method: []const u8, builder: *LineBuilder) !void {
        // Find parameter section
        if (std.mem.indexOf(u8, method, "(")) |paren_start| {
            if (std.mem.lastIndexOf(u8, method, ")")) |paren_end| {
                const method_name = std.mem.trim(u8, method[0..paren_start], " \t");
                const params = method[paren_start + 1..paren_end];
                const return_type = if (paren_end + 1 < method.len) std.mem.trim(u8, method[paren_end + 1..], " \t") else "";
                
                try builder.append(method_name);
                try builder.append("(");
                
                if (params.len > 0) {
                    try formatTypeScriptParameters(params, builder);
                }
                
                try builder.append(")");
                
                if (return_type.len > 0) {
                    try builder.append(return_type);
                }
            }
        }
    }

    /// Format TypeScript parameters with type annotations
    fn formatTypeScriptParameters(params: []const u8, builder: *LineBuilder) !void {
        var param_iter = std.mem.splitSequence(u8, params, ",");
        var first = true;
        
        while (param_iter.next()) |param| {
            const trimmed = std.mem.trim(u8, param, " \t");
            if (trimmed.len > 0) {
                if (!first) {
                    try builder.append(", ");
                }
                try TypeScriptUtils.formatFieldDeclaration(trimmed, builder);
                first = false;
            }
        }
    }

    /// Format arrow function with proper spacing
    pub fn formatArrowFunction(allocator: std.mem.Allocator, builder: *LineBuilder, arrow_fn: []const u8, options: FormatterOptions) !void {
        // Split by => to get parameters and body
        if (std.mem.indexOf(u8, arrow_fn, "=>")) |arrow_pos| {
            const params_part = std.mem.trim(u8, arrow_fn[0..arrow_pos], " \t");
            const body_part = std.mem.trim(u8, arrow_fn[arrow_pos + 2..], " \t");
            
            // Format parameters
            if (std.mem.startsWith(u8, params_part, "(") and std.mem.endsWith(u8, params_part, ")")) {
                const params = params_part[1..params_part.len-1];
                try TypeScriptUtils.formatParameterList(allocator, builder, params, options);
            } else {
                try builder.append(params_part);
            }
            
            try builder.append(" => ");
            
            // Format body
            if (std.mem.startsWith(u8, body_part, "{")) {
                try formatArrowFunctionBody(allocator, builder, body_part, options);
            } else {
                try builder.append(body_part);
            }
        }
    }

    /// Format arrow function body
    fn formatArrowFunctionBody(allocator: std.mem.Allocator, builder: *LineBuilder, body: []const u8, options: FormatterOptions) !void {
        _ = allocator;
        _ = options;
        
        if (std.mem.startsWith(u8, body, "{") and std.mem.endsWith(u8, body, "}")) {
            const content = std.mem.trim(u8, body[1..body.len-1], " \t\n\r");
            
            try builder.append("{");
            if (content.len > 0) {
                try builder.newline();
                builder.indent();
                try builder.appendIndent();
                try TypeScriptUtils.formatDeclarationWithSpacing(content, builder);
                try builder.newline();
                builder.dedent();
                try builder.appendIndent();
            }
            try builder.append("}");
        } else {
            try builder.append(body);
        }
    }

    /// Format class declaration with members
    pub fn formatClass(allocator: std.mem.Allocator, builder: *LineBuilder, class_text: []const u8, options: FormatterOptions) !void {
        if (std.mem.indexOf(u8, class_text, "{")) |brace_pos| {
            const signature = std.mem.trim(u8, class_text[0..brace_pos], " \t");
            try TypeScriptUtils.formatDeclarationWithSpacing(signature, builder);
            
            const body_end = std.mem.lastIndexOf(u8, class_text, "}") orelse class_text.len;
            const body = std.mem.trim(u8, class_text[brace_pos + 1..body_end], " \t\n\r");
            
            try builder.append(" {");
            try builder.newline();
            
            if (body.len > 0) {
                builder.indent();
                try formatClassBody(allocator, builder, body, options);
                builder.dedent();
            }
            
            try builder.appendIndent();
            try builder.append("}");
        }
    }

    /// Format class body with members
    fn formatClassBody(allocator: std.mem.Allocator, builder: *LineBuilder, body: []const u8, options: FormatterOptions) !void {
        // Parse class members (properties and methods)
        const members = try parseClassMembers(allocator, body);
        defer {
            for (members) |member| {
                allocator.free(member);
            }
            allocator.free(members);
        }

        for (members, 0..) |member, i| {
            try builder.appendIndent();
            
            if (std.mem.indexOf(u8, member, "(") != null and std.mem.indexOf(u8, member, ")") != null) {
                // This is a method
                try formatClassMethod(allocator, builder, member, options);
                // Add blank line after methods
                if (i < members.len - 1) {
                    try builder.newline();
                    try builder.newline();
                }
            } else {
                // This is a property
                try TypeScriptUtils.formatFieldDeclaration(member, builder);
                try builder.append(";");
                try builder.newline();
            }
        }
    }

    /// Parse class content into individual members
    fn parseClassMembers(allocator: std.mem.Allocator, content: []const u8) ![][]const u8 {
        var members = std.ArrayList([]const u8).init(allocator);
        defer members.deinit();

        var start: usize = 0;
        var brace_depth: i32 = 0;
        var in_string: bool = false;
        var string_char: u8 = 0;

        for (content, 0..) |char, i| {
            // Handle string boundaries
            if (!in_string and (char == '"' or char == '\'')) {
                in_string = true;
                string_char = char;
            } else if (in_string and char == string_char) {
                in_string = false;
            }

            if (!in_string) {
                switch (char) {
                    '{' => brace_depth += 1,
                    '}' => {
                        brace_depth -= 1;
                        if (brace_depth == 0) {
                            // End of method
                            const member = std.mem.trim(u8, content[start..i+1], " \t\n\r");
                            if (member.len > 0) {
                                try members.append(try allocator.dupe(u8, member));
                            }
                            start = i + 1;
                        }
                    },
                    ';' => {
                        if (brace_depth == 0) {
                            // End of property
                            const member = std.mem.trim(u8, content[start..i], " \t\n\r");
                            if (member.len > 0) {
                                try members.append(try allocator.dupe(u8, member));
                            }
                            start = i + 1;
                        }
                    },
                    else => {},
                }
            }
        }

        // Handle final member
        if (start < content.len) {
            const member = std.mem.trim(u8, content[start..], " \t\n\r");
            if (member.len > 0) {
                try members.append(try allocator.dupe(u8, member));
            }
        }

        return members.toOwnedSlice();
    }

    /// Format class method
    fn formatClassMethod(allocator: std.mem.Allocator, builder: *LineBuilder, method: []const u8, options: FormatterOptions) !void {
        if (std.mem.indexOf(u8, method, "{")) |brace_pos| {
            const signature = std.mem.trim(u8, method[0..brace_pos], " \t");
            try TypeScriptUtils.formatFunctionSignature(allocator, builder, signature, options);
            
            const body_end = std.mem.lastIndexOf(u8, method, "}") orelse method.len;
            const body = std.mem.trim(u8, method[brace_pos + 1..body_end], " \t\n\r");
            
            try builder.append(" {");
            if (body.len > 0) {
                try builder.newline();
                builder.indent();
                try builder.appendIndent();
                try TypeScriptUtils.formatDeclarationWithSpacing(body, builder);
                try builder.newline();
                builder.dedent();
                try builder.appendIndent();
            }
            try builder.append("}");
        }
    }

    /// Format import/export statements
    pub fn formatImportExport(import_text: []const u8, builder: *LineBuilder) !void {
        // Add proper spacing around keywords and braces
        const keywords = [_][]const u8{ "import", "from", "export", "default", "as" };
        const formatted = try formatKeywordSpacing(builder.allocator, import_text, &keywords);
        defer builder.allocator.free(formatted);
        
        try builder.append(formatted);
    }

    /// Add proper spacing around keywords
    fn formatKeywordSpacing(allocator: std.mem.Allocator, text: []const u8, keywords: []const []const u8) ![]const u8 {
        var result = std.ArrayList(u8).init(allocator);
        defer result.deinit();

        var i: usize = 0;
        while (i < text.len) {
            var found_keyword: ?[]const u8 = null;
            var keyword_len: usize = 0;

            // Check for keywords at current position
            for (keywords) |keyword| {
                if (i + keyword.len <= text.len and std.mem.eql(u8, text[i..i + keyword.len], keyword)) {
                    // Make sure it's a word boundary
                    const is_word_start = i == 0 or !std.ascii.isAlphanumeric(text[i-1]);
                    const is_word_end = i + keyword.len == text.len or !std.ascii.isAlphanumeric(text[i + keyword.len]);
                    
                    if (is_word_start and is_word_end) {
                        found_keyword = keyword;
                        keyword_len = keyword.len;
                        break;
                    }
                }
            }

            if (found_keyword) |keyword| {
                // Add space before keyword if needed
                if (result.items.len > 0 and result.items[result.items.len - 1] != ' ') {
                    try result.append(' ');
                }
                
                try result.appendSlice(keyword);
                
                // Add space after keyword if needed
                if (i + keyword_len < text.len and text[i + keyword_len] != ' ') {
                    try result.append(' ');
                }
                
                i += keyword_len;
            } else {
                try result.append(text[i]);
                i += 1;
            }
        }

        return result.toOwnedSlice();
    }

    /// Format method chaining with proper line breaks
    pub fn formatMethodChaining(allocator: std.mem.Allocator, builder: *LineBuilder, chain_text: []const u8, options: FormatterOptions) !void {
        try TypeScriptUtils.formatMethodChain(allocator, builder, chain_text, options);
    }

    /// Check if TypeScript code is a function declaration
    pub fn isFunctionDeclaration(text: []const u8) bool {
        const trimmed = std.mem.trim(u8, text, " \t\n\r");
        return std.mem.startsWith(u8, trimmed, "function ") or
               std.mem.startsWith(u8, trimmed, "async function ") or
               std.mem.startsWith(u8, trimmed, "export function ");
    }

    /// Check if TypeScript code is a type declaration
    pub fn isTypeDeclaration(text: []const u8) bool {
        const trimmed = std.mem.trim(u8, text, " \t\n\r");
        return std.mem.startsWith(u8, trimmed, "interface ") or
               std.mem.startsWith(u8, trimmed, "type ") or
               std.mem.startsWith(u8, trimmed, "class ") or
               std.mem.startsWith(u8, trimmed, "enum ");
    }

    // === NEW CONSOLIDATED HELPERS ===

    /// Format text with proper TypeScript spacing for all operators and punctuation
    /// Consolidates spacing logic from format_function, format_class, format_interface, etc.
    pub fn formatWithTypeScriptSpacing(text: []const u8, builder: *LineBuilder) !void {
        var tracker = DelimiterTracker{};
        var i: usize = 0;
        var escape_next = false;
        var in_comment = false;
        var in_template = false;
        var template_depth: u32 = 0;

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
                if (c == '{' and i > 0 and text[i - 1] == '$') {
                    template_depth += 1;
                } else if (c == '}' and template_depth > 1) {
                    template_depth -= 1;
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

            // Handle colon spacing (TypeScript style: no space before, space after)
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
                // Check for == or === operators
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
                    
                    // Ensure space after operator if next char isn't space
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

            // Handle union and intersection types (| and &)
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

    /// Split parameters/fields by comma while preserving strings and nested structures
    /// Enhanced version that uses DelimiterTracker for reliability
    pub fn splitByCommaPreservingStructure(allocator: std.mem.Allocator, text: []const u8) ![][]const u8 {
        var result = collections.List([]const u8).init(allocator);
        defer result.deinit();
        
        var start: usize = 0;
        var i: usize = 0;
        var tracker = DelimiterTracker{};
        var in_template = false;
        var template_depth: u32 = 0;
        
        while (i < text.len) {
            const c = text[i];
            
            // Handle template literals
            if (!tracker.in_string and c == '`') {
                in_template = !in_template;
                if (in_template) {
                    template_depth = 1;
                } else {
                    template_depth = 0;
                }
                i += 1;
                continue;
            }
            
            if (in_template) {
                if (c == '{' and i > 0 and text[i - 1] == '$') {
                    template_depth += 1;
                } else if (c == '}' and template_depth > 1) {
                    template_depth -= 1;
                }
                i += 1;
                continue;
            }
            
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

    /// Format property with TypeScript-style spacing (properties and interface members)
    /// Consolidates property formatting from format_class and format_interface
    pub fn formatPropertyWithSpacing(property: []const u8, builder: *LineBuilder) !void {
        var i: usize = 0;
        var in_string = false;
        var string_char: u8 = 0;
        var escape_next = false;
        var in_generic = false;
        var generic_depth: u32 = 0;

        while (i < property.len) {
            const c = property[i];

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
                
                // Skip any existing spaces after colon
                while (i < property.len and property[i] == ' ') {
                    i += 1;
                }
                
                // Check if this is followed by an object literal type
                if (i < property.len and property[i] == '{') {
                    // Add space before the opening brace
                    try builder.append(" ");
                    // Find the matching closing brace for the object literal
                    var brace_depth: u32 = 0;
                    const obj_start = i;
                    var obj_end = i;
                    var in_obj_string = false;
                    var obj_string_char: u8 = 0;
                    
                    while (obj_end < property.len) {
                        const obj_c = property[obj_end];
                        
                        if (!in_obj_string and (obj_c == '"' or obj_c == '\'' or obj_c == '`')) {
                            in_obj_string = true;
                            obj_string_char = obj_c;
                        } else if (in_obj_string and obj_c == obj_string_char) {
                            in_obj_string = false;
                        } else if (!in_obj_string) {
                            if (obj_c == '{') {
                                brace_depth += 1;
                            } else if (obj_c == '}') {
                                brace_depth -= 1;
                                if (brace_depth == 0) {
                                    obj_end += 1;
                                    break;
                                }
                            }
                        }
                        obj_end += 1;
                    }
                    
                    // Format the object literal with proper indentation
                    try formatObjectLiteral(property[obj_start..obj_end], builder);
                    i = obj_end;
                    continue;
                } else {
                    // Regular type after colon - add space
                    try builder.append(" ");
                }
                continue;
            }

            if (c == '=') {
                // Ensure space around assignment
                if (builder.buffer.items.len > 0 and 
                    builder.buffer.items[builder.buffer.items.len - 1] != ' ') {
                    try builder.append(" ");
                }
                try builder.append("=");
                i += 1;
                
                // Ensure space after equals
                if (i < property.len and property[i] != ' ') {
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
                if (i < property.len and property[i] != ' ') {
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

    /// Format object literal type with proper indentation
    /// Handles nested object types like { bio: string; avatar?: string; }
    fn formatObjectLiteral(obj_content: []const u8, builder: *LineBuilder) !void {
        if (obj_content.len < 2) return; // Need at least "{}"
        
        // Extract content between braces
        const content = std.mem.trim(u8, obj_content[1..obj_content.len-1], " \t\n\r");
        if (content.len == 0) {
            try builder.append("{}");
            return;
        }
        
        // Check if content has multiple properties (contains semicolons)
        if (std.mem.indexOf(u8, content, ";") != null) {
            // Multi-property object - format with newlines
            try builder.append("{");
            try builder.newline();
            builder.indent();
            
            // Split by semicolons and format each property
            var properties = std.mem.splitSequence(u8, content, ";");
            while (properties.next()) |prop| {
                const prop_trimmed = std.mem.trim(u8, prop, " \t\n\r");
                if (prop_trimmed.len > 0) {
                    try builder.appendIndent();
                    try formatSimpleProperty(prop_trimmed, builder);
                    try builder.append(";");
                    try builder.newline();
                }
            }
            
            builder.dedent();
            try builder.appendIndent();
            try builder.append("}");
        } else {
            // Single property or simple object - format inline
            try builder.append("{ ");
            try formatSimpleProperty(content, builder);
            try builder.append(" }");
        }
    }

    /// Format simple property without object literal handling (to avoid recursion)
    /// Basic spacing for property: type patterns like "name: string" or "email?: string"
    fn formatSimpleProperty(property: []const u8, builder: *LineBuilder) !void {
        var i: usize = 0;
        while (i < property.len) {
            const c = property[i];
            
            if (c == ':') {
                // TypeScript style: no space before colon, space after colon
                try builder.append(":");
                i += 1;
                // Skip any existing spaces and add one space
                while (i < property.len and property[i] == ' ') {
                    i += 1;
                }
                if (i < property.len) {
                    try builder.append(" ");
                }
                continue;
            }
            
            if (c == '?') {
                // Optional property marker
                try builder.append("?");
                i += 1;
                continue;
            }
            
            if (c == ' ') {
                // Space normalization
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

    /// Format generic parameters with proper spacing
    /// Consolidates generic parameter handling from format_class and format_interface
    pub fn formatGenericParameters(type_params: []const u8, builder: *LineBuilder) !void {
        var i: usize = 0;
        var in_string = false;
        var string_char: u8 = 0;
        var prev_was_space = false;
        
        while (i < type_params.len) {
            const c = type_params[i];
            
            if (!in_string and (c == '"' or c == '\'' or c == '`')) {
                in_string = true;
                string_char = c;
                try builder.append(&[_]u8{c});
                prev_was_space = false;
            } else if (in_string and c == string_char) {
                in_string = false;
                try builder.append(&[_]u8{c});
                prev_was_space = false;
            } else if (in_string) {
                try builder.append(&[_]u8{c});
                prev_was_space = false;
            } else if (c == ',') {
                try builder.append(",");
                // Add space after comma
                if (i + 1 < type_params.len and type_params[i + 1] != ' ') {
                    try builder.append(" ");
                }
                prev_was_space = true;
            } else if (c == ' ') {
                if (!prev_was_space) {
                    try builder.append(" ");
                    prev_was_space = true;
                }
            } else {
                try builder.append(&[_]u8{c});
                prev_was_space = false;
            }
            
            i += 1;
        }
    }

    /// Format method signature with proper parameter handling
    /// Consolidates method signature formatting from format_function and format_class
    pub fn formatMethodSignature(allocator: std.mem.Allocator, signature: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
        // Find parameter section
        if (std.mem.indexOf(u8, signature, "(")) |paren_start| {
            if (std.mem.lastIndexOf(u8, signature, ")")) |paren_end| {
                // Extract parts
                const method_name_part = std.mem.trim(u8, signature[0..paren_start], " \t");
                const params_part = signature[paren_start + 1..paren_end];
                const return_part = if (paren_end + 1 < signature.len) std.mem.trim(u8, signature[paren_end + 1..], " \t") else "";
                
                // Format method name part with proper spacing
                try formatWithTypeScriptSpacing(method_name_part, builder);
                
                // Format parameters
                try formatParameterList(allocator, params_part, builder, options);
                
                // Format return type
                if (return_part.len > 0) {
                    if (!std.mem.startsWith(u8, return_part, ":")) {
                        try builder.append(" ");
                    }
                    try formatWithTypeScriptSpacing(return_part, builder);
                }
                
                return;
            }
        }
        
        // Fallback - basic formatting without parameter parsing
        try formatWithTypeScriptSpacing(signature, builder);
    }

    /// Format parameter list with multiline/single line support
    /// Consolidates parameter formatting from format_function and format_parameter
    pub fn formatParameterList(allocator: std.mem.Allocator, params: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
        try builder.append("(");
        
        if (params.len == 0) {
            try builder.append(")");
            return;
        }
        
        // Use consolidated parameter splitting helper
        const param_list = try splitByCommaPreservingStructure(allocator, params);
        defer {
            for (param_list) |param| {
                allocator.free(param);
            }
            allocator.free(param_list);
        }
        
        // Calculate current line length
        var current_line_length: usize = 0;
        if (builder.buffer.items.len > 0) {
            if (std.mem.lastIndexOf(u8, builder.buffer.items, "\n")) |last_newline| {
                current_line_length = builder.buffer.items.len - last_newline - 1;
            } else {
                current_line_length = builder.buffer.items.len;
            }
        }
        
        // Check if we need multiline formatting
        var total_length: usize = current_line_length;
        for (param_list) |param| {
            total_length += param.len + 2; // +2 for ", "
        }
        total_length += 1; // +1 for closing parenthesis
        
        const use_multiline = total_length > options.line_width or 
                              std.mem.indexOf(u8, params, "\n") != null;
        
        if (use_multiline) {
            try builder.newline();
            builder.indent();
            
            for (param_list, 0..) |param, i| {
                try builder.appendIndent();
                try formatPropertyWithSpacing(param, builder);
                if (i < param_list.len - 1 or options.trailing_comma) {
                    try builder.append(",");
                }
                try builder.newline();
            }
            
            builder.dedent();
            try builder.appendIndent();
        } else {
            for (param_list, 0..) |param, i| {
                if (i > 0) {
                    try builder.append(", ");
                }
                try formatPropertyWithSpacing(param, builder);
            }
        }
        
        try builder.append(")");
    }

    /// Classify TypeScript declaration type for consistent handling
    /// Consolidates type checking from multiple format modules
    pub const TypeScriptDeclarationType = enum {
        function,
        arrow_function,
        class,
        interface,
        type_alias,
        enum_type,
        import_decl,
        export_decl,
        variable,
        constant,
        unknown,
    };

    pub fn classifyTypeScriptDeclaration(text: []const u8) TypeScriptDeclarationType {
        const trimmed = std.mem.trim(u8, text, " \t\n\r");
        
        // Check for arrow functions first (most specific)
        if (std.mem.indexOf(u8, trimmed, "=>") != null) {
            return .arrow_function;
        }
        
        // Check for imports/exports
        if (std.mem.startsWith(u8, trimmed, "import ") or
            std.mem.startsWith(u8, trimmed, "export ")) {
            if (std.mem.indexOf(u8, trimmed, "import") != null) {
                return .import_decl;
            } else {
                return .export_decl;
            }
        }
        
        // Check for function declarations
        if (std.mem.startsWith(u8, trimmed, "function ") or 
            std.mem.startsWith(u8, trimmed, "async function ") or
            std.mem.startsWith(u8, trimmed, "export function ")) {
            return .function;
        }
        
        // Check for type declarations
        if (std.mem.startsWith(u8, trimmed, "interface ") or
            std.mem.startsWith(u8, trimmed, "export interface ")) {
            return .interface;
        }
        
        if (std.mem.startsWith(u8, trimmed, "type ") or
            std.mem.startsWith(u8, trimmed, "export type ")) {
            return .type_alias;
        }
        
        if (std.mem.startsWith(u8, trimmed, "class ") or
            std.mem.startsWith(u8, trimmed, "export class ") or
            std.mem.startsWith(u8, trimmed, "abstract class ")) {
            return .class;
        }
        
        if (std.mem.startsWith(u8, trimmed, "enum ") or
            std.mem.startsWith(u8, trimmed, "export enum ")) {
            return .enum_type;
        }
        
        // Check for variables and constants
        if (std.mem.startsWith(u8, trimmed, "const ") or
            std.mem.startsWith(u8, trimmed, "export const ")) {
            return .constant;
        }
        
        if (std.mem.startsWith(u8, trimmed, "let ") or
            std.mem.startsWith(u8, trimmed, "var ") or
            std.mem.startsWith(u8, trimmed, "export let ") or
            std.mem.startsWith(u8, trimmed, "export var ")) {
            return .variable;
        }
        
        return .unknown;
    }

    /// Extract declaration name from any TypeScript declaration pattern
    /// Consolidates name extraction from format modules
    pub fn extractDeclarationName(text: []const u8) ?[]const u8 {
        const trimmed = std.mem.trim(u8, text, " \t\n\r");
        
        // Handle various declaration patterns
        var start_pos: usize = 0;
        
        if (std.mem.startsWith(u8, trimmed, "export ")) {
            start_pos = 7; // length of "export "
        }
        
        const remaining = trimmed[start_pos..];
        
        if (std.mem.startsWith(u8, remaining, "const ")) {
            start_pos += 6; // length of "const "
        } else if (std.mem.startsWith(u8, remaining, "let ")) {
            start_pos += 4; // length of "let "
        } else if (std.mem.startsWith(u8, remaining, "var ")) {
            start_pos += 4; // length of "var "
        } else if (std.mem.startsWith(u8, remaining, "function ")) {
            start_pos += 9; // length of "function "
        } else if (std.mem.startsWith(u8, remaining, "async function ")) {
            start_pos += 15; // length of "async function "
        } else if (std.mem.startsWith(u8, remaining, "class ")) {
            start_pos += 6; // length of "class "
        } else if (std.mem.startsWith(u8, remaining, "abstract class ")) {
            start_pos += 15; // length of "abstract class "
        } else if (std.mem.startsWith(u8, remaining, "interface ")) {
            start_pos += 10; // length of "interface "
        } else if (std.mem.startsWith(u8, remaining, "type ")) {
            start_pos += 5; // length of "type "
        } else if (std.mem.startsWith(u8, remaining, "enum ")) {
            start_pos += 5; // length of "enum "
        } else {
            return null;
        }
        
        // Find the end of the name (before "=", "(", ":", "<", or "{")
        var end_pos: usize = trimmed.len;
        const delimiters = [_][]const u8{ " =", "(", ":", "<", "{", " extends", " implements", " " };
        
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
};