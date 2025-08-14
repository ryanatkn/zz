const std = @import("std");
const AstCache = @import("cache.zig").AstCache;
const AstCacheKey = @import("cache.zig").AstCacheKey;
const imports_mod = @import("imports.zig");
const ImportInfo = imports_mod.Import;
const ExtractionResult = imports_mod.ExtractionResult;
const TreeSitterParser = @import("tree_sitter_parser.zig").TreeSitterParser;
const ast = @import("ast.zig");
const Language = ast.Language;
const io = @import("io.zig");
const errors = @import("errors.zig");

/// Enhanced file state for incremental processing with detailed import analysis
pub const FileState = struct {
    path: []const u8,
    hash: u64,                      // Content hash using xxHash
    mtime: i64,                     // Modification time (nanoseconds since epoch)
    size: usize,                    // File size in bytes
    language: Language,             // Detected programming language
    ast_cache_key: ?u64,            // Reference to cached AST
    
    // Enhanced import tracking with AST analysis
    imports_detailed: []ImportInfo,     // Detailed AST-extracted imports
    exports_detailed: []@import("import_extractor.zig").ExportInfo, // Detailed exports
    resolved_dependencies: [][]const u8, // Resolved file paths this file depends on
    unresolved_dependencies: [][]const u8, // External/unresolved dependencies
    dependents: [][]const u8,       // Files that depend on this file
    
    // Legacy fields for backward compatibility
    imports: [][]const u8,          // Simple import paths (derived from imports_detailed)
    exports: [][]const u8,          // Simple export names (derived from exports_detailed)
    
    // Import analysis metadata
    import_hash: ?u64,              // Hash of import structure for change detection
    last_import_analysis: i64,      // When imports were last analyzed
    
    pub fn deinit(self: *FileState, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
        
        // Clean up detailed imports
        for (self.imports_detailed) |*import_info| {
            import_info.deinit(allocator);
        }
        allocator.free(self.imports_detailed);
        
        // Clean up detailed exports
        for (self.exports_detailed) |*export_info| {
            export_info.deinit(allocator);
        }
        allocator.free(self.exports_detailed);
        
        // Clean up resolved dependencies
        for (self.resolved_dependencies) |dependency| {
            allocator.free(dependency);
        }
        allocator.free(self.resolved_dependencies);
        
        // Clean up unresolved dependencies
        for (self.unresolved_dependencies) |dependency| {
            allocator.free(dependency);
        }
        allocator.free(self.unresolved_dependencies);
        
        // Clean up dependents
        for (self.dependents) |dependent| {
            allocator.free(dependent);
        }
        allocator.free(self.dependents);
        
        // Clean up legacy fields
        for (self.imports) |import| {
            allocator.free(import);
        }
        allocator.free(self.imports);
        
        for (self.exports) |export_name| {
            allocator.free(export_name);
        }
        allocator.free(self.exports);
    }
    
    /// Update legacy import/export fields from detailed analysis
    pub fn updateLegacyFields(self: *FileState, allocator: std.mem.Allocator) !void {
        // Free existing legacy fields
        for (self.imports) |import| {
            allocator.free(import);
        }
        allocator.free(self.imports);
        
        for (self.exports) |export_name| {
            allocator.free(export_name);
        }
        allocator.free(self.exports);
        
        // Create new legacy fields from detailed analysis
        var import_paths = std.ArrayList([]const u8).init(allocator);
        defer import_paths.deinit();
        
        for (self.imports_detailed) |import_info| {
            try import_paths.append(try allocator.dupe(u8, import_info.import_path));
        }
        self.imports = try import_paths.toOwnedSlice();
        
        var export_names = std.ArrayList([]const u8).init(allocator);
        defer export_names.deinit();
        
        for (self.exports_detailed) |export_info| {
            if (export_info.is_default) {
                try export_names.append(try allocator.dupe(u8, "default"));
            }
            // Add more export name extraction logic as needed
        }
        self.exports = try export_names.toOwnedSlice();
    }
    
    /// Check if imports have changed by comparing hash
    pub fn importsChanged(self: FileState, new_import_hash: u64) bool {
        return self.import_hash == null or self.import_hash.? != new_import_hash;
    }
    
    /// Get all dependency file paths (resolved + unresolved)
    pub fn getAllDependencies(self: FileState, allocator: std.mem.Allocator) ![][]const u8 {
        var all_deps = std.ArrayList([]const u8).init(allocator);
        defer all_deps.deinit();
        
        for (self.resolved_dependencies) |dep| {
            try all_deps.append(try allocator.dupe(u8, dep));
        }
        
        for (self.unresolved_dependencies) |dep| {
            try all_deps.append(try allocator.dupe(u8, dep));
        }
        
        return all_deps.toOwnedSlice();
    }
};

