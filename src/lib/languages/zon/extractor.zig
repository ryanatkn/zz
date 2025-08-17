const std = @import("std");
const ZonParser = @import("parser.zig").ZonParser;
const DependencyInfo = @import("parser.zig").DependencyInfo;

/// High-level ZON extraction utilities
/// Provides convenient functions for common ZON extraction tasks

/// Extract all field-value pairs from a ZON struct
pub fn extractAllFields(allocator: std.mem.Allocator, content: []const u8) !std.StringHashMap([]u8) {
    var fields = std.StringHashMap([]u8).init(allocator);
    var lines = std.mem.splitSequence(u8, content, "\n");
    
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;
        if (std.mem.startsWith(u8, trimmed, "//")) continue;
        
        // Look for field patterns: .field = "value" or .@"field" = "value"
        if (extractFieldFromLine(allocator, trimmed)) |field_value| {
            try fields.put(field_value.name, field_value.value);
        }
    }
    
    return fields;
}

/// Extract configuration sections from ZON files
pub fn extractConfigSections(allocator: std.mem.Allocator, content: []const u8) !ConfigSections {
    var parser = ZonParser.init(allocator);
    
    var sections = ConfigSections{
        .dependencies = std.StringHashMap(DependencyInfo).init(allocator),
        .format_config = null,
        .prompt_config = null,
        .tree_config = null,
    };
    
    // Parse dependencies
    sections.dependencies = try parser.parseDependencies(content);
    
    // Extract other common sections
    if (try parser.extractSection(allocator, content, "format")) |format_section| {
        sections.format_config = format_section;
    }
    
    if (try parser.extractSection(allocator, content, "prompt")) |prompt_section| {
        sections.prompt_config = prompt_section;
    }
    
    if (try parser.extractSection(allocator, content, "tree")) |tree_section| {
        sections.tree_config = tree_section;
    }
    
    return sections;
}

/// Free all allocations in ConfigSections
pub fn freeConfigSections(allocator: std.mem.Allocator, sections: *ConfigSections) void {
    var parser = ZonParser.init(allocator);
    parser.freeDependencies(&sections.dependencies);
    
    if (sections.format_config) |config| {
        allocator.free(config);
    }
    if (sections.prompt_config) |config| {
        allocator.free(config);
    }
    if (sections.tree_config) |config| {
        allocator.free(config);
    }
}

/// Extract version and URL from a specific dependency
pub fn extractDependencyInfo(allocator: std.mem.Allocator, content: []const u8, dep_name: []const u8) !?DependencyInfo {
    var parser = ZonParser.init(allocator);
    
    // Get the dependencies section
    const deps_section = try parser.extractSection(allocator, content, "dependencies");
    if (deps_section == null) return null;
    defer allocator.free(deps_section.?);
    
    // Get the specific dependency section
    const dep_section = try parser.extractSection(allocator, deps_section.?, dep_name);
    if (dep_section == null) return null;
    defer allocator.free(dep_section.?);
    
    var info = DependencyInfo{};
    
    // Extract version and URL
    info.version = try parser.extractAnyField(dep_section.?, "version");
    info.url = try parser.extractAnyField(dep_section.?, "url");
    
    return info;
}

/// Validate ZON structure and report errors
pub fn validateZonStructure(content: []const u8) []const ZonValidationError {
    var errors = std.ArrayList(ZonValidationError).init(std.heap.page_allocator);
    defer errors.deinit();
    
    var lines = std.mem.splitSequence(u8, content, "\n");
    var line_number: u32 = 0;
    var brace_count: i32 = 0;
    
    while (lines.next()) |line| {
        line_number += 1;
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;
        if (std.mem.startsWith(u8, trimmed, "//")) continue;
        
        // Track brace balance
        for (trimmed) |c| {
            if (c == '{') brace_count += 1;
            if (c == '}') brace_count -= 1;
        }
        
        // Check for common syntax errors
        if (std.mem.indexOf(u8, trimmed, ".") != null and std.mem.indexOf(u8, trimmed, "=") == null) {
            // Field without assignment
            errors.append(ZonValidationError{
                .line = line_number,
                .type = .MissingAssignment,
                .message = "Field declaration without assignment",
            }) catch {};
        }
        
        if (std.mem.count(u8, trimmed, "\"") % 2 != 0) {
            // Unmatched quotes
            errors.append(ZonValidationError{
                .line = line_number,
                .type = .UnmatchedQuotes,
                .message = "Unmatched quotes in string literal",
            }) catch {};
        }
    }
    
    // Check final brace balance
    if (brace_count != 0) {
        errors.append(ZonValidationError{
            .line = line_number,
            .type = .UnmatchedBraces,
            .message = "Unmatched braces in ZON structure",
        }) catch {};
    }
    
    return errors.toOwnedSlice() catch &.{};
}

