const std = @import("std");
const ts = @import("tree-sitter");
const LineBuilder = @import("../../parsing/formatter.zig").LineBuilder;
const FormatterOptions = @import("../../parsing/formatter.zig").FormatterOptions;
const TypeScriptUtils = @import("typescript_utils.zig").TypeScriptUtils;

/// TypeScript-specific formatting helpers
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
            try formatMethodSignature(property, builder);
        } else {
            try TypeScriptUtils.formatFieldDeclaration(property, builder);
        }
    }

    /// Format method signature in interface
    fn formatMethodSignature(method: []const u8, builder: *LineBuilder) !void {
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
};