const std = @import("std");
const path = @import("path.zig");
const file_helpers = @import("file_helpers.zig");
const error_helpers = @import("error_helpers.zig");
const collection_helpers = @import("collection_helpers.zig");
const Language = @import("parser.zig").Language;
const ImportType = @import("import_extractor.zig").ImportType;

/// Configuration for import resolution
pub const ResolverConfig = struct {
    project_root: []const u8,
    node_modules_paths: [][]const u8,
    include_paths: [][]const u8,        // For C/C++ includes
    zig_package_paths: [][]const u8,    // For Zig package resolution
    typescript_paths: ?TypeScriptPaths, // TypeScript path mapping
    extensions: [][]const u8,           // File extensions to try
    follow_symlinks: bool,
    max_resolution_depth: u32,
    
    pub const TypeScriptPaths = struct {
        base_url: []const u8,
        paths: std.HashMap([]const u8, [][]const u8, std.hash_map.StringContext, 80),
        
        pub fn deinit(self: *TypeScriptPaths, allocator: std.mem.Allocator) void {
            var iter = self.paths.iterator();
            while (iter.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                for (entry.value_ptr.*) |path_item| {
                    allocator.free(path_item);
                }
                allocator.free(entry.value_ptr.*);
            }
            self.paths.deinit();
        }
    };
    
    pub fn deinit(self: *ResolverConfig, allocator: std.mem.Allocator) void {
        allocator.free(self.project_root);
        for (self.node_modules_paths) |node_path| {
            allocator.free(node_path);
        }
        allocator.free(self.node_modules_paths);
        for (self.include_paths) |include_path| {
            allocator.free(include_path);
        }
        allocator.free(self.include_paths);
        for (self.zig_package_paths) |zig_path| {
            allocator.free(zig_path);
        }
        allocator.free(self.zig_package_paths);
        if (self.typescript_paths) |*ts_paths| {
            ts_paths.deinit(allocator);
        }
        for (self.extensions) |ext| {
            allocator.free(ext);
        }
        allocator.free(self.extensions);
    }
    
    /// Create default resolver configuration
    pub fn default(allocator: std.mem.Allocator, project_root: []const u8) !ResolverConfig {
        const extensions = [_][]const u8{ ".zig", ".ts", ".js", ".tsx", ".jsx", ".css", ".html", ".json", ".c", ".h", ".cpp", ".hpp" };
        const ext_copies = try allocator.alloc([]const u8, extensions.len);
        for (extensions, 0..) |ext, i| {
            ext_copies[i] = try allocator.dupe(u8, ext);
        }
        
        return ResolverConfig{
            .project_root = try allocator.dupe(u8, project_root),
            .node_modules_paths = try allocator.alloc([]const u8, 0),
            .include_paths = try allocator.alloc([]const u8, 0),
            .zig_package_paths = try allocator.alloc([]const u8, 0),
            .typescript_paths = null,
            .extensions = ext_copies,
            .follow_symlinks = false,
            .max_resolution_depth = 10,
        };
    }
};

/// Result of import resolution
pub const ResolutionResult = struct {
    resolved_path: ?[]const u8,      // Absolute path to resolved file
    resolution_type: ResolutionType,  // How the import was resolved
    is_external: bool,               // Whether this is an external dependency
    package_name: ?[]const u8,       // Package name for external dependencies
    error_message: ?[]const u8,      // Error message if resolution failed
    
    pub const ResolutionType = enum {
        relative_file,      // ./file or ../file
        absolute_file,      // /absolute/path
        node_module,        // npm package
        zig_package,        // Zig package
        system_include,     // System header (<stdio.h>)
        local_include,      // Local header ("header.h")
        builtin,           // Built-in module (std, etc.)
        not_found,         // Could not resolve
    };
    
    pub fn deinit(self: *ResolutionResult, allocator: std.mem.Allocator) void {
        if (self.resolved_path) |resolved| {
            allocator.free(resolved);
        }
        if (self.package_name) |package| {
            allocator.free(package);
        }
        if (self.error_message) |message| {
            allocator.free(message);
        }
    }
    
    pub fn isResolved(self: ResolutionResult) bool {
        return self.resolved_path != null and self.resolution_type != .not_found;
    }
};

