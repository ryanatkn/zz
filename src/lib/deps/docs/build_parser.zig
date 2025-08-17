const std = @import("std");
const io = @import("../../core/io.zig");
const collections = @import("../../core/collections.zig");

/// Build configuration extracted from build.zig
pub const BuildConfig = struct {
    type: []const u8,           // "static_library", "module", etc.
    source_files: [][]const u8, // C source files
    include_paths: [][]const u8, // Include directories
    flags: [][]const u8,        // Compiler flags
    parser_function: ?[]const u8, // For grammars: tree_sitter_css()
    
    pub fn deinit(self: *const BuildConfig, allocator: std.mem.Allocator) void {
        allocator.free(self.type);
        for (self.source_files) |source| {
            allocator.free(source);
        }
        allocator.free(self.source_files);
        for (self.include_paths) |include| {
            allocator.free(include);
        }
        allocator.free(self.include_paths);
        for (self.flags) |flag| {
            allocator.free(flag);
        }
        allocator.free(self.flags);
        if (self.parser_function) |func| {
            allocator.free(func);
        }
    }
};

/// Build configuration parser for extracting dependency information from build.zig
pub const BuildParser = struct {
    allocator: std.mem.Allocator,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }
    
    /// Extract build configuration from build.zig by parsing the actual file
    pub fn extractBuildInfo(self: *Self, name: []const u8) !BuildConfig {
        // Parse build.zig to extract actual build configuration
        const build_zig_path = "build.zig"; // Relative to project root
        
        const build_content = io.readFileOptional(self.allocator, build_zig_path) catch |err| switch (err) {
            error.FileNotFound => {
                // Fallback to hardcoded values if build.zig can't be read
                return self.extractBuildInfoFallback(name);
            },
            else => return err,
        };
        
        if (build_content) |content| {
            defer self.allocator.free(content);
            return try self.parseBuildZigForDependency(content, name);
        } else {
            return self.extractBuildInfoFallback(name);
        }
    }
    
    /// Parse build.zig content to extract dependency configuration
    fn parseBuildZigForDependency(self: *Self, content: []const u8, dep_name: []const u8) !BuildConfig {
        var source_files = collections.List([]const u8).init(self.allocator);
        defer source_files.deinit();
        var include_paths = collections.List([]const u8).init(self.allocator);
        defer include_paths.deinit();
        var flags = collections.List([]const u8).init(self.allocator);
        defer flags.deinit();
        
        var build_type: []const u8 = "unknown";
        var parser_function: ?[]const u8 = null;
        
        // Look for library definition patterns
        const lib_name = if (std.mem.eql(u8, dep_name, "zig-tree-sitter")) "tree-sitter" else dep_name;
        
        // Find library definition by searching for addStaticLibrary or addModule with matching name
        var lines = std.mem.splitSequence(u8, content, "\n");
        var in_target_lib = false;
        var brace_count: i32 = 0;
        
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t");
            
            // Detect library definition start
            if (std.mem.indexOf(u8, trimmed, "addStaticLibrary") != null and 
                std.mem.indexOf(u8, trimmed, lib_name) != null) {
                in_target_lib = true;
                build_type = "static_library";
                brace_count = 0;
                continue;
            } else if (std.mem.indexOf(u8, trimmed, "addModule") != null and 
                       std.mem.indexOf(u8, trimmed, "tree-sitter") != null and 
                       std.mem.eql(u8, dep_name, "zig-tree-sitter")) {
                build_type = "zig_module";
                // For zig modules, we don't need to parse further
                break;
            }
            
            if (!in_target_lib) continue;
            
            // Track braces to know when we're done with this library
            var i: usize = 0;
            while (i < trimmed.len) : (i += 1) {
                switch (trimmed[i]) {
                    '{' => brace_count += 1,
                    '}' => brace_count -= 1,
                    else => {},
                }
            }
            
            // Extract source files
            if (std.mem.indexOf(u8, trimmed, "addCSourceFile") != null or
                std.mem.indexOf(u8, trimmed, "addCSourceFiles") != null) {
                try self.extractSourceFiles(trimmed, &source_files);
            }
            
            // Extract include paths
            if (std.mem.indexOf(u8, trimmed, "addIncludePath") != null) {
                try self.extractIncludePath(trimmed, &include_paths, dep_name);
            }
            
            // Extract compiler flags
            if (std.mem.indexOf(u8, trimmed, ".flags = ") != null) {
                try self.extractFlags(trimmed, &flags);
            }
            
            // End of library definition
            if (brace_count < 0) {
                break;
            }
        }
        
        // Generate parser function for grammars
        if (std.mem.startsWith(u8, dep_name, "tree-sitter-")) {
            const lang = dep_name[12..]; // Skip "tree-sitter-" (12 chars)
            parser_function = try std.fmt.allocPrint(self.allocator, "tree_sitter_{s}", .{lang});
        }
        
        return BuildConfig{
            .type = try self.allocator.dupe(u8, build_type),
            .source_files = try source_files.toOwnedSlice(),
            .include_paths = try include_paths.toOwnedSlice(),
            .flags = try flags.toOwnedSlice(),
            .parser_function = parser_function,
        };
    }
    
    /// Extract source file paths from addCSourceFile(s) lines
    fn extractSourceFiles(self: *Self, line: []const u8, source_files: *collections.List([]const u8)) !void {
        // Look for .file = b.path("...") or .files = &.{"...", "..."}
        if (std.mem.indexOf(u8, line, ".file = b.path(\"")) |start| {
            const quote_start = start + 15; // Length of ".file = b.path(\"
            if (std.mem.indexOfPos(u8, line, quote_start, "\"")) |quote_end| {
                const file_path = line[quote_start..quote_end];
                // Remove deps/dependency-name/ prefix to get relative path within dependency
                if (std.mem.indexOf(u8, file_path, "/")) |first_slash| {
                    if (std.mem.indexOfPos(u8, file_path, first_slash + 1, "/")) |second_slash| {
                        const relative_path = file_path[second_slash + 1..];
                        try source_files.append(try self.allocator.dupe(u8, relative_path));
                    }
                }
            }
        } else if (std.mem.indexOf(u8, line, ".files = &.{")) |_| {
            // Parse multiple files in array format
            const start_idx = std.mem.indexOf(u8, line, "{").? + 1;
            const end_idx = std.mem.lastIndexOf(u8, line, "}") orelse line.len;
            const files_section = line[start_idx..end_idx];
            
            var file_iter = std.mem.splitSequence(u8, files_section, ",");
            while (file_iter.next()) |file_part| {
                const trimmed_part = std.mem.trim(u8, file_part, " \t\"");
                if (std.mem.startsWith(u8, trimmed_part, "deps/")) {
                    // Extract relative path within dependency
                    if (std.mem.indexOf(u8, trimmed_part, "/")) |first_slash| {
                        if (std.mem.indexOfPos(u8, trimmed_part, first_slash + 1, "/")) |second_slash| {
                            const relative_path = trimmed_part[second_slash + 1..];
                            if (relative_path.len > 0) {
                                try source_files.append(try self.allocator.dupe(u8, relative_path));
                            }
                        }
                    }
                }
            }
        }
    }
    
    /// Extract include path from addIncludePath lines
    fn extractIncludePath(self: *Self, line: []const u8, include_paths: *collections.List([]const u8), dep_name: []const u8) !void {
        if (std.mem.indexOf(u8, line, "addIncludePath(b.path(\"")) |start| {
            const quote_start = start + 23; // Length of "addIncludePath(b.path("
            if (std.mem.indexOfPos(u8, line, quote_start, "\"")) |quote_end| {
                const full_path = line[quote_start..quote_end];
                
                // Convert absolute paths to relative paths within dependency
                const expected_prefix = try std.fmt.allocPrint(self.allocator, "deps/{s}/", .{dep_name});
                defer self.allocator.free(expected_prefix);
                
                if (std.mem.startsWith(u8, full_path, expected_prefix)) {
                    const relative_path = full_path[expected_prefix.len..];
                    if (relative_path.len > 0) {
                        try include_paths.append(try self.allocator.dupe(u8, relative_path));
                    } else {
                        try include_paths.append(try self.allocator.dupe(u8, "."));
                    }
                } else if (std.mem.indexOf(u8, full_path, "tree-sitter/lib/include")) |_| {
                    // Special case for tree-sitter core include
                    try include_paths.append(try self.allocator.dupe(u8, "../tree-sitter/lib/include"));
                }
            }
        }
    }
    
    /// Extract compiler flags from .flags = arrays
    fn extractFlags(self: *Self, line: []const u8, flags: *collections.List([]const u8)) !void {
        if (std.mem.indexOf(u8, line, ".flags = &.{")) |start| {
            const brace_start = std.mem.indexOf(u8, line[start..], "{").? + start + 1;
            const brace_end = std.mem.lastIndexOf(u8, line, "}") orelse line.len;
            const flags_section = line[brace_start..brace_end];
            
            var flag_iter = std.mem.splitSequence(u8, flags_section, ",");
            while (flag_iter.next()) |flag_part| {
                const trimmed_flag = std.mem.trim(u8, flag_part, " \t\"");
                if (trimmed_flag.len > 0) {
                    try flags.append(try self.allocator.dupe(u8, trimmed_flag));
                }
            }
        }
    }
    
    /// Fallback build info when build.zig parsing fails
    fn extractBuildInfoFallback(self: *Self, name: []const u8) !BuildConfig {
        // Hardcoded fallback based on known dependency patterns
        if (std.mem.eql(u8, name, "tree-sitter")) {
            var source_files = try self.allocator.alloc([]const u8, 1);
            source_files[0] = try self.allocator.dupe(u8, "lib/src/lib.c");
            
            var include_paths = try self.allocator.alloc([]const u8, 2);
            include_paths[0] = try self.allocator.dupe(u8, "lib/include");
            include_paths[1] = try self.allocator.dupe(u8, "lib/src");
            
            var flags = try self.allocator.alloc([]const u8, 3);
            flags[0] = try self.allocator.dupe(u8, "-std=c11");
            flags[1] = try self.allocator.dupe(u8, "-D_DEFAULT_SOURCE");
            flags[2] = try self.allocator.dupe(u8, "-D_BSD_SOURCE");
            
            return BuildConfig{
                .type = try self.allocator.dupe(u8, "static_library"),
                .source_files = source_files,
                .include_paths = include_paths,
                .flags = flags,
                .parser_function = null,
            };
        } else if (std.mem.eql(u8, name, "zig-tree-sitter")) {
            return BuildConfig{
                .type = try self.allocator.dupe(u8, "zig_module"),
                .source_files = try self.allocator.alloc([]const u8, 0),
                .include_paths = try self.allocator.alloc([]const u8, 0),
                .flags = try self.allocator.alloc([]const u8, 0),
                .parser_function = null,
            };
        } else if (std.mem.startsWith(u8, name, "tree-sitter-")) {
            const lang = name[13..];
            
            // Determine source files based on language (some have scanner.c)
            var source_files_list = collections.List([]const u8).init(self.allocator);
            defer source_files_list.deinit();
            
            try source_files_list.append(try self.allocator.dupe(u8, "src/parser.c"));
            if (std.mem.eql(u8, lang, "css") or std.mem.eql(u8, lang, "html") or 
                std.mem.eql(u8, lang, "typescript") or std.mem.eql(u8, lang, "svelte")) {
                try source_files_list.append(try self.allocator.dupe(u8, "src/scanner.c"));
            }
            
            var include_paths = try self.allocator.alloc([]const u8, 2);
            include_paths[0] = try self.allocator.dupe(u8, "src");
            include_paths[1] = try self.allocator.dupe(u8, "../tree-sitter/lib/include");
            
            var flags = try self.allocator.alloc([]const u8, 1);
            flags[0] = try self.allocator.dupe(u8, "-std=c11");
            
            const parser_func = try std.fmt.allocPrint(self.allocator, "tree_sitter_{s}", .{lang});
            
            return BuildConfig{
                .type = try self.allocator.dupe(u8, "static_library"),
                .source_files = try source_files_list.toOwnedSlice(),
                .include_paths = include_paths,
                .flags = flags,
                .parser_function = parser_func,
            };
        } else {
            return BuildConfig{
                .type = try self.allocator.dupe(u8, "unknown"),
                .source_files = try self.allocator.alloc([]const u8, 0),
                .include_paths = try self.allocator.alloc([]const u8, 0),
                .flags = try self.allocator.alloc([]const u8, 0),
                .parser_function = null,
            };
        }
    }
};