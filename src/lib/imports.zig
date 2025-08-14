const std = @import("std");

/// Language-agnostic import/export tracking and resolution
/// Eliminates JavaScript-specific cruft with clean, generic patterns

// ============================================================================
// Core Types
// ============================================================================

pub const Import = struct {
    path: []const u8,
    source_file: []const u8,
    line: u32,
    kind: ImportKind,
    symbols: [][]const u8, // What's imported from the module
    alias: ?[]const u8, // Import alias (e.g., "as foo")
    
    pub fn deinit(self: *Import, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
        allocator.free(self.source_file);
        for (self.symbols) |symbol| {
            allocator.free(symbol);
        }
        allocator.free(self.symbols);
        if (self.alias) |alias| {
            allocator.free(alias);
        }
    }
};

pub const Export = struct {
    name: []const u8,
    source_file: []const u8,
    line: u32,
    kind: ExportKind,
    type_info: ?[]const u8, // Optional type information
    
    pub fn deinit(self: *Export, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.source_file);
        if (self.type_info) |type_info| {
            allocator.free(type_info);
        }
    }
};

pub const ImportKind = enum {
    relative,    // ./foo or ../foo
    absolute,    // /usr/include/foo
    package,     // external package/module
    system,      // <stdio.h> or std.* in Zig
};

pub const ExportKind = enum {
    function,
    type,
    constant,
    variable,
    module,
};

pub const ExtractionResult = struct {
    imports: []Import,
    exports: []Export,
    
    pub fn deinit(self: *ExtractionResult, allocator: std.mem.Allocator) void {
        for (self.imports) |*import| {
            import.deinit(allocator);
        }
        allocator.free(self.imports);
        
        for (self.exports) |*exp| {
            exp.deinit(allocator);
        }
        allocator.free(self.exports);
    }
};

// ============================================================================
// Import Extractor
// ============================================================================