/// Enhanced dependency graph with AST-based import analysis
pub const DependencyGraph = struct {
    allocator: std.mem.Allocator,
    // path -> set of paths that depend on it
    dependents: std.HashMap([]const u8, std.ArrayList([]const u8), std.hash_map.StringContext, 80),
    // path -> set of paths it depends on
    dependencies: std.HashMap([]const u8, std.ArrayList([]const u8), std.hash_map.StringContext, 80),
    
    // Enhanced AST-based analysis
    import_extractor: imports_mod.Extractor,
    import_resolver: ImportResolver,
    
    // Circular dependency tracking
    circular_dependencies: std.ArrayList([][]const u8),
    
    // Statistics
    stats: DependencyStats,
    
    pub const DependencyStats = struct {
        total_files: u64 = 0,
        total_dependencies: u64 = 0,
        resolved_dependencies: u64 = 0,
        unresolved_dependencies: u64 = 0,
        circular_dependency_count: u64 = 0,
        ast_analysis_time_ns: u64 = 0,
        resolution_time_ns: u64 = 0,
        
        pub fn resolutionRate(self: DependencyStats) f64 {
            if (self.total_dependencies == 0) return 0.0;
            return @as(f64, @floatFromInt(self.resolved_dependencies)) / @as(f64, @floatFromInt(self.total_dependencies));
        }
    };

    pub fn init(allocator: std.mem.Allocator, project_root: []const u8) !DependencyGraph {
        const resolver_config = try ResolverConfig.default(allocator, project_root);
        
        return DependencyGraph{
            .allocator = allocator,
            .dependents = std.HashMap([]const u8, std.ArrayList([]const u8), std.hash_map.StringContext, 80).init(allocator),
            .dependencies = std.HashMap([]const u8, std.ArrayList([]const u8), std.hash_map.StringContext, 80).init(allocator),
            .import_extractor = imports_mod.Extractor.init(allocator),
            .import_resolver = ImportResolver.init(allocator, resolver_config),
            .circular_dependencies = std.ArrayList([][]const u8).init(allocator),
            .stats = DependencyStats{},
        };
    }
    
    pub fn initWithCache(allocator: std.mem.Allocator, project_root: []const u8, cache: *AstCache) !DependencyGraph {
        const resolver_config = try ResolverConfig.default(allocator, project_root);
        
        return DependencyGraph{
            .allocator = allocator,
            .dependents = std.HashMap([]const u8, std.ArrayList([]const u8), std.hash_map.StringContext, 80).init(allocator),
            .dependencies = std.HashMap([]const u8, std.ArrayList([]const u8), std.hash_map.StringContext, 80).init(allocator),
            .import_extractor = imports_mod.Extractor.initWithCache(allocator, cache),
            .import_resolver = ImportResolver.init(allocator, resolver_config),
            .circular_dependencies = std.ArrayList([][]const u8).init(allocator),
            .stats = DependencyStats{},
        };
    }

    pub fn deinit(self: *DependencyGraph) void {
        var dep_iter = self.dependents.iterator();
        while (dep_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            // Free all strings in the ArrayList
            for (entry.value_ptr.items) |item| {
                self.allocator.free(item);
            }
            entry.value_ptr.deinit();
        }
        self.dependents.deinit();

        var deps_iter = self.dependencies.iterator();
        while (deps_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            // Free all strings in the ArrayList
            for (entry.value_ptr.items) |item| {
                self.allocator.free(item);
            }
            entry.value_ptr.deinit();
        }
        self.dependencies.deinit();
        
        // Clean up AST-based analysis components
        self.import_resolver.deinit();
        
        // Clean up circular dependencies
        for (self.circular_dependencies.items) |circular_chain| {
            for (circular_chain) |file_path| {
                self.allocator.free(file_path);
            }
            self.allocator.free(circular_chain);
        }
        self.circular_dependencies.deinit();
    }

    /// Add a dependency relationship: from_file depends on to_file
    pub fn addDependency(self: *DependencyGraph, from_file: []const u8, to_file: []const u8) !void {
        // Add to dependencies map (from_file -> to_file)
        const from_key = try self.allocator.dupe(u8, from_file);
        const to_key = try self.allocator.dupe(u8, to_file);
        
        var result = try self.dependencies.getOrPut(from_key);
        if (!result.found_existing) {
            result.value_ptr.* = std.ArrayList([]const u8).init(self.allocator);
        }
        try result.value_ptr.append(to_key);

        // Add to dependents map (to_file -> from_file)
        const to_key_dup = try self.allocator.dupe(u8, to_file);
        const from_key_dup = try self.allocator.dupe(u8, from_file);
        
        var dependents_result = try self.dependents.getOrPut(to_key_dup);
        if (!dependents_result.found_existing) {
            dependents_result.value_ptr.* = std.ArrayList([]const u8).init(self.allocator);
        }
        try dependents_result.value_ptr.append(from_key_dup);
    }

    /// Get all files that depend on the given file (directly or indirectly)
    pub fn getDependents(self: *DependencyGraph, file_path: []const u8, result: *std.ArrayList([]const u8)) !void {
        var visited = std.HashMap([]const u8, void, std.hash_map.StringContext, 80).init(self.allocator);
        defer visited.deinit();
        
        try self.getDependentsRecursive(file_path, &visited, result);
    }

    fn getDependentsRecursive(self: *DependencyGraph, file_path: []const u8, visited: *std.HashMap([]const u8, void, std.hash_map.StringContext, 80), result: *std.ArrayList([]const u8)) !void {
        if (visited.contains(file_path)) return;
        try visited.put(file_path, {});

        if (self.dependents.get(file_path)) |direct_dependents| {
            for (direct_dependents.items) |dependent| {
                try result.append(dependent);
                try self.getDependentsRecursive(dependent, visited, result);
            }
        }
    }
    
    /// Analyze file with AST-based import extraction and resolution
    pub fn analyzeFile(self: *DependencyGraph, file_path: []const u8, source: []const u8) !FileState {
        const start_time = std.time.nanoTimestamp();
        
        // Extract imports and exports using AST analysis
        const extraction_result = try self.import_extractor.extract(file_path, source);
        defer extraction_result.deinit(self.allocator);
        
        const ast_analysis_time = std.time.nanoTimestamp() - start_time;
        self.stats.ast_analysis_time_ns += @intCast(ast_analysis_time);
        
        const resolution_start = std.time.nanoTimestamp();
        
        // Resolve import paths to actual files
        var resolved_dependencies = std.ArrayList([]const u8).init(self.allocator);
        defer resolved_dependencies.deinit();
        
        var unresolved_dependencies = std.ArrayList([]const u8).init(self.allocator);
        defer unresolved_dependencies.deinit();
        
        for (extraction_result.imports) |import_info| {
            const resolution = try self.import_resolver.resolve(file_path, import_info.import_path, import_info.import_type);
            defer resolution.deinit(self.allocator);
            
            if (resolution.isResolved()) {
                if (resolution.resolved_path) |resolved_path| {
                    try resolved_dependencies.append(try self.allocator.dupe(u8, resolved_path));
                    self.stats.resolved_dependencies += 1;
                }
            } else {
                try unresolved_dependencies.append(try self.allocator.dupe(u8, import_info.import_path));
                self.stats.unresolved_dependencies += 1;
            }
            
            self.stats.total_dependencies += 1;
        }
        
        const resolution_time = std.time.nanoTimestamp() - resolution_start;
        self.stats.resolution_time_ns += @intCast(resolution_time);
        
        // Detect language from file extension
        const language = Language.fromExtension(std.fs.path.extension(file_path));
        
        // Calculate import hash for change detection
        const import_hash = self.calculateImportHash(extraction_result.imports);
        
        // Create detailed file state
        var file_state = FileState{
            .path = try self.allocator.dupe(u8, file_path),
            .hash = try hashFile(self.allocator, file_path),
            .mtime = try getFileModTime(file_path),
            .size = try getFileSize(file_path),
            .language = language,
            .ast_cache_key = null,
            .imports_detailed = try self.duplicateImports(extraction_result.imports),
            .exports_detailed = try self.duplicateExports(extraction_result.exports),
            .resolved_dependencies = try resolved_dependencies.toOwnedSlice(),
            .unresolved_dependencies = try unresolved_dependencies.toOwnedSlice(),
            .dependents = &.{},
            .imports = &.{}, // Will be updated by updateLegacyFields
            .exports = &.{}, // Will be updated by updateLegacyFields
            .import_hash = import_hash,
            .last_import_analysis = std.time.nanoTimestamp(),
        };
        
        // Update legacy fields for backward compatibility
        try file_state.updateLegacyFields(self.allocator);
        
        self.stats.total_files += 1;
        
        return file_state;
    }
    
    /// Batch analyze multiple files for better performance
    pub fn analyzeFiles(self: *DependencyGraph, file_paths: []const []const u8) ![]FileState {
        var file_states = try self.allocator.alloc(FileState, file_paths.len);
        
        for (file_paths, 0..) |file_path, i| {
            const source = io.readFileRequired(self.allocator, file_path) catch {
                // Skip files that can't be read
                continue;
            };
            defer self.allocator.free(source);
            
            file_states[i] = try self.analyzeFile(file_path, source);
        }
        
        return file_states;
    }
    
    /// Update dependency graph with analyzed file
    pub fn updateWithFileState(self: *DependencyGraph, file_state: FileState) !void {
        // Add dependencies to the graph
        for (file_state.resolved_dependencies) |dependency| {
            try self.addDependency(file_state.path, dependency);
        }
        
        // Check for circular dependencies
        try self.detectCircularDependencies(file_state.path);
    }
    
    /// Detect circular dependencies starting from a file
    fn detectCircularDependencies(self: *DependencyGraph, start_file: []const u8) !void {
        var visited = std.HashMap([]const u8, void, std.hash_map.StringContext, 80).init(self.allocator);
        defer visited.deinit();
        
        var path_stack = std.ArrayList([]const u8).init(self.allocator);
        defer path_stack.deinit();
        
        try self.detectCircularDependenciesRecursive(start_file, &visited, &path_stack);
    }
    
    fn detectCircularDependenciesRecursive(self: *DependencyGraph, file_path: []const u8, visited: *std.HashMap([]const u8, void, std.hash_map.StringContext, 80), path_stack: *std.ArrayList([]const u8)) !void {
        // Check if we've seen this file in the current path
        for (path_stack.items) |stack_file| {
            if (std.mem.eql(u8, stack_file, file_path)) {
                // Found circular dependency - record it
                var circular_chain = try self.allocator.alloc([]const u8, path_stack.items.len + 1);
                
                for (path_stack.items, 0..) |stack_item, i| {
                    circular_chain[i] = try self.allocator.dupe(u8, stack_item);
                }
                circular_chain[path_stack.items.len] = try self.allocator.dupe(u8, file_path);
                
                try self.circular_dependencies.append(circular_chain);
                self.stats.circular_dependency_count += 1;
                return;
            }
        }
        
        if (visited.contains(file_path)) return;
        try visited.put(file_path, {});
        try path_stack.append(file_path);
        
        // Check dependencies
        if (self.dependencies.get(file_path)) |deps| {
            for (deps.items) |dependency| {
                try self.detectCircularDependenciesRecursive(dependency, visited, path_stack);
            }
        }
        
        _ = path_stack.pop();
    }
    
    /// Calculate hash of import structure for change detection
    fn calculateImportHash(self: *DependencyGraph, imports: []const ImportInfo) u64 {
        _ = self;
        var hasher = std.hash.XxHash64.init(0);
        
        for (imports) |import_info| {
            hasher.update(import_info.import_path);
            hasher.update(std.mem.asBytes(&import_info.import_type));
            hasher.update(std.mem.asBytes(&import_info.line_number));
            hasher.update(std.mem.asBytes(&import_info.is_dynamic));
            hasher.update(std.mem.asBytes(&import_info.is_type_only));
        }
        
        return hasher.final();
    }
    
    /// Create deep copies of imports for file state
    fn duplicateImports(self: *DependencyGraph, imports: []const ImportInfo) ![]ImportInfo {
        var duplicated = try self.allocator.alloc(ImportInfo, imports.len);
        
        for (imports, 0..) |import_info, i| {
            var symbols = try self.allocator.alloc(@import("import_extractor.zig").ImportedSymbol, import_info.symbols.len);
            for (import_info.symbols, 0..) |symbol, j| {
                symbols[j] = @import("import_extractor.zig").ImportedSymbol{
                    .name = try self.allocator.dupe(u8, symbol.name),
                    .alias = if (symbol.alias) |alias| try self.allocator.dupe(u8, alias) else null,
                    .is_type = symbol.is_type,
                    .line_number = symbol.line_number,
                };
            }
            
            duplicated[i] = ImportInfo{
                .source_file = try self.allocator.dupe(u8, import_info.source_file),
                .import_path = try self.allocator.dupe(u8, import_info.import_path),
                .resolved_path = if (import_info.resolved_path) |path| try self.allocator.dupe(u8, path) else null,
                .import_type = import_info.import_type,
                .symbols = symbols,
                .default_import = if (import_info.default_import) |default| try self.allocator.dupe(u8, default) else null,
                .namespace_import = if (import_info.namespace_import) |namespace| try self.allocator.dupe(u8, namespace) else null,
                .line_number = import_info.line_number,
                .is_dynamic = import_info.is_dynamic,
                .is_type_only = import_info.is_type_only,
            };
        }
        
        return duplicated;
    }
    
    /// Create deep copies of exports for file state
    fn duplicateExports(self: *DependencyGraph, exports: []const @import("import_extractor.zig").ExportInfo) ![]@import("import_extractor.zig").ExportInfo {
        var duplicated = try self.allocator.alloc(@import("import_extractor.zig").ExportInfo, exports.len);
        
        for (exports, 0..) |export_info, i| {
            var symbols = try self.allocator.alloc(@import("import_extractor.zig").ImportedSymbol, export_info.symbols.len);
            for (export_info.symbols, 0..) |symbol, j| {
                symbols[j] = @import("import_extractor.zig").ImportedSymbol{
                    .name = try self.allocator.dupe(u8, symbol.name),
                    .alias = if (symbol.alias) |alias| try self.allocator.dupe(u8, alias) else null,
                    .is_type = symbol.is_type,
                    .line_number = symbol.line_number,
                };
            }
            
            duplicated[i] = @import("import_extractor.zig").ExportInfo{
                .source_file = try self.allocator.dupe(u8, export_info.source_file),
                .export_path = if (export_info.export_path) |path| try self.allocator.dupe(u8, path) else null,
                .symbols = symbols,
                .is_default = export_info.is_default,
                .is_namespace = export_info.is_namespace,
                .line_number = export_info.line_number,
            };
        }
        
        return duplicated;
    }
    
    /// Get dependency analysis statistics
    pub fn getStats(self: *DependencyGraph) DependencyStats {
        return self.stats;
    }
    
    /// Check if there are circular dependencies
    pub fn hasCircularDependencies(self: *DependencyGraph) bool {
        return self.circular_dependencies.items.len > 0;
    }
    
    /// Get all circular dependency chains
    pub fn getCircularDependencies(self: *DependencyGraph) []const [][]const u8 {
        return self.circular_dependencies.items;
    }
};

