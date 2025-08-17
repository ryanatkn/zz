const std = @import("std");
const LineBuilder = @import("../../parsing/formatter.zig").LineBuilder;
const FormatterOptions = @import("../../parsing/formatter.zig").FormatterOptions;
const ZigUtils = @import("zig_utils.zig").ZigUtils;
const ZigSpacingHelpers = @import("spacing_helpers.zig").ZigSpacingHelpers;
const ZigFormattingHelpers = @import("formatting_helpers.zig").ZigFormattingHelpers;

/// Zig-specific parameter formatting functionality
pub const FormatParameter = struct {

    /// Format a single Zig parameter with proper colon spacing
    pub fn formatSingleParameter(param: []const u8, builder: *LineBuilder) !void {
        // Use consolidated colon spacing helper
        try ZigSpacingHelpers.formatColonSpacing(param, builder);
    }

    /// Format Zig parameter list with proper spacing and multiline handling
    pub fn formatParameterList(allocator: std.mem.Allocator, builder: *LineBuilder, params_text: []const u8, options: FormatterOptions) !void {
        if (params_text.len == 0) {
            try builder.append("()");
            return;
        }

        // Use consolidated parameter splitting helper
        const params = try ZigFormattingHelpers.splitByCommaPreservingStructure(allocator, params_text);
        defer allocator.free(params);

        // Calculate total length for multiline decision
        var total_length: u32 = 2; // For parentheses
        for (params) |param| {
            total_length += @intCast(param.len + 2); // +2 for ", "
        }

        const use_multiline = total_length > options.line_width;
        
        try builder.append("(");
        
        if (use_multiline) {
            try builder.newline();
            builder.indent();
            
            for (params, 0..) |param, i| {
                try builder.appendIndent();
                try formatSingleParameter(param, builder);
                if (i < params.len - 1) {
                    try builder.append(",");
                }
                try builder.newline();
            }
            
            builder.dedent();
            try builder.appendIndent();
        } else {
            for (params, 0..) |param, i| {
                try formatSingleParameter(param, builder);
                if (i < params.len - 1) {
                    try builder.append(", ");
                }
            }
        }
        
        try builder.append(")");
    }

    /// Format comptime parameters with special handling
    pub fn formatComptimeParameters(allocator: std.mem.Allocator, builder: *LineBuilder, params_text: []const u8, options: FormatterOptions) !void {
        _ = options;
        if (params_text.len == 0) {
            try builder.append("()");
            return;
        }

        const params = try ZigFormattingHelpers.splitByCommaPreservingStructure(allocator, params_text);
        defer allocator.free(params);

        // Always use multiline for comptime signatures as they tend to be complex
        const use_multiline = params.len > 1 or std.mem.indexOf(u8, params_text, "comptime") != null;
        
        try builder.append("(");
        
        if (use_multiline) {
            for (params, 0..) |param, i| {
                const trimmed = std.mem.trim(u8, param, " \t");
                if (trimmed.len > 0) {
                    try formatSingleParameter(trimmed, builder);
                    if (i < params.len - 1) {
                        try builder.append(",");
                    }
                    try builder.append(" ");
                }
            }
        } else {
            for (params, 0..) |param, i| {
                try formatSingleParameter(std.mem.trim(u8, param, " \t"), builder);
                if (i < params.len - 1) {
                    try builder.append(", ");
                }
            }
        }
        
        try builder.append(")");
    }

    /// Extract parameter types from function signature
    pub fn extractParameterTypes(allocator: std.mem.Allocator, signature: []const u8) ![][]const u8 {
        // Find parameter section between parentheses
        if (std.mem.indexOf(u8, signature, "(")) |start| {
            if (std.mem.lastIndexOf(u8, signature, ")")) |end| {
                const params_text = signature[start + 1..end];
                const params = try ZigFormattingHelpers.splitByCommaPreservingStructure(allocator, params_text);
                
                var types = std.ArrayList([]const u8).init(allocator);
                defer types.deinit();
                
                for (params) |param| {
                    const trimmed = std.mem.trim(u8, param, " \t");
                    if (std.mem.indexOf(u8, trimmed, ":")) |colon_pos| {
                        const type_part = std.mem.trim(u8, trimmed[colon_pos + 1..], " \t");
                        try types.append(try allocator.dupe(u8, type_part));
                    }
                }
                
                return types.toOwnedSlice();
            }
        }
        
        return &[_][]const u8{};
    }

    /// Check if parameters contain comptime
    pub fn hasComptimeParams(params_text: []const u8) bool {
        return std.mem.indexOf(u8, params_text, "comptime") != null;
    }

    /// Check if parameter list should use multiline format
    pub fn shouldUseMultiline(params_text: []const u8, options: FormatterOptions) bool {
        if (params_text.len == 0) return false;
        
        // Count commas to estimate parameter count
        var comma_count: u32 = 0;
        for (params_text) |char| {
            if (char == ',') comma_count += 1;
        }
        
        // Use multiline if more than 2 parameters or total length exceeds limit
        return comma_count > 1 or params_text.len > options.line_width - 20; // Reserve space for function name and parentheses
    }
};