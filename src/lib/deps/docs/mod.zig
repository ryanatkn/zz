const std = @import("std");
const config = @import("../config.zig");
const io = @import("../../core/io.zig");
const path = @import("../../core/path.zig");
const collections = @import("../../core/collections.zig");
const FilesystemInterface = @import("../../filesystem/interface.zig").FilesystemInterface;
const RealFilesystem = @import("../../filesystem/real.zig").RealFilesystem;

// Re-export types and submodules
pub const DependencyCategory = @import("types.zig").DependencyCategory;
pub const DependencyDoc = @import("types.zig").DependencyDoc;
pub const BuildParser = @import("build_parser.zig").BuildParser;
pub const BuildConfig = @import("build_parser.zig").BuildConfig;
// Markdown generation removed - focus on manifest.json only
pub const ManifestGenerator = @import("manifest.zig").ManifestGenerator;

// Local imports for use within this module
const types = @import("types.zig");
const build_parser = @import("build_parser.zig");
// Markdown import removed - JSON manifest only
const manifest = @import("manifest.zig");

/// Main documentation generator
pub const DocumentationGenerator = struct {
    allocator: std.mem.Allocator,
    filesystem: FilesystemInterface,
    deps_dir: []const u8,
    build_parser: build_parser.BuildParser,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator, deps_dir: []const u8) Self {
        return Self.initWithFilesystem(allocator, RealFilesystem.init(), deps_dir);
    }
    
    pub fn initWithFilesystem(allocator: std.mem.Allocator, filesystem: FilesystemInterface, deps_dir: []const u8) Self {
        return Self{
            .allocator = allocator,
            .filesystem = filesystem,
            .deps_dir = deps_dir,
            .build_parser = build_parser.BuildParser.init(allocator),
        };
    }
    
    /// Generate manifest.json from current dependency state
    pub fn generateDocumentation(self: *Self, dependencies: []const config.Dependency) !void {
        // Collect dependency documentation
        var dep_docs = collections.List(types.DependencyDoc).init(self.allocator);
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
        
        // Generate manifest.json only
        var manifest_gen = manifest.ManifestGenerator.init(self.allocator, self.deps_dir);
        try manifest_gen.generateManifest(dep_docs.items);
    }
    
    /// Create a DependencyDoc from a config.Dependency
    fn createDependencyDoc(self: *Self, dep: config.Dependency) !types.DependencyDoc {
        // Load version info from .version file
        const dep_dir = try path.joinPath(self.allocator, self.deps_dir, dep.name);
        defer self.allocator.free(dep_dir);
        
        const version_file = try path.joinPath(self.allocator, dep_dir, ".version");
        defer self.allocator.free(version_file);
        
        // Read .version file content
        const content = io.readFileOptional(self.allocator, version_file) catch |err| switch (err) {
            error.FileNotFound => {
                // Create a default version info if file doesn't exist
                return types.DependencyDoc{
                    .name = try self.allocator.dupe(u8, dep.name),
                    .category = if (dep.category) |cat| self.parseCategory(cat) else self.categorizeDepencency(dep.name),
                    .version_info = config.VersionInfo{
                        .repository = try self.allocator.dupe(u8, dep.url),
                        .version = try self.allocator.dupe(u8, dep.version),
                        .commit = try self.allocator.dupe(u8, "unknown"),
                        .updated = 0,
                        .updated_by = try self.allocator.dupe(u8, "unknown"),
                    },
                    .build_config = try self.build_parser.extractBuildInfo(dep.name),
                    .language = if (dep.language) |lang| try self.allocator.dupe(u8, lang) else try self.extractLanguage(dep.name),
                    .purpose = if (dep.purpose) |purpose| try self.allocator.dupe(u8, purpose) else try self.generatePurpose(dep.name),
                };
            },
            else => return err,
        };
        
        if (content) |c| {
            defer self.allocator.free(c);
            const version_info = try config.VersionInfo.parseFromContent(self.allocator, c);
            
            return types.DependencyDoc{
                .name = try self.allocator.dupe(u8, dep.name),
                .category = if (dep.category) |cat| self.parseCategory(cat) else self.categorizeDepencency(dep.name),
                .version_info = version_info,
                .build_config = try self.build_parser.extractBuildInfo(dep.name),
                .language = if (dep.language) |lang| try self.allocator.dupe(u8, lang) else try self.extractLanguage(dep.name),
                .purpose = if (dep.purpose) |purpose| try self.allocator.dupe(u8, purpose) else try self.generatePurpose(dep.name),
            };
        } else {
            // No version file found, create default
            return types.DependencyDoc{
                .name = try self.allocator.dupe(u8, dep.name),
                .category = if (dep.category) |cat| self.parseCategory(cat) else self.categorizeDepencency(dep.name),
                .version_info = config.VersionInfo{
                    .repository = try self.allocator.dupe(u8, dep.url),
                    .version = try self.allocator.dupe(u8, dep.version),
                    .commit = try self.allocator.dupe(u8, "unknown"),
                    .updated = 0,
                    .updated_by = try self.allocator.dupe(u8, "unknown"),
                },
                .build_config = try self.build_parser.extractBuildInfo(dep.name),
                .language = if (dep.language) |lang| try self.allocator.dupe(u8, lang) else try self.extractLanguage(dep.name),
                .purpose = if (dep.purpose) |purpose| try self.allocator.dupe(u8, purpose) else try self.generatePurpose(dep.name),
            };
        }
    }
    
    /// Parse category string to enum
    fn parseCategory(self: *Self, category_str: []const u8) types.DependencyCategory {
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
    fn categorizeDepencency(self: *Self, name: []const u8) types.DependencyCategory {
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
};