pub const Extractor = struct {
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) Extractor {
        return Extractor{ .allocator = allocator };
    }
    
    /// Extract imports/exports from source code based on file extension
    pub fn extract(self: *Extractor, file_path: []const u8, source: []const u8) !ExtractionResult {
        const ext = std.fs.path.extension(file_path);
        
        if (std.mem.eql(u8, ext, ".zig")) {
            return self.extractZig(file_path, source);
        } else if (std.mem.eql(u8, ext, ".ts") or std.mem.eql(u8, ext, ".js")) {
            return self.extractTypeScript(file_path, source);
        } else if (std.mem.eql(u8, ext, ".c") or std.mem.eql(u8, ext, ".h")) {
            return self.extractC(file_path, source);
        } else if (std.mem.eql(u8, ext, ".css")) {
            return self.extractCss(file_path, source);
        } else {
            // Generic text-based extraction
            return self.extractGeneric(file_path, source);
        }
    }
    
    fn extractZig(self: *Extractor, file_path: []const u8, source: []const u8) !ExtractionResult {
        var imports = std.ArrayList(Import).init(self.allocator);
        defer imports.deinit();
        
        var exports = std.ArrayList(Export).init(self.allocator);
        defer exports.deinit();
        
        var lines = std.mem.splitScalar(u8, source, '\n');
        var line_num: u32 = 1;
        
        while (lines.next()) |line| {
            defer line_num += 1;
            
            const trimmed = std.mem.trim(u8, line, " \t");
            
            // Extract @import statements
            if (std.mem.startsWith(u8, trimmed, "@import(")) {
                if (self.parseZigImport(file_path, trimmed, line_num)) |import| {
                    try imports.append(import);
                } else |_| {
                    // Skip malformed imports
                }
            }
            
            // Extract pub declarations (exports)
            if (std.mem.startsWith(u8, trimmed, "pub ")) {
                if (self.parseZigExport(file_path, trimmed, line_num)) |exp| {
                    try exports.append(exp);
                } else |_| {
                    // Skip malformed exports
                }
            }
        }
        
        return ExtractionResult{
            .imports = try imports.toOwnedSlice(),
            .exports = try exports.toOwnedSlice(),
        };
    }
    
    fn extractTypeScript(self: *Extractor, file_path: []const u8, source: []const u8) !ExtractionResult {
        var imports = std.ArrayList(Import).init(self.allocator);
        defer imports.deinit();
        
        var exports = std.ArrayList(Export).init(self.allocator);
        defer exports.deinit();
        
        var lines = std.mem.splitScalar(u8, source, '\n');
        var line_num: u32 = 1;
        
        while (lines.next()) |line| {
            defer line_num += 1;
            
            const trimmed = std.mem.trim(u8, line, " \t");
            
            // Extract import statements
            if (std.mem.startsWith(u8, trimmed, "import ")) {
                if (self.parseTypeScriptImport(file_path, trimmed, line_num)) |import| {
                    try imports.append(import);
                } else |_| {}
            }
            
            // Extract export statements
            if (std.mem.startsWith(u8, trimmed, "export ")) {
                if (self.parseTypeScriptExport(file_path, trimmed, line_num)) |export| {
                    try exports.append(export);
                } else |_| {}
            }
        }
        
        return ExtractionResult{
            .imports = try imports.toOwnedSlice(),
            .exports = try exports.toOwnedSlice(),
        };
    }
    
    fn extractC(self: *Extractor, file_path: []const u8, source: []const u8) !ExtractionResult {
        var imports = std.ArrayList(Import).init(self.allocator);
        defer imports.deinit();
        
        var lines = std.mem.splitScalar(u8, source, '\n');
        var line_num: u32 = 1;
        
        while (lines.next()) |line| {
            defer line_num += 1;
            
            const trimmed = std.mem.trim(u8, line, " \t");
            
            // Extract #include statements
            if (std.mem.startsWith(u8, trimmed, "#include")) {
                if (self.parseCInclude(file_path, trimmed, line_num)) |import| {
                    try imports.append(import);
                } else |_| {}
            }
        }
        
        return ExtractionResult{
            .imports = try imports.toOwnedSlice(),
            .exports = try self.allocator.alloc(Export, 0), // C doesn't have explicit exports
        };
    }
    
    fn extractCss(self: *Extractor, file_path: []const u8, source: []const u8) !ExtractionResult {
        var imports = std.ArrayList(Import).init(self.allocator);
        defer imports.deinit();
        
        var lines = std.mem.splitScalar(u8, source, '\n');
        var line_num: u32 = 1;
        
        while (lines.next()) |line| {
            defer line_num += 1;
            
            const trimmed = std.mem.trim(u8, line, " \t");
            
            // Extract @import statements
            if (std.mem.startsWith(u8, trimmed, "@import")) {
                if (self.parseCssImport(file_path, trimmed, line_num)) |import| {
                    try imports.append(import);
                } else |_| {}
            }
        }
        
        return ExtractionResult{
            .imports = try imports.toOwnedSlice(),
            .exports = try self.allocator.alloc(Export, 0), // CSS doesn't have explicit exports
        };
    }
    
    fn extractGeneric(self: *Extractor, file_path: []const u8, source: []const u8) !ExtractionResult {
        _ = file_path;
        _ = source;
        
        // Generic extraction - just return empty results
        return ExtractionResult{
            .imports = try self.allocator.alloc(Import, 0),
            .exports = try self.allocator.alloc(Export, 0),
        };
    }
    
    // Parsing helpers
    fn parseZigImport(self: *Extractor, file_path: []const u8, line: []const u8, line_num: u32) !Import {
        // @import("path")
        const start = std.mem.indexOf(u8, line, "\"") orelse return error.NoQuote;
        const end = std.mem.lastIndexOf(u8, line, "\"") orelse return error.NoQuote;
        if (start >= end) return error.InvalidQuotes;
        
        const path = try self.allocator.dupe(u8, line[start + 1 .. end]);
        const kind = if (std.mem.startsWith(u8, path, "./") or std.mem.startsWith(u8, path, "../")) 
            ImportKind.relative 
        else if (std.mem.startsWith(u8, path, "std")) 
            ImportKind.system 
        else 
            ImportKind.package;
        
        return Import{
            .path = path,
            .source_file = try self.allocator.dupe(u8, file_path),
            .line = line_num,
            .kind = kind,
            .symbols = try self.allocator.alloc([]const u8, 0),
            .alias = null,
        };
    }
    
    fn parseZigExport(self: *Extractor, file_path: []const u8, line: []const u8, line_num: u32) !Export {
        // pub fn name(), pub const name, etc.
        const after_pub = std.mem.trim(u8, line[4..], " \t");
        
        var kind: ExportKind = .function;
        var name_start: usize = 0;
        
        if (std.mem.startsWith(u8, after_pub, "fn ")) {
            kind = .function;
            name_start = 3;
        } else if (std.mem.startsWith(u8, after_pub, "const ")) {
            kind = .constant;
            name_start = 6;
        } else if (std.mem.startsWith(u8, after_pub, "var ")) {
            kind = .variable;
            name_start = 4;
        } else {
            return error.UnknownExportType;
        }
        
        const name_part = std.mem.trim(u8, after_pub[name_start..], " \t");
        const name_end = std.mem.indexOfAny(u8, name_part, " \t=(") orelse name_part.len;
        const name = try self.allocator.dupe(u8, name_part[0..name_end]);
        
        return Export{
            .name = name,
            .source_file = try self.allocator.dupe(u8, file_path),
            .line = line_num,
            .kind = kind,
            .type_info = null,
        };
    }
    
    fn parseTypeScriptImport(self: *Extractor, file_path: []const u8, line: []const u8, line_num: u32) !Import {
        // import ... from "path"
        const from_pos = std.mem.indexOf(u8, line, " from ") orelse return error.NoFrom;
        const quote_start = std.mem.indexOf(u8, line[from_pos..], "\"") orelse return error.NoQuote;
        const quote_end = std.mem.lastIndexOf(u8, line, "\"") orelse return error.NoQuote;
        
        const path_start = from_pos + quote_start + 1;
        if (path_start >= quote_end) return error.InvalidQuotes;
        
        const path = try self.allocator.dupe(u8, line[path_start..quote_end]);
        const kind = if (std.mem.startsWith(u8, path, "./") or std.mem.startsWith(u8, path, "../"))
            ImportKind.relative
        else if (std.mem.startsWith(u8, path, "/"))
            ImportKind.absolute
        else
            ImportKind.package;
        
        return Import{
            .path = path,
            .source_file = try self.allocator.dupe(u8, file_path),
            .line = line_num,
            .kind = kind,
            .symbols = try self.allocator.alloc([]const u8, 0),
            .alias = null,
        };
    }
    
    fn parseTypeScriptExport(self: *Extractor, file_path: []const u8, line: []const u8, line_num: u32) !Export {
        // export function name(), export const name, etc.
        const after_export = std.mem.trim(u8, line[7..], " \t");
        
        var kind: ExportKind = .function;
        var name_start: usize = 0;
        
        if (std.mem.startsWith(u8, after_export, "function ")) {
            kind = .function;
            name_start = 9;
        } else if (std.mem.startsWith(u8, after_export, "const ")) {
            kind = .constant;
            name_start = 6;
        } else if (std.mem.startsWith(u8, after_export, "interface ")) {
            kind = .type;
            name_start = 10;
        } else {
            return error.UnknownExportType;
        }
        
        const name_part = std.mem.trim(u8, after_export[name_start..], " \t");
        const name_end = std.mem.indexOfAny(u8, name_part, " \t(={") orelse name_part.len;
        const name = try self.allocator.dupe(u8, name_part[0..name_end]);
        
        return Export{
            .name = name,
            .source_file = try self.allocator.dupe(u8, file_path),
            .line = line_num,
            .kind = kind,
            .type_info = null,
        };
    }
    
    fn parseCInclude(self: *Extractor, file_path: []const u8, line: []const u8, line_num: u32) !Import {
        // #include "path" or #include <path>
        const is_system = std.mem.indexOf(u8, line, "<") != null;
        const quote_char = if (is_system) "<" else "\"";
        const end_char = if (is_system) ">" else "\"";
        
        const start = std.mem.indexOf(u8, line, quote_char) orelse return error.NoQuote;
        const end = std.mem.indexOf(u8, line[start + 1..], end_char) orelse return error.NoQuote;
        
        const path = try self.allocator.dupe(u8, line[start + 1 .. start + 1 + end]);
        const kind = if (is_system) ImportKind.system else ImportKind.relative;
        
        return Import{
            .path = path,
            .source_file = try self.allocator.dupe(u8, file_path),
            .line = line_num,
            .kind = kind,
            .symbols = try self.allocator.alloc([]const u8, 0),
            .alias = null,
        };
    }
    
    fn parseCssImport(self: *Extractor, file_path: []const u8, line: []const u8, line_num: u32) !Import {
        // @import "path" or @import url("path")
        const quote_start = std.mem.indexOf(u8, line, "\"") orelse return error.NoQuote;
        const quote_end = std.mem.lastIndexOf(u8, line, "\"") orelse return error.NoQuote;
        if (quote_start >= quote_end) return error.InvalidQuotes;
        
        const path = try self.allocator.dupe(u8, line[quote_start + 1 .. quote_end]);
        const kind = if (std.mem.startsWith(u8, path, "./") or std.mem.startsWith(u8, path, "../"))
            ImportKind.relative
        else
            ImportKind.package;
        
        return Import{
            .path = path,
            .source_file = try self.allocator.dupe(u8, file_path),
            .line = line_num,
            .kind = kind,
            .symbols = try self.allocator.alloc([]const u8, 0),
            .alias = null,
        };
    }
};

