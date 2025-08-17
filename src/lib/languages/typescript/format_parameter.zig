const std = @import("std");
const LineBuilder = @import("../../parsing/formatter.zig").LineBuilder;
const FormatterOptions = @import("../../parsing/formatter.zig").FormatterOptions;
const TypeScriptHelpers = @import("formatting_helpers.zig").TypeScriptFormattingHelpers;
const TypeScriptSpacing = @import("spacing_helpers.zig").TypeScriptSpacingHelpers;

pub const FormatParameter = struct {
    /// Format TypeScript parameter using consolidated helpers
    pub fn formatSingleParameter(param: []const u8, builder: *LineBuilder) !void {
        try TypeScriptHelpers.formatPropertyWithSpacing(param, builder);
    }

    /// Format parameter list using consolidated helpers
    pub fn formatParameterList(params: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
        // Remove outer parentheses if present
        var content = params;
        if (std.mem.startsWith(u8, content, "(") and std.mem.endsWith(u8, content, ")")) {
            content = content[1..content.len-1];
        }

        // Use consolidated parameter list formatter
        try TypeScriptHelpers.formatParameterList(builder.allocator, content, builder, options);
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