/// Advanced import path resolver
pub const ImportResolver = struct {
    allocator: std.mem.Allocator,
    config: ResolverConfig,
    cache: std.HashMap([]const u8, ResolutionResult, std.hash_map.StringContext, 80),
    stats: ResolverStats,
    
    const Self = @This();
    
    pub const ResolverStats = struct {
        total_resolutions: u64 = 0,
        cache_hits: u64 = 0,
        successful_resolutions: u64 = 0,
        failed_resolutions: u64 = 0,
        relative_resolutions: u64 = 0,
        package_resolutions: u64 = 0,
        
        pub fn hitRate(self: ResolverStats) f64 {
            if (self.total_resolutions == 0) return 0.0;
            return @as(f64, @floatFromInt(self.cache_hits)) / @as(f64, @floatFromInt(self.total_resolutions));
        }
        
        pub fn successRate(self: ResolverStats) f64 {
            if (self.total_resolutions == 0) return 0.0;
            return @as(f64, @floatFromInt(self.successful_resolutions)) / @as(f64, @floatFromInt(self.total_resolutions));
        }
    };
    
    /// Initialize resolver taking ownership of config
    /// Config ownership transfers to resolver - caller should not use config after this
    pub fn initOwning(allocator: std.mem.Allocator, config: ResolverConfig) Self {
        return Self{
            .allocator = allocator,
            .config = config,
            .cache = std.HashMap([]const u8, ResolutionResult, std.hash_map.StringContext, 80).init(allocator),
            .stats = ResolverStats{},
        };
    }
    
    /// Initialize resolver borrowing config (makes internal copy)
    /// Caller retains ownership of config and must clean it up
    pub fn initBorrowing(allocator: std.mem.Allocator, config: *const ResolverConfig) !Self {
        // Deep copy all string arrays
        const node_modules_copy = try allocator.alloc([]const u8, config.node_modules_paths.len);
        for (config.node_modules_paths, 0..) |node_path, i| {
            node_modules_copy[i] = try allocator.dupe(u8, node_path);
        }
        
        const include_paths_copy = try allocator.alloc([]const u8, config.include_paths.len);
        for (config.include_paths, 0..) |include_path, i| {
            include_paths_copy[i] = try allocator.dupe(u8, include_path);
        }
        
        const zig_package_paths_copy = try allocator.alloc([]const u8, config.zig_package_paths.len);
        for (config.zig_package_paths, 0..) |zig_path, i| {
            zig_package_paths_copy[i] = try allocator.dupe(u8, zig_path);
        }
        
        const extensions_copy = try allocator.alloc([]const u8, config.extensions.len);
        for (config.extensions, 0..) |ext, i| {
            extensions_copy[i] = try allocator.dupe(u8, ext);
        }
        
        const owned_config = ResolverConfig{
            .project_root = try allocator.dupe(u8, config.project_root),
            .node_modules_paths = node_modules_copy,
            .include_paths = include_paths_copy,
            .zig_package_paths = zig_package_paths_copy,
            .typescript_paths = config.typescript_paths, // TODO: Deep copy if needed
            .extensions = extensions_copy,
            .follow_symlinks = config.follow_symlinks,
            .max_resolution_depth = config.max_resolution_depth,
        };
        
        return Self{
            .allocator = allocator,
            .config = owned_config,
            .cache = std.HashMap([]const u8, ResolutionResult, std.hash_map.StringContext, 80).init(allocator),
            .stats = ResolverStats{},
        };
    }
    
    /// Compatibility alias for backward compatibility - transfers ownership
    pub fn init(allocator: std.mem.Allocator, config: ResolverConfig) Self {
        return initOwning(allocator, config);
    }
    
    pub fn deinit(self: *Self) void {
        // Clean up cache
        var iter = self.cache.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            var mutable_result = entry.value_ptr.*;
            mutable_result.deinit(self.allocator);
        }
        self.cache.deinit();
        
        self.config.deinit(self.allocator);
    }
    
    /// Resolve an import path to an absolute file path
    pub fn resolve(self: *Self, from_file: []const u8, import_path: []const u8, import_type: ImportType) !ResolutionResult {
        self.stats.total_resolutions += 1;
        
        // Create cache key
        const cache_key = try self.createCacheKey(from_file, import_path, import_type);
        defer self.allocator.free(cache_key);
        
        // Check cache first
        if (self.cache.get(cache_key)) |cached_result| {
            self.stats.cache_hits += 1;
            
            // Deep copy the cached result
            const result = ResolutionResult{
                .resolved_path = if (cached_result.resolved_path) |p| try self.allocator.dupe(u8, p) else null,
                .resolution_type = cached_result.resolution_type,
                .is_external = cached_result.is_external,
                .package_name = if (cached_result.package_name) |p| try self.allocator.dupe(u8, p) else null,
                .error_message = if (cached_result.error_message) |m| try self.allocator.dupe(u8, m) else null,
            };
            
            return result;
        }
        
        // Perform resolution based on import type and path characteristics
        var result = switch (import_type) {
            .zig_import => try self.resolveZigImport(from_file, import_path),
            .c_include => try self.resolveCInclude(from_file, import_path, false),
            .c_include_system => try self.resolveCInclude(from_file, import_path, true),
            .default_import, .named_import, .namespace_import, .side_effect_import, .dynamic_import => 
                try self.resolveJavaScriptImport(from_file, import_path),
            .re_export, .re_export_all => try self.resolveJavaScriptImport(from_file, import_path),
        };
        
        // Update stats
        if (result.isResolved()) {
            self.stats.successful_resolutions += 1;
            if (result.resolution_type == .relative_file or result.resolution_type == .absolute_file) {
                self.stats.relative_resolutions += 1;
            } else {
                self.stats.package_resolutions += 1;
            }
        } else {
            self.stats.failed_resolutions += 1;
        }
        
        // Cache the result
        const cache_key_owned = try self.allocator.dupe(u8, cache_key);
        const cached_result = ResolutionResult{
            .resolved_path = if (result.resolved_path) |p| try self.allocator.dupe(u8, p) else null,
            .resolution_type = result.resolution_type,
            .is_external = result.is_external,
            .package_name = if (result.package_name) |p| try self.allocator.dupe(u8, p) else null,
            .error_message = if (result.error_message) |m| try self.allocator.dupe(u8, m) else null,
        };
        try self.cache.put(cache_key_owned, cached_result);
        
        return result;
    }
    
    /// Resolve Zig import: @import("module")
    fn resolveZigImport(self: *Self, from_file: []const u8, import_path: []const u8) !ResolutionResult {
        // Check for built-in modules
        if (self.isZigBuiltinModule(import_path)) {
            return ResolutionResult{
                .resolved_path = try self.allocator.dupe(u8, import_path),
                .resolution_type = .builtin,
                .is_external = true,
                .package_name = try self.allocator.dupe(u8, "std"),
                .error_message = null,
            };
        }
        
        // Relative import
        if (std.mem.startsWith(u8, import_path, ".")) {
            return self.resolveRelativeImport(from_file, import_path);
        }
        
        // Package import - check configured Zig package paths
        for (self.config.zig_package_paths) |package_path| {
            const full_path = try path.joinPath(self.allocator, package_path, import_path);
            defer self.allocator.free(full_path);
            
            if (try self.tryResolveFile(full_path)) |resolved| {
                return ResolutionResult{
                    .resolved_path = resolved,
                    .resolution_type = .zig_package,
                    .is_external = true,
                    .package_name = try self.allocator.dupe(u8, import_path),
                    .error_message = null,
                };
            }
        }
        
        // Try relative to project root
        const project_relative = try path.joinPath(self.allocator, self.config.project_root, import_path);
        defer self.allocator.free(project_relative);
        
        if (try self.tryResolveFile(project_relative)) |resolved| {
            return ResolutionResult{
                .resolved_path = resolved,
                .resolution_type = .relative_file,
                .is_external = false,
                .package_name = null,
                .error_message = null,
            };
        }
        
        return ResolutionResult{
            .resolved_path = null,
            .resolution_type = .not_found,
            .is_external = false,
            .package_name = null,
            .error_message = try std.fmt.allocPrint(self.allocator, "Zig module '{}' not found", .{import_path}),
        };
    }
    
    /// Resolve JavaScript/TypeScript import
    fn resolveJavaScriptImport(self: *Self, from_file: []const u8, import_path: []const u8) !ResolutionResult {
        // Relative import
        if (std.mem.startsWith(u8, import_path, ".")) {
            return self.resolveRelativeImport(from_file, import_path);
        }
        
        // Absolute import
        if (std.mem.startsWith(u8, import_path, "/")) {
            if (try self.tryResolveFile(import_path)) |resolved| {
                return ResolutionResult{
                    .resolved_path = resolved,
                    .resolution_type = .absolute_file,
                    .is_external = false,
                    .package_name = null,
                    .error_message = null,
                };
            }
        }
        
        // TypeScript path mapping
        if (self.config.typescript_paths) |ts_paths| {
            if (try self.resolveTypeScriptPath(ts_paths, import_path)) |result| {
                return result;
            }
        }
        
        // Node module resolution
        return self.resolveNodeModule(from_file, import_path);
    }
    
    /// Resolve C/C++ include
    fn resolveCInclude(self: *Self, from_file: []const u8, import_path: []const u8, is_system: bool) !ResolutionResult {
        if (is_system) {
            // System include: search in include paths
            for (self.config.include_paths) |include_path| {
                const full_path = try path.joinPath(self.allocator, include_path, import_path);
                defer self.allocator.free(full_path);
                
                if (try self.tryResolveFile(full_path)) |resolved| {
                    return ResolutionResult{
                        .resolved_path = resolved,
                        .resolution_type = .system_include,
                        .is_external = true,
                        .package_name = null,
                        .error_message = null,
                    };
                }
            }
            
            return ResolutionResult{
                .resolved_path = null,
                .resolution_type = .not_found,
                .is_external = true,
                .package_name = null,
                .error_message = try std.fmt.allocPrint(self.allocator, "System header '{}' not found", .{import_path}),
            };
        } else {
            // Local include: relative to current file
            return self.resolveRelativeInclude(from_file, import_path);
        }
    }
    
    /// Resolve relative import (./file or ../file)
    fn resolveRelativeImport(self: *Self, from_file: []const u8, import_path: []const u8) !ResolutionResult {
        const from_dir = std.fs.path.dirname(from_file) orelse ".";
        const full_path = try path.joinPath(self.allocator, from_dir, import_path);
        defer self.allocator.free(full_path);
        
        if (try self.tryResolveFile(full_path)) |resolved| {
            return ResolutionResult{
                .resolved_path = resolved,
                .resolution_type = .relative_file,
                .is_external = false,
                .package_name = null,
                .error_message = null,
            };
        }
        
        return ResolutionResult{
            .resolved_path = null,
            .resolution_type = .not_found,
            .is_external = false,
            .package_name = null,
            .error_message = try std.fmt.allocPrint(self.allocator, "Relative import '{}' not found from '{}'", .{ import_path, from_file }),
        };
    }
    
    /// Resolve relative include for C/C++
    fn resolveRelativeInclude(self: *Self, from_file: []const u8, import_path: []const u8) !ResolutionResult {
        const from_dir = std.fs.path.dirname(from_file) orelse ".";
        const full_path = try path.joinPath(self.allocator, from_dir, import_path);
        defer self.allocator.free(full_path);
        
        if (try self.tryResolveFile(full_path)) |resolved| {
            return ResolutionResult{
                .resolved_path = resolved,
                .resolution_type = .local_include,
                .is_external = false,
                .package_name = null,
                .error_message = null,
            };
        }
        
        return ResolutionResult{
            .resolved_path = null,
            .resolution_type = .not_found,
            .is_external = false,
            .package_name = null,
            .error_message = try std.fmt.allocPrint(self.allocator, "Local include '{}' not found from '{}'", .{ import_path, from_file }),
        };
    }
    
    /// Resolve Node.js module
    fn resolveNodeModule(self: *Self, from_file: []const u8, import_path: []const u8) !ResolutionResult {
        // Extract package name from import path
        const package_name = self.extractPackageName(import_path);
        
        // Search in node_modules directories starting from current file's directory
        var current_dir = std.fs.path.dirname(from_file) orelse ".";
        var depth: u32 = 0;
        
        while (depth < self.config.max_resolution_depth) : (depth += 1) {
            // Try configured node_modules paths
            for (self.config.node_modules_paths) |node_modules_path| {
                const module_path = try path.joinPath(self.allocator, node_modules_path, import_path);
                defer self.allocator.free(module_path);
                
                if (try self.tryResolveNodeModule(module_path)) |resolved| {
                    return ResolutionResult{
                        .resolved_path = resolved,
                        .resolution_type = .node_module,
                        .is_external = true,
                        .package_name = try self.allocator.dupe(u8, package_name),
                        .error_message = null,
                    };
                }
            }
            
            // Try node_modules in current directory
            const node_modules_path = try path.joinPath(self.allocator, current_dir, "node_modules");
            defer self.allocator.free(node_modules_path);
            
            const module_path = try path.joinPath(self.allocator, node_modules_path, import_path);
            defer self.allocator.free(module_path);
            
            if (try self.tryResolveNodeModule(module_path)) |resolved| {
                return ResolutionResult{
                    .resolved_path = resolved,
                    .resolution_type = .node_module,
                    .is_external = true,
                    .package_name = try self.allocator.dupe(u8, package_name),
                    .error_message = null,
                };
            }
            
            // Move up one directory
            const parent = std.fs.path.dirname(current_dir);
            if (parent == null or std.mem.eql(u8, parent.?, current_dir)) {
                break; // Reached root
            }
            current_dir = parent.?;
        }
        
        return ResolutionResult{
            .resolved_path = null,
            .resolution_type = .not_found,
            .is_external = true,
            .package_name = try self.allocator.dupe(u8, package_name),
            .error_message = try std.fmt.allocPrint(self.allocator, "Node module '{}' not found", .{import_path}),
        };
    }
    
    /// Resolve TypeScript path mapping
    fn resolveTypeScriptPath(self: *Self, ts_paths: ResolverConfig.TypeScriptPaths, import_path: []const u8) !?ResolutionResult {
        var best_match: ?[]const u8 = null;
        var best_match_paths: ?[][]const u8 = null;
        
        // Find the best matching path pattern
        var iter = ts_paths.paths.iterator();
        while (iter.next()) |entry| {
            const pattern = entry.key_ptr.*;
            const paths = entry.value_ptr.*;
            
            if (self.matchesTypeScriptPattern(import_path, pattern)) {
                if (best_match == null or pattern.len > best_match.?.len) {
                    best_match = pattern;
                    best_match_paths = paths;
                }
            }
        }
        
        if (best_match) |pattern| {
            if (best_match_paths) |paths| {
                // Try each mapped path
                for (paths) |mapped_path| {
                    const resolved_path = try self.substituteTypeScriptPath(import_path, pattern, mapped_path);
                    defer self.allocator.free(resolved_path);
                    
                    const absolute_path = try path.joinPath(self.allocator, ts_paths.base_url, resolved_path);
                    defer self.allocator.free(absolute_path);
                    
                    if (try self.tryResolveFile(absolute_path)) |final_path| {
                        return ResolutionResult{
                            .resolved_path = final_path,
                            .resolution_type = .relative_file,
                            .is_external = false,
                            .package_name = null,
                            .error_message = null,
                        };
                    }
                }
            }
        }
        
        return null;
    }
    
    /// Try to resolve a file with various extensions
    fn tryResolveFile(self: *Self, base_path: []const u8) !?[]const u8 {
        // Try exact path first
        if (self.fileExists(base_path)) {
            return try self.allocator.dupe(u8, base_path);
        }
        
        // Try with extensions
        for (self.config.extensions) |ext| {
            const path_with_ext = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ base_path, ext });
            defer self.allocator.free(path_with_ext);
            
            if (self.fileExists(path_with_ext)) {
                return try self.allocator.dupe(u8, path_with_ext);
            }
        }
        
        // Try index files in directory
        if (self.isDirectory(base_path)) {
            const index_files = [_][]const u8{ "index", "mod", "main" };
            for (index_files) |index_name| {
                for (self.config.extensions) |ext| {
                    const index_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}{s}", .{ base_path, index_name, ext });
                    defer self.allocator.free(index_path);
                    
                    if (self.fileExists(index_path)) {
                        return try self.allocator.dupe(u8, index_path);
                    }
                }
            }
        }
        
        return null;
    }
    
    /// Try to resolve a Node.js module with package.json support
    fn tryResolveNodeModule(self: *Self, module_path: []const u8) !?[]const u8 {
        // Try direct file resolution first
        if (try self.tryResolveFile(module_path)) |resolved| {
            return resolved;
        }
        
        // Check if this is a directory with package.json
        if (self.isDirectory(module_path)) {
            const package_json_path = try path.joinPath(self.allocator, module_path, "package.json");
            defer self.allocator.free(package_json_path);
            
            if (self.fileExists(package_json_path)) {
                // Parse package.json to find main entry point
                if (try self.parsePackageJsonMain(package_json_path)) |main_file| {
                    defer self.allocator.free(main_file);
                    
                    const main_path = try path.joinPath(self.allocator, module_path, main_file);
                    defer self.allocator.free(main_path);
                    
                    if (try self.tryResolveFile(main_path)) |resolved| {
                        return resolved;
                    }
                }
            }
            
            // Fallback to index files
            return self.tryResolveFile(module_path);
        }
        
        return null;
    }
    
    /// Parse package.json to extract main entry point
    fn parsePackageJsonMain(self: *Self, package_json_path: []const u8) !?[]const u8 {
        const content = file_helpers.FileHelpers.readFileOptional(self.allocator, package_json_path) catch return null;
        defer self.allocator.free(content);
        
        // Simple JSON parsing to extract "main" field
        // Note: This is a simplified parser. In production, would use a proper JSON parser
        if (std.mem.indexOf(u8, content, "\"main\"")) |main_pos| {
            const colon_pos = std.mem.indexOf(u8, content[main_pos..], ":") orelse return null;
            const value_start = main_pos + colon_pos + 1;
            
            // Skip whitespace and find quote
            var pos = value_start;
            while (pos < content.len and (content[pos] == ' ' or content[pos] == '\t' or content[pos] == '\n')) {
                pos += 1;
            }
            
            if (pos < content.len and content[pos] == '"') {
                pos += 1; // Skip opening quote
                const value_end = std.mem.indexOf(u8, content[pos..], "\"") orelse return null;
                const main_value = content[pos..pos + value_end];
                return try self.allocator.dupe(u8, main_value);
            }
        }
        
        return null;
    }
    
    // Utility methods
    
    fn createCacheKey(self: *Self, from_file: []const u8, import_path: []const u8, import_type: ImportType) ![]const u8 {
        return try std.fmt.allocPrint(self.allocator, "{}:{}:{}", .{ from_file, import_path, @intFromEnum(import_type) });
    }
    
    fn isZigBuiltinModule(self: *Self, import_path: []const u8) bool {
        _ = self;
        const builtin_modules = [_][]const u8{ "std", "builtin", "root" };
        for (builtin_modules) |builtin| {
            if (std.mem.eql(u8, import_path, builtin)) {
                return true;
            }
        }
        return false;
    }
    
    fn extractPackageName(self: *Self, import_path: []const u8) []const u8 {
        _ = self;
        // Extract package name from import path like "@scope/package/subpath" -> "@scope/package"
        if (std.mem.startsWith(u8, import_path, "@")) {
            // Scoped package
            const first_slash = std.mem.indexOf(u8, import_path, "/") orelse return import_path;
            const second_slash = std.mem.indexOf(u8, import_path[first_slash + 1..], "/");
            if (second_slash) |pos| {
                return import_path[0..first_slash + 1 + pos];
            }
            return import_path;
        } else {
            // Regular package
            const slash_pos = std.mem.indexOf(u8, import_path, "/") orelse return import_path;
            return import_path[0..slash_pos];
        }
    }
    
    fn matchesTypeScriptPattern(self: *Self, import_path: []const u8, pattern: []const u8) bool {
        _ = self;
        // Simple pattern matching - in production would support full glob patterns
        if (std.mem.endsWith(u8, pattern, "*")) {
            const prefix = pattern[0..pattern.len - 1];
            return std.mem.startsWith(u8, import_path, prefix);
        }
        return std.mem.eql(u8, import_path, pattern);
    }
    
    fn substituteTypeScriptPath(self: *Self, import_path: []const u8, pattern: []const u8, mapped_path: []const u8) ![]const u8 {
        if (std.mem.endsWith(u8, pattern, "*") and std.mem.endsWith(u8, mapped_path, "*")) {
            const pattern_prefix = pattern[0..pattern.len - 1];
            const mapped_prefix = mapped_path[0..mapped_path.len - 1];
            
            if (std.mem.startsWith(u8, import_path, pattern_prefix)) {
                const suffix = import_path[pattern_prefix.len..];
                return try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ mapped_prefix, suffix });
            }
        }
        
        return try self.allocator.dupe(u8, mapped_path);
    }
    
    fn fileExists(self: *Self, file_path: []const u8) bool {
        _ = self;
        std.fs.cwd().access(file_path, .{}) catch return false;
        return true;
    }
    
    fn isDirectory(self: *Self, dir_path: []const u8) bool {
        _ = self;
        const stat = std.fs.cwd().statFile(dir_path) catch return false;
        return stat.kind == .directory;
    }
    
    /// Get resolver statistics
    pub fn getStats(self: *Self) ResolverStats {
        return self.stats;
    }
    
    /// Clear resolution cache
    pub fn clearCache(self: *Self) void {
        var iter = self.cache.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            var mutable_result = entry.value_ptr.*;
            mutable_result.deinit(self.allocator);
        }
        self.cache.clearAndFree();
    }
    
    /// Batch resolve multiple imports for better performance
    pub fn resolveBatch(self: *Self, imports: []const struct { from_file: []const u8, import_path: []const u8, import_type: ImportType }) ![]ResolutionResult {
        var results = try self.allocator.alloc(ResolutionResult, imports.len);
        
        for (imports, 0..) |import_item, i| {
            results[i] = try self.resolve(import_item.from_file, import_item.import_path, import_item.import_type);
        }
        
        return results;
    }
    
    /// Add a custom resolution path for testing or special cases
    pub fn addCustomResolution(self: *Self, from_file: []const u8, import_path: []const u8, import_type: ImportType, resolved_path: []const u8) !void {
        const cache_key = try self.createCacheKey(from_file, import_path, import_type);
        
        const result = ResolutionResult{
            .resolved_path = try self.allocator.dupe(u8, resolved_path),
            .resolution_type = .relative_file,
            .is_external = false,
            .package_name = null,
            .error_message = null,
        };
        
        try self.cache.put(cache_key, result);
    }
};

