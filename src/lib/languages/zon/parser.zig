const std = @import("std");

/// ZON (Zig Object Notation) parser
/// Provides text-based parsing of ZON files with proper memory management
/// Designed to be generic and reusable across the codebase

/// ZON parsing errors
pub const ZonParseError = error{
    InvalidSyntax,
    MalformedField,
    UnexpectedEndOfFile,
    OutOfMemory,
};

/// Generic ZON field extractor
/// Extracts field values from ZON content using text-based parsing
pub const ZonParser = struct {
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) ZonParser {
        return ZonParser{
            .allocator = allocator,
        };
    }
    
    /// Extract a single field value from ZON content
    /// Returns allocated string that caller must free
    pub fn extractField(self: ZonParser, content: []const u8, field_name: []const u8) !?[]u8 {
        const pattern = try std.fmt.allocPrint(self.allocator, ".{s} = \"", .{field_name});
        defer self.allocator.free(pattern);
        
        var lines = std.mem.splitSequence(u8, content, "\n");
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0) continue;
            if (std.mem.startsWith(u8, trimmed, "//")) continue;
            
            if (std.mem.indexOf(u8, trimmed, pattern)) |start| {
                const quote_start = start + pattern.len;
                if (std.mem.indexOf(u8, trimmed[quote_start..], "\"")) |quote_end| {
                    const value = trimmed[quote_start..quote_start + quote_end];
                    return try self.allocator.dupe(u8, value);
                }
            }
        }
        
        return null;
    }
    
    /// Extract a quoted field value (handles .@"field-name" syntax)
    pub fn extractQuotedField(self: ZonParser, content: []const u8, field_name: []const u8) !?[]u8 {
        const pattern = try std.fmt.allocPrint(self.allocator, ".@\"{s}\" = \"", .{field_name});
        defer self.allocator.free(pattern);
        
        var lines = std.mem.splitSequence(u8, content, "\n");
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0) continue;
            if (std.mem.startsWith(u8, trimmed, "//")) continue;
            
            if (std.mem.indexOf(u8, trimmed, pattern)) |start| {
                const quote_start = start + pattern.len;
                if (std.mem.indexOf(u8, trimmed[quote_start..], "\"")) |quote_end| {
                    const value = trimmed[quote_start..quote_start + quote_end];
                    return try self.allocator.dupe(u8, value);
                }
            }
        }
        
        return null;
    }
    
    /// Extract any field (tries both regular and quoted syntax)
    pub fn extractAnyField(self: ZonParser, content: []const u8, field_name: []const u8) !?[]u8 {
        // Try regular field first
        if (try self.extractField(content, field_name)) |value| {
            return value;
        }
        
        // Try quoted field
        return self.extractQuotedField(content, field_name);
    }
    
    /// Extract nested field using dot notation (e.g., "dependencies.zig-tree-sitter.version")
    pub fn extractNestedField(self: ZonParser, content: []const u8, field_path: []const u8) !?[]u8 {
        var path_parts = std.mem.splitSequence(u8, field_path, ".");
        var current_content = content;
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const arena_allocator = arena.allocator();
        
        // Navigate through the nested structure
        while (path_parts.next()) |part| {
            if (path_parts.peek() == null) {
                // Last part - extract the actual value
                return self.extractAnyField(current_content, part);
            } else {
                // Navigate into the nested structure
                const section = try self.extractSection(arena_allocator, current_content, part);
                if (section) |s| {
                    current_content = s;
                } else {
                    return null; // Path not found
                }
            }
        }
        
        return null;
    }
    
    /// Extract a ZON section (everything inside .field = .{ ... })
    fn extractSection(self: ZonParser, allocator: std.mem.Allocator, content: []const u8, section_name: []const u8) !?[]u8 {
        _ = self;
        const pattern = try std.fmt.allocPrint(allocator, ".{s} = .{{", .{section_name});
        defer allocator.free(pattern);
        
        var lines = std.mem.splitSequence(u8, content, "\n");
        var in_section = false;
        var brace_count: i32 = 0;
        var result = std.ArrayList(u8).init(allocator);
        defer result.deinit();
        
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0) continue;
            if (std.mem.startsWith(u8, trimmed, "//")) continue;
            
            if (!in_section) {
                if (std.mem.indexOf(u8, trimmed, pattern) != null) {
                    in_section = true;
                    // Count braces on this line
                    for (trimmed) |c| {
                        if (c == '{') brace_count += 1;
                        if (c == '}') brace_count -= 1;
                    }
                }
            } else {
                // We're in the section, collect content
                try result.appendSlice(line);
                try result.append('\n');
                
                // Track braces to know when section ends
                for (trimmed) |c| {
                    if (c == '{') brace_count += 1;
                    if (c == '}') brace_count -= 1;
                }
                
                if (brace_count <= 0) {
                    break; // End of section
                }
            }
        }
        
        if (result.items.len > 0) {
            return try allocator.dupe(u8, result.items);
        }
        
        return null;
    }
    
    /// Parse all dependencies from a deps.zon file
    /// Returns a HashMap with dependency name -> info
    pub fn parseDependencies(self: ZonParser, content: []const u8) !std.StringHashMap(DependencyInfo) {
        var dependencies = std.StringHashMap(DependencyInfo).init(self.allocator);
        
        // Extract the dependencies section
        const deps_section = try self.extractSection(self.allocator, content, "dependencies");
        if (deps_section == null) {
            return dependencies; // No dependencies section
        }
        defer self.allocator.free(deps_section.?);
        
        // Parse individual dependencies
        var lines = std.mem.splitSequence(u8, deps_section.?, "\n");
        var current_dep_name: ?[]u8 = null;
        var in_dep_block = false;
        var dep_brace_count: i32 = 0;
        var current_dep_info = DependencyInfo{};
        
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0) continue;
            if (std.mem.startsWith(u8, trimmed, "//")) continue;
            
            // Look for dependency name pattern: .@"dep-name" = .{
            if (std.mem.indexOf(u8, trimmed, ".@\"")) |start| {
                // Extract dependency name
                const quote_start = start + 3;
                if (std.mem.indexOf(u8, trimmed[quote_start..], "\"")) |quote_end| {
                    const dep_name_slice = trimmed[quote_start..quote_start + quote_end];
                    if (current_dep_name) |old_name| {
                        self.allocator.free(old_name);
                    }
                    current_dep_name = try self.allocator.dupe(u8, dep_name_slice);
                    in_dep_block = true;
                    dep_brace_count = 0;
                    current_dep_info = DependencyInfo{}; // Reset
                    
                    // Count braces on this line for the new dependency
                    for (trimmed) |c| {
                        if (c == '{') dep_brace_count += 1;
                        if (c == '}') dep_brace_count -= 1;
                    }
                }
                continue;
            }
            
            // If we're in a dependency block, look for field values
            if (in_dep_block and current_dep_name != null) {
                // Count braces to track when we exit the block
                for (trimmed) |c| {
                    if (c == '{') dep_brace_count += 1;
                    if (c == '}') dep_brace_count -= 1;
                }
                
                // Extract field values
                if (self.extractFieldValueFromLine(trimmed, "version")) |version_value| {
                    if (current_dep_info.version) |old_version| {
                        self.allocator.free(old_version);
                    }
                    current_dep_info.version = try self.allocator.dupe(u8, version_value);
                }
                
                if (self.extractFieldValueFromLine(trimmed, "url")) |url_value| {
                    if (current_dep_info.url) |old_url| {
                        self.allocator.free(old_url);
                    }
                    current_dep_info.url = try self.allocator.dupe(u8, url_value);
                }
                
                // Check if we've exited the dependency block
                if (dep_brace_count <= 0) {
                    // Store the completed dependency
                    try dependencies.put(current_dep_name.?, current_dep_info);
                    current_dep_name = null; // Don't free, HashMap owns it now
                    in_dep_block = false;
                }
            }
        }
        
        return dependencies;
    }
    
    /// Extract field value from a single line (internal helper)
    fn extractFieldValueFromLine(self: ZonParser, line: []const u8, field_name: []const u8) ?[]const u8 {
        _ = self;
        
        if (std.mem.eql(u8, field_name, "version")) {
            if (std.mem.indexOf(u8, line, ".version = \"")) |start| {
                const quote_start = start + 12; // ".version = \"".len
                if (std.mem.indexOf(u8, line[quote_start..], "\"")) |quote_end| {
                    return line[quote_start..quote_start + quote_end];
                }
            }
        } else if (std.mem.eql(u8, field_name, "url")) {
            if (std.mem.indexOf(u8, line, ".url = \"")) |start| {
                const quote_start = start + 8; // ".url = \"".len
                if (std.mem.indexOf(u8, line[quote_start..], "\"")) |quote_end| {
                    return line[quote_start..quote_start + quote_end];
                }
            }
        }
        
        return null;
    }
    
    /// Free all allocations for a dependency map
    pub fn freeDependencies(self: ZonParser, dependencies: *std.StringHashMap(DependencyInfo)) void {
        var iterator = dependencies.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            
            const dep_info = entry.value_ptr.*;
            if (dep_info.version) |version| {
                self.allocator.free(version);
            }
            if (dep_info.url) |url| {
                self.allocator.free(url);
            }
        }
        dependencies.deinit();
    }
};