/// Change detection result
pub const ChangeType = enum {
    unchanged,      // File hasn't changed
    content,        // File content changed
    dependencies,   // File dependencies changed (imports/exports)
    new,           // New file
    deleted,       // File was deleted
};

pub const FileChange = struct {
    path: []const u8,
    change_type: ChangeType,
    old_state: ?FileState,
    new_state: ?FileState,
};

/// Fast file hashing using xxHash - now using shared file helpers
pub fn hashFile(allocator: std.mem.Allocator, file_path: []const u8) !u64 {
    return io.hashFile(allocator, file_path);
}

/// Get file modification time in nanoseconds since epoch - using shared file helpers
pub fn getFileModTime(file_path: []const u8) !i64 {
    if (try io.getModTime(file_path)) |mtime| {
        return mtime * std.time.ns_per_s; // Convert to nanoseconds
    }
    return 0;
}

/// Get file size
pub fn getFileSize(file_path: []const u8) !usize {
    const stat = std.fs.cwd().statFile(file_path) catch |err| switch (err) {
        error.FileNotFound => return 0,
        else => return err,
    };
    
    return @intCast(stat.size);
}

/// File change detector for incremental processing
pub const ChangeDetector = struct {
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) ChangeDetector {
        return ChangeDetector{
            .allocator = allocator,
        };
    }

    /// Detect changes between old and new file states - using improved error handling
    pub fn detectFileChange(self: *ChangeDetector, file_path: []const u8, old_state: ?FileState) !FileChange {
        // Check if file still exists using enhanced error handling
        // Try to get file modification time
        const new_mtime = getFileModTime(file_path) catch |err| {
            if (err == error.FileNotFound) {
                return FileChange{
                    .path = file_path,
                    .change_type = if (old_state != null) .deleted else .unchanged,
                    .old_state = old_state,
                    .new_state = null,
                };
            }
            return err;
        };

        // If we have no old state, this is a new file
        if (old_state == null) {
            const new_hash = try hashFile(self.allocator, file_path);
            const new_size = try getFileSize(file_path);
            const path_copy = try self.allocator.dupe(u8, file_path);
            
            return FileChange{
                .path = file_path,
                .change_type = .new,
                .old_state = null,
                .new_state = FileState{
                    .path = path_copy,
                    .hash = new_hash,
                    .mtime = new_mtime,
                    .size = new_size,
                    .language = .unknown,
                    .ast_cache_key = null,
                    .imports_detailed = &.{},
                    .exports_detailed = &.{},
                    .resolved_dependencies = &.{},
                    .unresolved_dependencies = &.{},
                    .dependents = &.{},
                    .imports = &.{},
                    .exports = &.{},
                    .import_hash = null,
                    .last_import_analysis = 0,
                },
            };
        }

        const old = old_state.?;

        // Fast path: check modification time and size first
        const new_size = try getFileSize(file_path);
        if (new_mtime == old.mtime and new_size == old.size) {
            return FileChange{
                .path = file_path,
                .change_type = .unchanged,
                .old_state = old_state,
                .new_state = old_state,
            };
        }

        // Content might have changed, compute hash
        const new_hash = try hashFile(self.allocator, file_path);
        if (new_hash == old.hash) {
            // File touched but content unchanged
            return FileChange{
                .path = file_path,
                .change_type = .unchanged,
                .old_state = old_state,
                .new_state = old_state,
            };
        }

        // Content changed - need to determine if dependencies changed too
        // For now, assume content change (dependency analysis comes later)
        const path_copy = try self.allocator.dupe(u8, file_path);
        return FileChange{
            .path = file_path,
            .change_type = .content,
            .old_state = old_state,
            .new_state = FileState{
                .path = path_copy,
                .hash = new_hash,
                .mtime = new_mtime,
                .size = new_size,
                .language = .unknown,
                .ast_cache_key = null, // Will be updated after parsing
                .imports_detailed = &.{},      // Will be updated after analysis
                .exports_detailed = &.{},      // Will be updated after analysis
                .resolved_dependencies = &.{}, // Will be updated after analysis
                .unresolved_dependencies = &.{}, // Will be updated after analysis
                .dependents = &.{},            // Will be updated after analysis
                .imports = &.{},               // Will be updated after analysis
                .exports = &.{},               // Will be updated after analysis  
                .import_hash = null,           // Will be updated after analysis
                .last_import_analysis = 0,     // Will be updated after analysis
            },
        };
    }
};