// Tests
test "import resolver initialization" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    var config = try ResolverConfig.default(allocator, "/project/root");
    defer config.deinit(allocator); // We retain ownership
    
    var resolver = try ImportResolver.initBorrowing(allocator, &config);
    defer resolver.deinit(); // Resolver cleans up its own copy
    
    try testing.expect(resolver.stats.total_resolutions == 0);
}

test "zig builtin module detection" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    var config = try ResolverConfig.default(allocator, "/project/root");
    defer config.deinit(allocator); // We retain ownership
    
    var resolver = try ImportResolver.initBorrowing(allocator, &config);
    defer resolver.deinit(); // Resolver cleans up its own copy
    
    try testing.expect(resolver.isZigBuiltinModule("std"));
    try testing.expect(resolver.isZigBuiltinModule("builtin"));
    try testing.expect(!resolver.isZigBuiltinModule("custom"));
}

test "package name extraction" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    var config = try ResolverConfig.default(allocator, "/project/root");
    defer config.deinit(allocator); // We retain ownership
    
    var resolver = try ImportResolver.initBorrowing(allocator, &config);
    defer resolver.deinit(); // Resolver cleans up its own copy
    
    try testing.expect(std.mem.eql(u8, resolver.extractPackageName("lodash"), "lodash"));
    try testing.expect(std.mem.eql(u8, resolver.extractPackageName("lodash/map"), "lodash"));
    try testing.expect(std.mem.eql(u8, resolver.extractPackageName("@types/node"), "@types/node"));
    try testing.expect(std.mem.eql(u8, resolver.extractPackageName("@types/node/fs"), "@types/node"));
}

test "resolution result lifecycle" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    var result = ResolutionResult{
        .resolved_path = try allocator.dupe(u8, "/test/path"),
        .resolution_type = .relative_file,
        .is_external = false,
        .package_name = try allocator.dupe(u8, "test"),
        .error_message = null,
    };
    defer result.deinit(allocator);
    
    try testing.expect(result.isResolved());
    try testing.expect(std.mem.eql(u8, result.resolved_path.?, "/test/path"));
}