/// Information about a dependency extracted from ZON
pub const DependencyInfo = struct {
    url: ?[]u8 = null,
    version: ?[]u8 = null,
    // Could be extended with more fields as needed
};

// Helper functions for common use cases
/// Quick extraction of a single field from ZON content
pub fn quickExtractField(allocator: std.mem.Allocator, content: []const u8, field_name: []const u8) !?[]u8 {
    var parser = ZonParser.init(allocator);
    return parser.extractAnyField(content, field_name);
}

/// Parse ZON content with error handling and defaults
pub fn parseZonWithDefaults(allocator: std.mem.Allocator, content: []const u8, comptime T: type, default_value: T) T {
    // Try to use the existing ZonCore for full struct parsing if needed
    const ZonCore = @import("../../core/zon.zig").ZonCore;
    return ZonCore.parseFromSliceWithDefault(T, allocator, content, default_value);
}

test "ZonParser field extraction" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    const test_content =
        \\.{
        \\    .name = "test-project",
        \\    .version = "1.0.0",
        \\    .@"quoted-field" = "quoted-value",
        \\    .dependencies = .{
        \\        .@"zig-tree-sitter" = .{
        \\            .url = "https://github.com/tree-sitter/zig-tree-sitter.git",
        \\            .version = "v0.25.0",
        \\        },
        \\    },
        \\}
    ;
    
    var parser = ZonParser.init(allocator);
    
    // Test regular field extraction
    const name = try parser.extractField(test_content, "name");
    defer if (name) |n| allocator.free(n);
    try testing.expectEqualStrings("test-project", name.?);
    
    // Test quoted field extraction
    const quoted = try parser.extractQuotedField(test_content, "quoted-field");
    defer if (quoted) |q| allocator.free(q);
    try testing.expectEqualStrings("quoted-value", quoted.?);
    
    // Test any field extraction
    const version = try parser.extractAnyField(test_content, "version");
    defer if (version) |v| allocator.free(v);
    try testing.expectEqualStrings("1.0.0", version.?);
}

test "ZonParser dependency parsing" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    const deps_content =
        \\.{
        \\    .dependencies = .{
        \\        .@"zig-tree-sitter" = .{
        \\            .url = "https://github.com/tree-sitter/zig-tree-sitter.git",
        \\            .version = "v0.25.0",
        \\        },
        \\        .@"tree-sitter" = .{
        \\            .url = "https://github.com/tree-sitter/tree-sitter.git",
        \\            .version = "v0.25.0",
        \\        },
        \\    },
        \\}
    ;
    
    var parser = ZonParser.init(allocator);
    var dependencies = try parser.parseDependencies(deps_content);
    defer parser.freeDependencies(&dependencies);
    
    try testing.expectEqual(@as(usize, 2), dependencies.count());
    
    const zig_ts = dependencies.get("zig-tree-sitter").?;
    try testing.expectEqualStrings("v0.25.0", zig_ts.version.?);
    try testing.expectEqualStrings("https://github.com/tree-sitter/zig-tree-sitter.git", zig_ts.url.?);
}