/// File tracker for maintaining incremental state
pub const FileTracker = struct {
    allocator: std.mem.Allocator,
    files: std.HashMap([]const u8, FileState, std.hash_map.StringContext, 80),
    dependency_graph: DependencyGraph,
    change_detector: ChangeDetector,
    ast_cache: ?*AstCache, // Optional AST cache for invalidation

    pub fn init(allocator: std.mem.Allocator) FileTracker {
        return FileTracker{
            .allocator = allocator,
            .files = std.HashMap([]const u8, FileState, std.hash_map.StringContext, 80).init(allocator),
            .dependency_graph = DependencyGraph.init(allocator, ".") catch unreachable,
            .change_detector = ChangeDetector.init(allocator),
            .ast_cache = null,
        };
    }

    pub fn initWithAstCache(allocator: std.mem.Allocator, ast_cache: *AstCache) FileTracker {
        return FileTracker{
            .allocator = allocator,
            .files = std.HashMap([]const u8, FileState, std.hash_map.StringContext, 80).init(allocator),
            .dependency_graph = DependencyGraph.init(allocator, ".") catch unreachable,
            .change_detector = ChangeDetector.init(allocator),
            .ast_cache = ast_cache,
        };
    }

    pub fn deinit(self: *FileTracker) void {
        var iter = self.files.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(self.allocator);
        }
        self.files.deinit();
        self.dependency_graph.deinit();
    }

    /// Track a new file or update existing file state
    pub fn trackFile(self: *FileTracker, file_path: []const u8) !void {
        const change = try self.change_detector.detectFileChange(file_path, self.files.get(file_path));
        
        switch (change.change_type) {
            .unchanged => {
                // Nothing to do
            },
            .new, .content => {
                if (change.new_state) |new_state| {
                    const key = try self.allocator.dupe(u8, file_path);
                    
                    // Invalidate AST cache entries for this file
                    if (self.ast_cache) |cache| {
                        try self.invalidateAstCacheForFile(cache, file_path);
                    }
                    
                    // Remove old state if it exists
                    if (self.files.fetchRemove(key)) |old_entry| {
                        self.allocator.free(old_entry.key);
                        var mutable_value = old_entry.value;
                        mutable_value.deinit(self.allocator);
                    }
                    
                    // Add new state
                    try self.files.put(key, new_state);
                }
            },
            .deleted => {
                if (self.files.fetchRemove(file_path)) |old_entry| {
                    self.allocator.free(old_entry.key);
                    var mutable_value = old_entry.value;
                    mutable_value.deinit(self.allocator);
                }
            },
            .dependencies => {
                // TODO: Handle dependency changes
            },
        }
    }

    /// Get current state of a tracked file
    pub fn getFileState(self: *FileTracker, file_path: []const u8) ?FileState {
        return self.files.get(file_path);
    }

    /// Get all tracked files
    pub fn getAllFiles(self: *FileTracker) []const []const u8 {
        var result = self.allocator.alloc([]const u8, self.files.count()) catch unreachable;
        var iter = self.files.keyIterator();
        var i: usize = 0;
        while (iter.next()) |key| {
            result[i] = key.*;
            i += 1;
        }
        return result;
    }

    /// Get files that have changed since last tracking
    pub fn getChangedFiles(self: *FileTracker, file_paths: []const []const u8, result: *std.ArrayList([]const u8)) !void {
        for (file_paths) |file_path| {
            const change = try self.change_detector.detectFileChange(file_path, self.files.get(file_path));
            if (change.change_type != .unchanged) {
                try result.append(file_path);
            }
        }
    }

    /// Invalidate AST cache entries for a file
    fn invalidateAstCacheForFile(self: *FileTracker, cache: *AstCache, file_path: []const u8) !void {
        // Get the file's current hash (if it exists)
        if (self.files.get(file_path)) |file_state| {
            // Invalidate all cache entries for this file by removing entries with matching file hash
            try cache.invalidateByFileHash(file_state.hash);
        }
    }

    /// Invalidate AST cache entries for multiple files
    pub fn invalidateAstCacheForFiles(self: *FileTracker, file_paths: []const []const u8) !void {
        if (self.ast_cache) |cache| {
            for (file_paths) |file_path| {
                try self.invalidateAstCacheForFile(cache, file_path);
            }
        }
    }

    /// Get or create AST cache key for a file with extraction flags
    pub fn getAstCacheKey(self: *FileTracker, file_path: []const u8, extraction_flags_hash: u64) ?AstCacheKey {
        if (self.files.get(file_path)) |file_state| {
            return AstCacheKey.init(
                file_state.hash,
                1, // parser version - could be made configurable
                extraction_flags_hash
            );
        }
        return null;
    }

    /// Cascade invalidation for dependent files
    pub fn cascadeInvalidation(self: *FileTracker, changed_file: []const u8) !void {
        if (self.ast_cache == null) return;
        
        var dependents = std.ArrayList([]const u8).init(self.allocator);
        defer dependents.deinit();
        
        // Get all files that depend on the changed file
        try self.dependency_graph.getDependents(changed_file, &dependents);
        
        // Invalidate cache for all dependent files
        try self.invalidateAstCacheForFiles(dependents.items);
    }
};