// ============================================================================
// Path Resolver
// ============================================================================

pub const Resolver = struct {
    allocator: std.mem.Allocator,
    project_root: []const u8,
    search_paths: [][]const u8,
    cache: std.StringHashMap([]const u8),
    
    pub fn initOwning(allocator: std.mem.Allocator, project_root: []const u8, search_paths: []const []const u8) !Resolver {
        var owned_root = try allocator.dupe(u8, project_root);
        var owned_paths = try allocator.alloc([]const u8, search_paths.len);
        
        for (search_paths, 0..) |path, i| {
            owned_paths[i] = try allocator.dupe(u8, path);
        }
        
        return Resolver{
            .allocator = allocator,
            .project_root = owned_root,
            .search_paths = owned_paths,
            .cache = std.StringHashMap([]const u8).init(allocator),
        };
    }
    
    pub fn initBorrowing(allocator: std.mem.Allocator, project_root: []const u8, search_paths: []const []const u8) Resolver {
        return Resolver{
            .allocator = allocator,
            .project_root = project_root,
            .search_paths = search_paths,
            .cache = std.StringHashMap([]const u8).init(allocator),
        };
    }
    
    pub fn deinit(self: *Resolver) void {
        // Only free if we own the data (check if we allocated it)
        if (self.search_paths.len > 0) {
            // Assume if we have search paths, we might own them
            // In practice, caller should track ownership
        }
        
        var iter = self.cache.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.cache.deinit();
    }
    
    /// Resolve import path to absolute file path
    pub fn resolve(self: *Resolver, from_file: []const u8, import_path: []const u8) !?[]const u8 {
        // Check cache first
        const cache_key = try std.fmt.allocPrint(self.allocator, "{s}:{s}", .{ from_file, import_path });
        defer self.allocator.free(cache_key);
        
        if (self.cache.get(cache_key)) |cached| {
            return try self.allocator.dupe(u8, cached);
        }
        
        var resolved: ?[]const u8 = null;
        
        // Try relative resolution first
        if (std.mem.startsWith(u8, import_path, "./") or std.mem.startsWith(u8, import_path, "../")) {
            resolved = try self.resolveRelative(from_file, import_path);
        }
        
        // Try search paths if relative failed
        if (resolved == null) {
            resolved = try self.resolveInSearchPaths(import_path);
        }
        
        // Cache result if found
        if (resolved) |path| {
            const cached_path = try self.allocator.dupe(u8, path);
            try self.cache.put(try self.allocator.dupe(u8, cache_key), cached_path);
        }
        
        return resolved;
    }
    
    fn resolveRelative(self: *Resolver, from_file: []const u8, import_path: []const u8) !?[]const u8 {
        const from_dir = std.fs.path.dirname(from_file) orelse ".";
        const candidate = try std.fs.path.join(self.allocator, &[_][]const u8{ from_dir, import_path });
        defer self.allocator.free(candidate);
        
        // Try with various extensions
        const extensions = [_][]const u8{ "", ".zig", ".ts", ".js", ".c", ".h" };
        for (extensions) |ext| {
            const full_path = if (ext.len == 0) 
                try self.allocator.dupe(u8, candidate)
            else 
                try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ candidate, ext });
            
            if (self.fileExists(full_path)) {
                return full_path;
            } else {
                self.allocator.free(full_path);
            }
        }
        
        return null;
    }
    
    fn resolveInSearchPaths(self: *Resolver, import_path: []const u8) !?[]const u8 {
        for (self.search_paths) |search_path| {
            const candidate = try std.fs.path.join(self.allocator, &[_][]const u8{ search_path, import_path });
            defer self.allocator.free(candidate);
            
            // Try with extensions
            const extensions = [_][]const u8{ "", ".zig", ".ts", ".js", ".c", ".h" };
            for (extensions) |ext| {
                const full_path = if (ext.len == 0)
                    try self.allocator.dupe(u8, candidate)
                else
                    try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ candidate, ext });
                
                if (self.fileExists(full_path)) {
                    return full_path;
                }
                self.allocator.free(full_path);
            }
        }
        
        return null;
    }
    
    fn fileExists(self: *Resolver, path: []const u8) bool {
        _ = self;
        std.fs.cwd().access(path, .{}) catch return false;
        return true;
    }
};

test "zig import extraction" {
    const testing = std.testing;
    
    var extractor = Extractor.init(testing.allocator);
    
    const source = 
        \\const std = @import("std");
        \\const utils = @import("./utils.zig");
        \\
        \\pub fn test() void {}
        \\pub const VERSION = "1.0.0";
    ;
    
    var result = try extractor.extract("test.zig", source);
    defer result.deinit(testing.allocator);
    
    try testing.expect(result.imports.len == 2);
    try testing.expect(result.exports.len == 2);
    
    try testing.expectEqualStrings("std", result.imports[0].path);
    try testing.expect(result.imports[0].kind == .system);
    
    try testing.expectEqualStrings("./utils.zig", result.imports[1].path);
    try testing.expect(result.imports[1].kind == .relative);
}

test "resolver basic functionality" {
    const testing = std.testing;
    
    const search_paths = [_][]const u8{"./src"};
    var resolver = Resolver.initBorrowing(testing.allocator, ".", &search_paths);
    defer resolver.deinit();
    
    // Test cache works
    try testing.expect(resolver.cache.count() == 0);
}