/// Count and analyze ZON content statistics
pub fn analyzeZonContent(content: []const u8) ZonAnalysis {
    var analysis = ZonAnalysis{};
    var lines = std.mem.splitSequence(u8, content, "\n");
    
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) {
            analysis.empty_lines += 1;
            continue;
        }
        
        if (std.mem.startsWith(u8, trimmed, "//")) {
            analysis.comment_lines += 1;
            continue;
        }
        
        analysis.content_lines += 1;
        
        // Count fields
        if (std.mem.indexOf(u8, trimmed, ".") != null and std.mem.indexOf(u8, trimmed, "=") != null) {
            analysis.field_count += 1;
        }
        
        // Count structures
        if (std.mem.indexOf(u8, trimmed, "= .{") != null) {
            analysis.struct_count += 1;
        }
    }
    
    return analysis;
}

// Helper structures

pub const ConfigSections = struct {
    dependencies: std.StringHashMap(DependencyInfo),
    format_config: ?[]u8,
    prompt_config: ?[]u8,
    tree_config: ?[]u8,
};

pub const FieldValue = struct {
    name: []u8,
    value: []u8,
};

pub const ZonValidationError = struct {
    line: u32,
    type: ErrorType,
    message: []const u8,
    
    pub const ErrorType = enum {
        UnmatchedBraces,
        UnmatchedQuotes,
        MissingAssignment,
        InvalidSyntax,
    };
};

pub const ZonAnalysis = struct {
    content_lines: u32 = 0,
    comment_lines: u32 = 0,
    empty_lines: u32 = 0,
    field_count: u32 = 0,
    struct_count: u32 = 0,
};

// Helper functions

fn extractFieldFromLine(allocator: std.mem.Allocator, line: []const u8) ?FieldValue {
    // Handle .field = "value"
    if (std.mem.indexOf(u8, line, ".")) |dot_pos| {
        if (std.mem.indexOf(u8, line[dot_pos..], " = \"")) |eq_pos| {
            const field_start = dot_pos + 1;
            const field_end = dot_pos + eq_pos;
            const value_start = field_end + 4; // " = \"".len
            
            if (std.mem.indexOf(u8, line[value_start..], "\"")) |quote_pos| {
                const field_name = line[field_start..field_end];
                const field_value = line[value_start..value_start + quote_pos];
                
                return FieldValue{
                    .name = allocator.dupe(u8, field_name) catch return null,
                    .value = allocator.dupe(u8, field_value) catch return null,
                };
            }
        }
    }
    
    // Handle .@"field" = "value"
    if (std.mem.indexOf(u8, line, ".@\"")) |start| {
        const quote_start = start + 3;
        if (std.mem.indexOf(u8, line[quote_start..], "\"")) |quote_end| {
            const field_name = line[quote_start..quote_start + quote_end];
            
            if (std.mem.indexOf(u8, line, " = \"")) |eq_pos| {
                const value_start = eq_pos + 4;
                if (std.mem.indexOf(u8, line[value_start..], "\"")) |value_quote_end| {
                    const field_value = line[value_start..value_start + value_quote_end];
                    
                    return FieldValue{
                        .name = allocator.dupe(u8, field_name) catch return null,
                        .value = allocator.dupe(u8, field_value) catch return null,
                    };
                }
            }
        }
    }
    
    return null;
}

test "extractAllFields" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    const test_content =
        \\.{
        \\    .name = "test",
        \\    .version = "1.0.0",
        \\    .@"quoted-field" = "value",
        \\}
    ;
    
    var fields = try extractAllFields(allocator, test_content);
    defer {
        var iterator = fields.iterator();
        while (iterator.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        fields.deinit();
    }
    
    try testing.expectEqual(@as(usize, 3), fields.count());
    try testing.expectEqualStrings("test", fields.get("name").?);
    try testing.expectEqualStrings("1.0.0", fields.get("version").?);
    try testing.expectEqualStrings("value", fields.get("quoted-field").?);
}

test "analyzeZonContent" {
    const test_content =
        \\// Comment line
        \\.{
        \\    .field1 = "value1",
        \\    .field2 = .{
        \\        .nested = "value",
        \\    },
        \\}
        \\
    ;
    
    const analysis = analyzeZonContent(test_content);
    try std.testing.expectEqual(@as(u32, 1), analysis.comment_lines);
    try std.testing.expectEqual(@as(u32, 6), analysis.content_lines);
    try std.testing.expectEqual(@as(u32, 1), analysis.empty_lines);
    try std.testing.expectEqual(@as(u32, 3), analysis.field_count);
    try std.testing.expectEqual(@as(u32, 2), analysis.struct_count);
}