/// Incremental state for persistence
pub const IncrementalState = struct {
    files: std.HashMap([]const u8, FileState, std.hash_map.StringContext, 80),
    dependency_graph: DependencyGraph,
    cache_version: u32,
    last_run: i64,
    
    pub fn init(allocator: std.mem.Allocator) IncrementalState {
        return IncrementalState{
            .files = std.HashMap([]const u8, FileState, std.hash_map.StringContext, 80).init(allocator),
            .dependency_graph = DependencyGraph.init(allocator, ".") catch unreachable,
            .cache_version = 1,
            .last_run = @as(i64, @intCast(std.time.nanoTimestamp())),
        };
    }
    
    pub fn deinit(self: *IncrementalState, allocator: std.mem.Allocator) void {
        var iter = self.files.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(allocator);
        }
        self.files.deinit();
        self.dependency_graph.deinit();
    }
    
    /// Save state to file
    pub fn saveToFile(self: *IncrementalState, allocator: std.mem.Allocator, file_path: []const u8) !void {
        // Create .zz directory if it doesn't exist - using shared file helpers
        try io.ensureDir(".zz");
        
        // Serialize state to JSON
        var json_data = std.ArrayList(u8).init(allocator);
        defer json_data.deinit();
        
        try self.writeJson(&json_data);
        
        // Write to file atomically (write to temp file, then rename)
        const temp_path = try std.fmt.allocPrint(allocator, "{s}.tmp", .{file_path});
        defer allocator.free(temp_path);
        
        const file = try std.fs.cwd().createFile(temp_path, .{});
        defer file.close();
        
        try file.writeAll(json_data.items);
        
        // Atomic rename
        try std.fs.cwd().rename(temp_path, file_path);
    }
    
    /// Load state from file - using shared file helpers
    pub fn loadFromFile(allocator: std.mem.Allocator, file_path: []const u8) !IncrementalState {
        const content = io.readFileOptional(allocator, file_path) catch |err| {
            std.debug.print("Warning: loading incremental state for {s}: {s}\n", .{ file_path, errors.getMessage(err) });
            return err;
        };
        
        if (content) |file_content| {
            defer allocator.free(file_content);
            return try parseJson(allocator, file_content);
        } else {
            // File doesn't exist, return empty state
            return IncrementalState.init(allocator);
        }
    }
    
    /// Write state as JSON
    fn writeJson(self: *IncrementalState, writer: *std.ArrayList(u8)) !void {
        try writer.appendSlice("{\n");
        try writer.writer().print("  \"cache_version\": {},\n", .{self.cache_version});
        try writer.writer().print("  \"last_run\": {},\n", .{self.last_run});
        try writer.appendSlice("  \"files\": {\n");
        
        var file_iter = self.files.iterator();
        var first_file = true;
        while (file_iter.next()) |entry| {
            if (!first_file) try writer.appendSlice(",\n");
            first_file = false;
            
            try writer.writer().print("    \"{s}\": {{\n", .{entry.key_ptr.*});
            try writer.writer().print("      \"hash\": {},\n", .{entry.value_ptr.hash});
            try writer.writer().print("      \"mtime\": {},\n", .{entry.value_ptr.mtime});
            try writer.writer().print("      \"size\": {}\n", .{entry.value_ptr.size});
            try writer.appendSlice("    }");
        }
        
        try writer.appendSlice("\n  }\n");
        try writer.appendSlice("}\n");
    }
    
    /// Parse state from JSON
    fn parseJson(allocator: std.mem.Allocator, json_content: []const u8) !IncrementalState {
        // For now, use a simple JSON parser
        // In production, you'd want to use a proper JSON library
        
        var state = IncrementalState.init(allocator);
        
        // Parse basic fields (simplified parsing)
        if (std.mem.indexOf(u8, json_content, "\"cache_version\": ")) |start| {
            const num_start = start + "\"cache_version\": ".len;
            if (std.mem.indexOf(u8, json_content[num_start..], ",")) |end| {
                const version_str = json_content[num_start..num_start + end];
                state.cache_version = std.fmt.parseInt(u32, version_str, 10) catch 1;
            }
        }
        
        if (std.mem.indexOf(u8, json_content, "\"last_run\": ")) |start| {
            const num_start = start + "\"last_run\": ".len;
            if (std.mem.indexOf(u8, json_content[num_start..], ",")) |end| {
                const time_str = json_content[num_start..num_start + end];
                state.last_run = std.fmt.parseInt(i64, time_str, 10) catch @as(i64, @intCast(std.time.nanoTimestamp()));
            }
        }
        
        // TODO: Parse files section properly
        // This is a simplified implementation
        
        return state;
    }
};

