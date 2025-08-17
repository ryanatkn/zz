const std = @import("std");
const config = @import("config.zig");
const utils = @import("utils.zig");
const io = @import("../core/io.zig");
const path = @import("../core/path.zig");
const FilesystemInterface = @import("../filesystem/interface.zig").FilesystemInterface;
const RealFilesystem = @import("../filesystem/real.zig").RealFilesystem;

/// Categories for dependency classification
pub const DependencyCategory = enum {
    core,      // Core libraries (tree-sitter, zig-tree-sitter)
    grammar,   // Language grammars (tree-sitter-*)
    reference, // Documentation/specs (zig-spec)
    
    pub fn toString(self: DependencyCategory) []const u8 {
        return switch (self) {
            .core => "core",
            .grammar => "grammar",
            .reference => "reference",
        };
    }
    
    pub fn displayName(self: DependencyCategory) []const u8 {
        return switch (self) {
            .core => "Core Libraries",
            .grammar => "Language Grammars", 
            .reference => "Reference Documentation",
        };
    }
};

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

/// Enhanced dependency documentation structure
pub const DependencyDoc = struct {
    name: []const u8,
    category: DependencyCategory,
    version_info: config.VersionInfo,
    build_config: BuildConfig,
    language: ?[]const u8,      // For grammars: "zig", "css", etc.
    purpose: []const u8,        // Human-readable purpose
    
    pub fn deinit(self: *const DependencyDoc, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        self.version_info.deinit(allocator);
        self.build_config.deinit(allocator);
        if (self.language) |lang| {
            allocator.free(lang);
        }
        allocator.free(self.purpose);
    }
};