/// Enhanced file tracker with persistence
pub const PersistentFileTracker = struct {
    base_tracker: FileTracker,
    state_file_path: []const u8,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, state_file_path: []const u8) PersistentFileTracker {
        return PersistentFileTracker{
            .base_tracker = FileTracker.init(allocator),
            .state_file_path = state_file_path,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *PersistentFileTracker) void {
        self.base_tracker.deinit();
    }
    
    /// Load state from disk
    pub fn loadState(self: *PersistentFileTracker) !void {
        var state = IncrementalState.loadFromFile(self.allocator, self.state_file_path) catch |err| switch (err) {
            error.FileNotFound => {
                // No existing state, start fresh
                return;
            },
            else => return err,
        };
        defer state.deinit(self.allocator);
        
        // Copy loaded state to tracker
        var iter = state.files.iterator();
        while (iter.next()) |entry| {
            const key = try self.allocator.dupe(u8, entry.key_ptr.*);
            try self.base_tracker.files.put(key, entry.value_ptr.*);
        }
    }
    
    /// Save state to disk
    pub fn saveState(self: *PersistentFileTracker) !void {
        var state = IncrementalState{
            .files = self.base_tracker.files,
            .dependency_graph = self.base_tracker.dependency_graph,
            .cache_version = 1,
            .last_run = @as(i64, @intCast(std.time.nanoTimestamp())),
        };
        
        try state.saveToFile(self.allocator, self.state_file_path);
    }
    
    /// Forward methods to base tracker
    pub fn trackFile(self: *PersistentFileTracker, file_path: []const u8) !void {
        return self.base_tracker.trackFile(file_path);
    }
    
    pub fn getFileState(self: *PersistentFileTracker, file_path: []const u8) ?FileState {
        return self.base_tracker.getFileState(file_path);
    }
    
    pub fn getChangedFiles(self: *PersistentFileTracker, file_paths: []const []const u8, result: *std.ArrayList([]const u8)) !void {
        return self.base_tracker.getChangedFiles(file_paths, result);
    }
};