/// Main documentation generator
pub const DocumentationGenerator = struct {
    allocator: std.mem.Allocator,
    filesystem: FilesystemInterface,
    deps_dir: []const u8,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator, deps_dir: []const u8) Self {
        return Self.initWithFilesystem(allocator, RealFilesystem.init(), deps_dir);
    }
    
    pub fn initWithFilesystem(allocator: std.mem.Allocator, filesystem: FilesystemInterface, deps_dir: []const u8) Self {
        return Self{
            .allocator = allocator,
            .filesystem = filesystem,
            .deps_dir = deps_dir,
        };
    }
    
    /// Generate both DEPS.md and manifest.json from current dependency state
    pub fn generateDocumentation(self: *Self, dependencies: []const config.Dependency) !void {
        // Collect dependency documentation
        var dep_docs = std.ArrayList(DependencyDoc).init(self.allocator);
        defer {
            for (dep_docs.items) |*doc| {
                doc.deinit(self.allocator);
            }
            dep_docs.deinit();
        }
        
        for (dependencies) |dep| {
            const doc = try self.createDependencyDoc(dep);
            try dep_docs.append(doc);
        }
        
        // Generate DEPS.md
        try self.generateMarkdownDocs(dep_docs.items);
        
        // Generate manifest.json
        try self.generateManifest(dep_docs.items);
    }
    
    /// Create a DependencyDoc from a config.Dependency
    fn createDependencyDoc(self: *Self, dep: config.Dependency) !DependencyDoc {
        // Load version info from .version file
        const dep_dir = try path.joinPath(self.allocator, self.deps_dir, dep.name);
        defer self.allocator.free(dep_dir);
        
        const version_file = try path.joinPath(self.allocator, dep_dir, ".version");
        defer self.allocator.free(version_file);
        
        // Read .version file content
        const content = utils.Utils.readFileOptional(self.allocator, version_file, 1024) catch |err| switch (err) {
            error.FileNotFound => {
                // Create a default version info if file doesn't exist
                return DependencyDoc{
                    .name = try self.allocator.dupe(u8, dep.name),
                    .category = if (dep.category) |cat| self.parseCategory(cat) else self.categorizeDepencency(dep.name),
                    .version_info = config.VersionInfo{
                        .repository = try self.allocator.dupe(u8, dep.url),
                        .version = try self.allocator.dupe(u8, dep.version),
                        .commit = try self.allocator.dupe(u8, "unknown"),
                        .updated = 0,
                        .updated_by = try self.allocator.dupe(u8, "unknown"),
                    },
                    .build_config = try self.extractBuildInfo(dep.name),
                    .language = if (dep.language) |lang| try self.allocator.dupe(u8, lang) else try self.extractLanguage(dep.name),
                    .purpose = if (dep.purpose) |purpose| try self.allocator.dupe(u8, purpose) else try self.generatePurpose(dep.name),
                };
            },
            else => return err,
        };
        
        if (content) |c| {
            defer self.allocator.free(c);
            const version_info = try config.VersionInfo.parseFromContent(self.allocator, c);
            
            return DependencyDoc{
                .name = try self.allocator.dupe(u8, dep.name),
                .category = if (dep.category) |cat| self.parseCategory(cat) else self.categorizeDepencency(dep.name),
                .version_info = version_info,
                .build_config = try self.extractBuildInfo(dep.name),
                .language = if (dep.language) |lang| try self.allocator.dupe(u8, lang) else try self.extractLanguage(dep.name),
                .purpose = if (dep.purpose) |purpose| try self.allocator.dupe(u8, purpose) else try self.generatePurpose(dep.name),
            };
        } else {
            // No version file found, create default
            return DependencyDoc{
                .name = try self.allocator.dupe(u8, dep.name),
                .category = if (dep.category) |cat| self.parseCategory(cat) else self.categorizeDepencency(dep.name),
                .version_info = config.VersionInfo{
                    .repository = try self.allocator.dupe(u8, dep.url),
                    .version = try self.allocator.dupe(u8, dep.version),
                    .commit = try self.allocator.dupe(u8, "unknown"),
                    .updated = 0,
                    .updated_by = try self.allocator.dupe(u8, "unknown"),
                },
                .build_config = try self.extractBuildInfo(dep.name),
                .language = if (dep.language) |lang| try self.allocator.dupe(u8, lang) else try self.extractLanguage(dep.name),
                .purpose = if (dep.purpose) |purpose| try self.allocator.dupe(u8, purpose) else try self.generatePurpose(dep.name),
            };
        }
    }
    
    /// Parse category string to enum
    fn parseCategory(self: *Self, category_str: []const u8) DependencyCategory {
        _ = self;
        
        if (std.mem.eql(u8, category_str, "core")) {
            return .core;
        } else if (std.mem.eql(u8, category_str, "grammar")) {
            return .grammar;
        } else if (std.mem.eql(u8, category_str, "reference")) {
            return .reference;
        } else {
            return .reference; // Default fallback
        }
    }
    
    /// Categorize a dependency by name
    fn categorizeDepencency(self: *Self, name: []const u8) DependencyCategory {
        _ = self;
        
        if (std.mem.eql(u8, name, "tree-sitter") or 
            std.mem.eql(u8, name, "zig-tree-sitter")) {
            return .core;
        }
        
        if (std.mem.startsWith(u8, name, "tree-sitter-")) {
            return .grammar;
        }
        
        if (std.mem.eql(u8, name, "zig-spec")) {
            return .reference;
        }
        
        return .reference; // Default to reference for unknown dependencies
    }
    
    /// Extract language from grammar dependency name
    fn extractLanguage(self: *Self, name: []const u8) !?[]const u8 {
        if (std.mem.startsWith(u8, name, "tree-sitter-")) {
            const lang = name[13..]; // Skip "tree-sitter-"
            return try self.allocator.dupe(u8, lang);
        }
        return null;
    }
    
    /// Generate human-readable purpose for a dependency
    fn generatePurpose(self: *Self, name: []const u8) ![]const u8 {
        if (std.mem.eql(u8, name, "tree-sitter")) {
            return try self.allocator.dupe(u8, "Core tree-sitter parsing engine");
        } else if (std.mem.eql(u8, name, "zig-tree-sitter")) {
            return try self.allocator.dupe(u8, "Zig language bindings to tree-sitter");
        } else if (std.mem.eql(u8, name, "zig-spec")) {
            return try self.allocator.dupe(u8, "Zig language specification and grammar reference");
        } else if (std.mem.startsWith(u8, name, "tree-sitter-")) {
            const lang = name[13..];
            return try std.fmt.allocPrint(self.allocator, "{s} language grammar for tree-sitter", .{lang});
        } else {
            return try std.fmt.allocPrint(self.allocator, "Dependency: {s}", .{name});
        }
    }
    
    /// Extract build configuration from build.zig by parsing the actual file
    fn extractBuildInfo(self: *Self, name: []const u8) !BuildConfig {
        // Parse build.zig to extract actual build configuration
        const build_zig_path = "build.zig"; // Relative to project root
        
        const build_content = utils.Utils.readFileOptional(self.allocator, build_zig_path, 1024 * 1024) catch |err| switch (err) {
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
        var source_files = std.ArrayList([]const u8).init(self.allocator);
        defer source_files.deinit();
        var include_paths = std.ArrayList([]const u8).init(self.allocator);
        defer include_paths.deinit();
        var flags = std.ArrayList([]const u8).init(self.allocator);
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
            const lang = dep_name[13..];
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
    fn extractSourceFiles(self: *Self, line: []const u8, source_files: *std.ArrayList([]const u8)) !void {
        // Look for .file = b.path("...") or .files = &.{"...", "..."}
        if (std.mem.indexOf(u8, line, ".file = b.path(\"")) |start| {
            const quote_start = start + 15; // Length of ".file = b.path(\""
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
    fn extractIncludePath(self: *Self, line: []const u8, include_paths: *std.ArrayList([]const u8), dep_name: []const u8) !void {
        if (std.mem.indexOf(u8, line, "addIncludePath(b.path(\"")) |start| {
            const quote_start = start + 23; // Length of "addIncludePath(b.path(\""
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
    fn extractFlags(self: *Self, line: []const u8, flags: *std.ArrayList([]const u8)) !void {
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
            var source_files_list = std.ArrayList([]const u8).init(self.allocator);
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
    
    /// Generate DEPS.md markdown documentation
    fn generateMarkdownDocs(self: *Self, dep_docs: []const DependencyDoc) !void {
        var content = std.ArrayList(u8).init(self.allocator);
        defer content.deinit();
        
        const writer = content.writer();
        
        // Header
        try writer.print("# Dependency Manifest\n", .{});
        try writer.print("Generated: {d}-{d:0>2}-{d:0>2} by zz deps\n\n", .{ 
            2025, 8, 17  // TODO: Use actual current date
        });
        
        // Summary
        try writer.print("## Summary\n", .{});
        try writer.print("Total Dependencies: {d}\n\n", .{dep_docs.len});
        
        // Group by category
        var core_deps = std.ArrayList(*const DependencyDoc).init(self.allocator);
        defer core_deps.deinit();
        var grammar_deps = std.ArrayList(*const DependencyDoc).init(self.allocator);
        defer grammar_deps.deinit();
        var reference_deps = std.ArrayList(*const DependencyDoc).init(self.allocator);
        defer reference_deps.deinit();
        
        for (dep_docs) |*doc| {
            switch (doc.category) {
                .core => try core_deps.append(doc),
                .grammar => try grammar_deps.append(doc),
                .reference => try reference_deps.append(doc),
            }
        }
        
        // Core Libraries section
        if (core_deps.items.len > 0) {
            try writer.print("## {s} ({d})\n\n", .{ DependencyCategory.core.displayName(), core_deps.items.len });
            try writer.print("| Dependency | Version | Repository | Purpose |\n", .{});
            try writer.print("|------------|---------|------------|----------|\n", .{});
            
            for (core_deps.items) |doc| {
                try writer.print("| {s} | {s} | [GitHub]({s}) | {s} |\n", .{
                    doc.name,
                    doc.version_info.version,
                    doc.version_info.repository,
                    doc.purpose,
                });
            }
            try writer.print("\n", .{});
        }
        
        // Grammar Libraries section
        if (grammar_deps.items.len > 0) {
            try writer.print("## {s} ({d})\n\n", .{ DependencyCategory.grammar.displayName(), grammar_deps.items.len });
            try writer.print("| Dependency | Version | Language | Parser Function | Purpose |\n", .{});
            try writer.print("|------------|---------|----------|-----------------|----------|\n", .{});
            
            for (grammar_deps.items) |doc| {
                const lang = doc.language orelse "unknown";
                const parser_func = doc.build_config.parser_function orelse "unknown";
                try writer.print("| {s} | {s} | {s} | `{s}()` | {s} |\n", .{
                    doc.name,
                    doc.version_info.version,
                    lang,
                    parser_func,
                    doc.purpose,
                });
            }
            try writer.print("\n", .{});
        }
        
        // Reference Documentation section
        if (reference_deps.items.len > 0) {
            try writer.print("## {s} ({d})\n\n", .{ DependencyCategory.reference.displayName(), reference_deps.items.len });
            try writer.print("| Dependency | Version | Purpose |\n", .{});
            try writer.print("|------------|---------|----------|\n", .{});
            
            for (reference_deps.items) |doc| {
                try writer.print("| {s} | {s} | {s} |\n", .{
                    doc.name,
                    doc.version_info.version,
                    doc.purpose,
                });
            }
            try writer.print("\n", .{});
        }
        
        // Write to file
        const deps_md_path = try path.joinPath(self.allocator, self.deps_dir, "DEPS.md");
        defer self.allocator.free(deps_md_path);
        
        try io.writeFile(deps_md_path, content.items);
    }
    
    /// Generate manifest.json machine-readable documentation
    fn generateManifest(self: *Self, dep_docs: []const DependencyDoc) !void {
        var content = std.ArrayList(u8).init(self.allocator);
        defer content.deinit();
        
        const writer = content.writer();
        
        try writer.print("{{\n", .{});
        try writer.print("  \"generated\": \"2025-08-17T10:30:00Z\",\n", .{});
        try writer.print("  \"generator\": \"zz-deps-v1.0.0\",\n", .{});
        try writer.print("  \"dependencies\": {{\n", .{});
        
        for (dep_docs, 0..) |doc, i| {
            try writer.print("    \"{s}\": {{\n", .{doc.name});
            try writer.print("      \"category\": \"{s}\",\n", .{doc.category.toString()});
            try writer.print("      \"version\": \"{s}\",\n", .{doc.version_info.version});
            try writer.print("      \"repository\": \"{s}\",\n", .{doc.version_info.repository});
            try writer.print("      \"commit\": \"{s}\",\n", .{doc.version_info.commit});
            try writer.print("      \"purpose\": \"{s}\"", .{doc.purpose});
            
            if (doc.language) |lang| {
                try writer.print(",\n      \"language\": \"{s}\"", .{lang});
            }
            
            if (doc.build_config.parser_function) |func| {
                try writer.print(",\n      \"parser_function\": \"{s}\"", .{func});
            }
            
            try writer.print("\n    }}", .{});
            
            if (i < dep_docs.len - 1) {
                try writer.print(",", .{});
            }
            try writer.print("\n", .{});
        }
        
        try writer.print("  }}\n", .{});
        try writer.print("}}\n", .{});
        
        // Write to file
        const manifest_path = try path.joinPath(self.allocator, self.deps_dir, "manifest.json");
        defer self.allocator.free(manifest_path);
        
        try io.writeFile(manifest_path, content.items);
    }
};