// Tests
test "file hashing" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Create a temporary file
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const content = "test content for hashing";
    try tmp_dir.dir.writeFile(.{ .sub_path = "test.txt", .data = content });

    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, "test.txt");
    defer allocator.free(tmp_path);

    const hash1 = try hashFile(allocator, tmp_path);
    const hash2 = try hashFile(allocator, tmp_path);
    
    try testing.expect(hash1 == hash2);
    try testing.expect(hash1 != 0);
}

test "change detection" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var detector = ChangeDetector.init(allocator);

    // Test new file detection
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.writeFile(.{ .sub_path = "new.txt", .data = "content" });
    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, "new.txt");
    defer allocator.free(tmp_path);

    const change = try detector.detectFileChange(tmp_path, null);
    try testing.expect(change.change_type == .new);
    
    // Clean up allocated path in new_state
    if (change.new_state) |*state| {
        var mutable_state = state.*;
        mutable_state.deinit(allocator);
    }
}

test "file tracker" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var tracker = FileTracker.init(allocator);
    defer tracker.deinit();

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.writeFile(.{ .sub_path = "track.txt", .data = "content" });
    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, "track.txt");
    defer allocator.free(tmp_path);

    try tracker.trackFile(tmp_path);
    
    const state = tracker.getFileState(tmp_path);
    try testing.expect(state != null);
    try testing.expect(state.?.hash != 0);
}

test "dependency graph" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var graph = DependencyGraph.init(allocator, ".") catch unreachable;
    defer graph.deinit();

    try graph.addDependency("a.zig", "b.zig");
    try graph.addDependency("b.zig", "c.zig");
    
    var dependents = std.ArrayList([]const u8).init(allocator);
    defer dependents.deinit();
    
    try graph.getDependents("c.zig", &dependents);
    try testing.expect(dependents.items.len == 2); // a.zig and b.zig depend on c.zig
}