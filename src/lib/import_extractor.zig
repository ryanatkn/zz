const std = @import("std");
const TreeSitterParser = @import("tree_sitter_parser.zig").TreeSitterParser;
const Language = @import("parser.zig").Language;
const AstCache = @import("cache.zig").AstCache;
const AstCacheKey = @import("cache.zig").AstCacheKey;
const collection_helpers = @import("collection_helpers.zig");
const file_helpers = @import("file_helpers.zig");
const error_helpers = @import("error_helpers.zig");
const path = @import("path.zig");

/// Type of import statement
pub const ImportType = enum {
    // ES6/TypeScript imports
    default_import,        // import foo from 'module'
    named_import,          // import { foo, bar } from 'module'
    namespace_import,      // import * as foo from 'module'
    side_effect_import,    // import 'module'
    dynamic_import,        // import('module')
    
    // Other language imports
    zig_import,           // @import("module")
    c_include,            // #include "file.h"
    c_include_system,     // #include <file.h>
    
    // Re-exports
    re_export,            // export { foo } from 'module'
    re_export_all,        // export * from 'module'
};

/// Individual symbol being imported
pub const ImportedSymbol = struct {
    name: []const u8,           // Original name in source module
    alias: ?[]const u8,         // Local alias if renamed
    is_type: bool,              // TypeScript type import
    line_number: u32,           // Line where symbol appears
    
    pub fn deinit(self: *ImportedSymbol, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        if (self.alias) |alias| {
            allocator.free(alias);
        }
    }
    
    /// Get the local name used in the importing file
    pub fn getLocalName(self: ImportedSymbol) []const u8 {
        return self.alias orelse self.name;
    }
};

/// Complete information about an import statement
pub const ImportInfo = struct {
    source_file: []const u8,       // File doing the importing
    import_path: []const u8,       // Raw import path from source
    resolved_path: ?[]const u8,    // Resolved absolute file path
    import_type: ImportType,       // Type of import
    symbols: []ImportedSymbol,     // Specific symbols imported
    default_import: ?[]const u8,   // Default import name
    namespace_import: ?[]const u8, // Namespace import name
    line_number: u32,              // Line number of import statement
    is_dynamic: bool,              // Dynamic import (runtime resolved)
    is_type_only: bool,            // TypeScript type-only import
    
    pub fn deinit(self: *ImportInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.source_file);
        allocator.free(self.import_path);
        if (self.resolved_path) |resolved| {
            allocator.free(resolved);
        }
        for (self.symbols) |*symbol| {
            symbol.deinit(allocator);
        }
        allocator.free(self.symbols);
        if (self.default_import) |default| {
            allocator.free(default);
        }
        if (self.namespace_import) |namespace| {
            allocator.free(namespace);
        }
    }
    
    /// Check if this import includes a specific symbol
    pub fn hasSymbol(self: ImportInfo, symbol_name: []const u8) bool {
        // Check default import
        if (self.default_import) |default| {
            if (std.mem.eql(u8, default, symbol_name)) return true;
        }
        
        // Check namespace import
        if (self.namespace_import) |namespace| {
            if (std.mem.eql(u8, namespace, symbol_name)) return true;
        }
        
        // Check named imports
        for (self.symbols) |symbol| {
            if (std.mem.eql(u8, symbol.getLocalName(), symbol_name)) return true;
        }
        
        return false;
    }
    
    /// Get all locally available symbol names from this import
    pub fn getLocalSymbols(self: ImportInfo, allocator: std.mem.Allocator) ![][]const u8 {
        var symbols = collection_helpers.CollectionHelpers.ManagedArrayList([]const u8).init(allocator);
        defer symbols.deinit();
        
        if (self.default_import) |default| {
            try symbols.append(try allocator.dupe(u8, default));
        }
        
        if (self.namespace_import) |namespace| {
            try symbols.append(try allocator.dupe(u8, namespace));
        }
        
        for (self.symbols) |symbol| {
            try symbols.append(try allocator.dupe(u8, symbol.getLocalName()));
        }
        
        return symbols.toOwnedSlice();
    }
};

/// Information about an export statement
pub const ExportInfo = struct {
    source_file: []const u8,       // File doing the exporting
    export_path: ?[]const u8,      // Re-export source path
    symbols: []ImportedSymbol,     // Symbols being exported
    is_default: bool,              // Default export
    is_namespace: bool,            // export * 
    line_number: u32,              // Line number of export
    
    pub fn deinit(self: *ExportInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.source_file);
        if (self.export_path) |export_path| {
            allocator.free(export_path);
        }
        for (self.symbols) |*symbol| {
            symbol.deinit(allocator);
        }
        allocator.free(self.symbols);
    }
};

/// Extraction result containing both imports and exports
pub const ExtractionResult = struct {
    imports: []ImportInfo,
    exports: []ExportInfo,
    
    pub fn deinit(self: *ExtractionResult, allocator: std.mem.Allocator) void {
        for (self.imports) |*import| {
            import.deinit(allocator);
        }
        allocator.free(self.imports);
        
        for (self.exports) |*export_item| {
            export_item.deinit(allocator);
        }
        allocator.free(self.exports);
    }
};

/// Advanced import extractor using AST analysis
pub const ImportExtractor = struct {
    allocator: std.mem.Allocator,
    cache: ?*AstCache,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .cache = null,
        };
    }
    
    pub fn initWithCache(allocator: std.mem.Allocator, cache: *AstCache) Self {
        return Self{
            .allocator = allocator,
            .cache = cache,
        };
    }
    
    /// Extract imports and exports from a source file using AST analysis
    pub fn extract(self: *Self, file_path: []const u8, source: []const u8) !ExtractionResult {
        // Check cache first if available
        if (self.cache) |cache| {
            const cache_key = self.createCacheKey(file_path, source);
            if (cache.get(cache_key)) |cached_content| {
                return try self.deserializeResult(cached_content);
            }
        }
        
        // Detect language from file extension
        const language = Language.fromExtension(std.fs.path.extension(file_path));
        
        // Extract using appropriate method
        const result = switch (language) {
            .typescript, .javascript => try self.extractTypeScript(file_path, source),
            .zig => try self.extractZig(file_path, source),
            .c, .cpp => try self.extractC(file_path, source),
            .css => try self.extractCSS(file_path, source),
            .svelte => try self.extractSvelte(file_path, source),
            else => ExtractionResult{ .imports = &.{}, .exports = &.{} },
        };
        
        // Cache the result if cache is available
        if (self.cache) |cache| {
            const cache_key = self.createCacheKey(file_path, source);
            const serialized = try self.serializeResult(result);
            defer self.allocator.free(serialized);
            cache.put(cache_key, serialized) catch {}; // Ignore cache errors
        }
        
        return result;
    }
    
    /// Extract imports from TypeScript/JavaScript source
    fn extractTypeScript(self: *Self, file_path: []const u8, source: []const u8) !ExtractionResult {
        var parser = TreeSitterParser.init(self.allocator, .typescript) catch {
            // Fallback to text-based extraction if tree-sitter fails
            return self.extractTypeScriptFallback(file_path, source);
        };
        defer parser.deinit();
        
        const tree = parser.parse(source) catch {
            return self.extractTypeScriptFallback(file_path, source);
        };
        defer tree.destroy();
        
        var imports = collection_helpers.CollectionHelpers.ManagedArrayList(ImportInfo).init(self.allocator);
        defer imports.deinit();
        
        var exports = collection_helpers.CollectionHelpers.ManagedArrayList(ExportInfo).init(self.allocator);
        defer exports.deinit();
        
        // Walk AST to find import/export nodes
        try self.walkTypeScriptAST(tree.rootNode(), source, file_path, &imports, &exports);
        
        return ExtractionResult{
            .imports = try imports.toOwnedSlice(),
            .exports = try exports.toOwnedSlice(),
        };
    }
    
    /// Extract imports from Zig source
    fn extractZig(self: *Self, file_path: []const u8, source: []const u8) !ExtractionResult {
        var parser = TreeSitterParser.init(self.allocator, .zig) catch {
            return self.extractZigFallback(file_path, source);
        };
        defer parser.deinit();
        
        const tree = parser.parse(source) catch {
            return self.extractZigFallback(file_path, source);
        };
        defer tree.destroy();
        
        var imports = collection_helpers.CollectionHelpers.ManagedArrayList(ImportInfo).init(self.allocator);
        defer imports.deinit();
        
        // Zig doesn't have exports in the same sense, so exports will be empty
        const exports = try self.allocator.alloc(ExportInfo, 0);
        
        try self.walkZigAST(tree.rootNode(), source, file_path, &imports);
        
        return ExtractionResult{
            .imports = try imports.toOwnedSlice(),
            .exports = exports,
        };
    }
    
    /// Extract imports from C/C++ source
    fn extractC(self: *Self, file_path: []const u8, source: []const u8) !ExtractionResult {
        return self.extractCFallback(file_path, source);
    }
    
    /// Extract imports from CSS source
    fn extractCSS(self: *Self, file_path: []const u8, source: []const u8) !ExtractionResult {
        var parser = TreeSitterParser.init(self.allocator, .css) catch {
            return ExtractionResult{ .imports = &.{}, .exports = &.{} };
        };
        defer parser.deinit();
        
        const tree = parser.parse(source) catch {
            return ExtractionResult{ .imports = &.{}, .exports = &.{} };
        };
        defer tree.destroy();
        
        var imports = collection_helpers.CollectionHelpers.ManagedArrayList(ImportInfo).init(self.allocator);
        defer imports.deinit();
        
        try self.walkCSSAST(tree.rootNode(), source, file_path, &imports);
        
        return ExtractionResult{
            .imports = try imports.toOwnedSlice(),
            .exports = &.{},
        };
    }
    
    /// Extract imports from Svelte source (multi-section aware)
    fn extractSvelte(self: *Self, file_path: []const u8, source: []const u8) !ExtractionResult {
        // Svelte files have multiple sections - extract from each
        var all_imports = collection_helpers.CollectionHelpers.ManagedArrayList(ImportInfo).init(self.allocator);
        defer all_imports.deinit();
        
        var all_exports = collection_helpers.CollectionHelpers.ManagedArrayList(ExportInfo).init(self.allocator);
        defer all_exports.deinit();
        
        // Extract from script sections (TypeScript/JavaScript)
        if (self.extractSvelteScriptSection(source)) |script_content| {
            defer self.allocator.free(script_content);
            const script_result = try self.extractTypeScript(file_path, script_content);
            defer script_result.deinit(self.allocator);
            
            try all_imports.appendSlice(script_result.imports);
            try all_exports.appendSlice(script_result.exports);
        }
        
        // Extract from style sections (CSS)
        if (self.extractSvelteStyleSection(source)) |style_content| {
            defer self.allocator.free(style_content);
            const style_result = try self.extractCSS(file_path, style_content);
            defer style_result.deinit(self.allocator);
            
            try all_imports.appendSlice(style_result.imports);
        }
        
        return ExtractionResult{
            .imports = try all_imports.toOwnedSlice(),
            .exports = try all_exports.toOwnedSlice(),
        };
    }
    
    // AST walking methods for each language
    const ts = @import("tree-sitter");
    
    fn walkTypeScriptAST(self: *Self, node: ts.Node, source: []const u8, file_path: []const u8, 
                        imports: *collection_helpers.CollectionHelpers.ManagedArrayList(ImportInfo),
                        exports: *collection_helpers.CollectionHelpers.ManagedArrayList(ExportInfo)) !void {
        const node_type = node.kind();
        
        // Handle import statements
        if (std.mem.eql(u8, node_type, "import_statement")) {
            const import_info = try self.parseTypeScriptImport(node, source, file_path);
            try imports.append(import_info);
        }
        // Handle export statements
        else if (std.mem.eql(u8, node_type, "export_statement")) {
            if (self.parseTypeScriptExport(node, source, file_path)) |export_info| {
                try exports.append(export_info);
            } else |_| {
                // Ignore parse errors
            }
        }
        
        // Recurse into children
        const child_count = node.childCount();
        var i: u32 = 0;
        while (i < child_count) : (i += 1) {
            if (node.child(i)) |child| {
                try self.walkTypeScriptAST(child, source, file_path, imports, exports);
            }
        }
    }
    
    fn walkZigAST(self: *Self, node: ts.Node, source: []const u8, file_path: []const u8,
                  imports: *collection_helpers.CollectionHelpers.ManagedArrayList(ImportInfo)) !void {
        const node_type = node.kind();
        
        if (std.mem.eql(u8, node_type, "import_statement") or
            std.mem.eql(u8, node_type, "builtin_call")) {
            const text = self.getNodeText(node, source);
            if (std.mem.indexOf(u8, text, "@import") != null) {
                const import_info = try self.parseZigImport(node, source, file_path);
                try imports.append(import_info);
            }
        }
        
        // Recurse into children
        const child_count = node.childCount();
        var i: u32 = 0;
        while (i < child_count) : (i += 1) {
            if (node.child(i)) |child| {
                try self.walkZigAST(child, source, file_path, imports);
            }
        }
    }
    
    fn walkCSSAST(self: *Self, node: ts.Node, source: []const u8, file_path: []const u8,
                  imports: *collection_helpers.CollectionHelpers.ManagedArrayList(ImportInfo)) !void {
        const node_type = node.kind();
        
        if (std.mem.eql(u8, node_type, "import_statement") or
            std.mem.eql(u8, node_type, "at_rule")) {
            const text = self.getNodeText(node, source);
            if (std.mem.indexOf(u8, text, "@import") != null) {
                const import_info = try self.parseCSSImport(node, source, file_path);
                try imports.append(import_info);
            }
        }
        
        // Recurse into children
        const child_count = node.childCount();
        var i: u32 = 0;
        while (i < child_count) : (i += 1) {
            if (node.child(i)) |child| {
                try self.walkCSSAST(child, source, file_path, imports);
            }
        }
    }
    
    // Parsing methods for specific import types
    
    fn parseTypeScriptImport(self: *Self, node: ts.Node, source: []const u8, file_path: []const u8) !ImportInfo {
        // Extract import path
        const import_path = try self.extractImportPath(node, source);
        const line_number = self.getLineNumber(node, source);
        
        // Determine import type and extract symbols
        if (node.childByFieldName("source")) |_| {
            
            var import_info = ImportInfo{
                .source_file = try self.allocator.dupe(u8, file_path),
                .import_path = import_path,
                .resolved_path = null, // Will be resolved later
                .import_type = .named_import, // Default, will be refined
                .symbols = &.{},
                .default_import = null,
                .namespace_import = null,
                .line_number = line_number,
                .is_dynamic = false,
                .is_type_only = false,
            };
            
            // Parse import clause to extract symbols
            if (node.childByFieldName("import_clause")) |import_clause| {
                try self.parseTypeScriptImportClause(import_clause, source, &import_info);
            }
            
            return import_info;
        }
        
        return error.InvalidImport;
    }
    
    fn parseTypeScriptExport(self: *Self, node: ts.Node, source: []const u8, file_path: []const u8) !ExportInfo {
        // Parse export statement
        const line_number = self.getLineNumber(node, source);
        
        var export_info = ExportInfo{
            .source_file = try self.allocator.dupe(u8, file_path),
            .export_path = null,
            .symbols = &.{},
            .is_default = false,
            .is_namespace = false,
            .line_number = line_number,
        };
        
        // Extract export details
        const node_text = self.getNodeText(node, source);
        
        if (std.mem.indexOf(u8, node_text, "export default") != null) {
            export_info.is_default = true;
        } else if (std.mem.indexOf(u8, node_text, "export *") != null) {
            export_info.is_namespace = true;
        }
        
        // Extract re-export path if present
        if (std.mem.indexOf(u8, node_text, "from") != null) {
            export_info.export_path = try self.extractImportPath(node, source);
        }
        
        return export_info;
    }
    
    fn parseZigImport(self: *Self, node: ts.Node, source: []const u8, file_path: []const u8) !ImportInfo {
        const node_text = self.getNodeText(node, source);
        const line_number = self.getLineNumber(node, source);
        
        // Extract import path from @import("path")
        const start = std.mem.indexOf(u8, node_text, "\"");
        const end = if (start) |_| std.mem.lastIndexOf(u8, node_text, "\"") else null;
        
        if (start == null or end == null or start.? >= end.?) {
            return error.InvalidZigImport;
        }
        
        const import_path = node_text[start.? + 1..end.?];
        
        return ImportInfo{
            .source_file = try self.allocator.dupe(u8, file_path),
            .import_path = try self.allocator.dupe(u8, import_path),
            .resolved_path = null,
            .import_type = .zig_import,
            .symbols = &.{},
            .default_import = null,
            .namespace_import = null,
            .line_number = line_number,
            .is_dynamic = false,
            .is_type_only = false,
        };
    }
    
    fn parseCSSImport(self: *Self, node: ts.Node, source: []const u8, file_path: []const u8) !ImportInfo {
        const node_text = self.getNodeText(node, source);
        const line_number = self.getLineNumber(node, source);
        
        // Parse @import url("path") or @import "path"
        var import_path: []const u8 = "";
        
        if (std.mem.indexOf(u8, node_text, "url(")) |url_start| {
            const start = std.mem.indexOf(u8, node_text[url_start..], "\"");
            const end = if (start) |s| std.mem.indexOf(u8, node_text[url_start + s + 1..], "\"") else null;
            
            if (start != null and end != null) {
                const full_start = url_start + start.? + 1;
                const full_end = full_start + end.?;
                import_path = node_text[full_start..full_end];
            }
        } else {
            // Direct string import
            const start = std.mem.indexOf(u8, node_text, "\"");
            const end = if (start) |_| std.mem.lastIndexOf(u8, node_text, "\"") else null;
            
            if (start != null and end != null and start.? < end.?) {
                import_path = node_text[start.? + 1..end.?];
            }
        }
        
        return ImportInfo{
            .source_file = try self.allocator.dupe(u8, file_path),
            .import_path = try self.allocator.dupe(u8, import_path),
            .resolved_path = null,
            .import_type = .side_effect_import,
            .symbols = &.{},
            .default_import = null,
            .namespace_import = null,
            .line_number = line_number,
            .is_dynamic = false,
            .is_type_only = false,
        };
    }
    
    fn parseTypeScriptImportClause(self: *Self, import_clause: ts.Node, source: []const u8, import_info: *ImportInfo) !void {
        // This is a placeholder - would need detailed AST parsing for full implementation
        // For now, we'll do basic text-based parsing
        const clause_text = self.getNodeText(import_clause, source);
        
        // Check for default import
        if (std.mem.indexOf(u8, clause_text, "{") == null and std.mem.indexOf(u8, clause_text, "*") == null) {
            import_info.import_type = .default_import;
            // Extract default import name (simplified)
            const trimmed = std.mem.trim(u8, clause_text, " \t\n");
            import_info.default_import = try self.allocator.dupe(u8, trimmed);
        }
        // Check for namespace import
        else if (std.mem.indexOf(u8, clause_text, "*") != null) {
            import_info.import_type = .namespace_import;
            // Extract namespace name (simplified)
            if (std.mem.indexOf(u8, clause_text, " as ")) |as_pos| {
                const name_start = as_pos + 4;
                const name = std.mem.trim(u8, clause_text[name_start..], " \t\n");
                import_info.namespace_import = try self.allocator.dupe(u8, name);
            }
        }
        // Named imports
        else {
            import_info.import_type = .named_import;
            // Would need more sophisticated parsing to extract individual symbols
        }
    }
    
    // Fallback text-based extractors for when AST parsing fails
    
    fn extractTypeScriptFallback(self: *Self, file_path: []const u8, source: []const u8) !ExtractionResult {
        var imports = collection_helpers.CollectionHelpers.ManagedArrayList(ImportInfo).init(self.allocator);
        defer imports.deinit();
        
        var exports = collection_helpers.CollectionHelpers.ManagedArrayList(ExportInfo).init(self.allocator);
        defer exports.deinit();
        
        var lines = std.mem.splitScalar(u8, source, '\n');
        var line_number: u32 = 1;
        
        while (lines.next()) |line| {
            defer line_number += 1;
            const trimmed = std.mem.trim(u8, line, " \t");
            
            if (std.mem.startsWith(u8, trimmed, "import ")) {
                if (self.parseTypeScriptImportLine(trimmed, file_path, line_number)) |import_info| {
                    try imports.append(import_info);
                } else |_| {
                    // Ignore parse errors
                }
            } else if (std.mem.startsWith(u8, trimmed, "export ")) {
                if (self.parseTypeScriptExportLine(trimmed, file_path, line_number)) |export_info| {
                    try exports.append(export_info);
                } else |_| {
                    // Ignore parse errors
                }
            }
        }
        
        return ExtractionResult{
            .imports = try imports.toOwnedSlice(),
            .exports = try exports.toOwnedSlice(),
        };
    }
    
    fn extractZigFallback(self: *Self, file_path: []const u8, source: []const u8) !ExtractionResult {
        var imports = collection_helpers.CollectionHelpers.ManagedArrayList(ImportInfo).init(self.allocator);
        defer imports.deinit();
        
        var lines = std.mem.splitScalar(u8, source, '\n');
        var line_number: u32 = 1;
        
        while (lines.next()) |line| {
            defer line_number += 1;
            
            if (std.mem.indexOf(u8, line, "@import(\"") != null) {
                if (self.parseZigImportLine(line, file_path, line_number)) |import_info| {
                    try imports.append(import_info);
                } else |_| {
                    // Ignore parse errors
                }
            }
        }
        
        return ExtractionResult{
            .imports = try imports.toOwnedSlice(),
            .exports = &.{},
        };
    }
    
    fn extractCFallback(self: *Self, file_path: []const u8, source: []const u8) !ExtractionResult {
        var imports = collection_helpers.CollectionHelpers.ManagedArrayList(ImportInfo).init(self.allocator);
        defer imports.deinit();
        
        var lines = std.mem.splitScalar(u8, source, '\n');
        var line_number: u32 = 1;
        
        while (lines.next()) |line| {
            defer line_number += 1;
            const trimmed = std.mem.trim(u8, line, " \t");
            
            if (std.mem.startsWith(u8, trimmed, "#include ")) {
                if (self.parseCIncludeLine(trimmed, file_path, line_number)) |import_info| {
                    try imports.append(import_info);
                } else |_| {
                    // Ignore parse errors
                }
            }
        }
        
        return ExtractionResult{
            .imports = try imports.toOwnedSlice(),
            .exports = &.{},
        };
    }
    
    // Text-based line parsers
    
    fn parseTypeScriptImportLine(self: *Self, line: []const u8, file_path: []const u8, line_number: u32) !ImportInfo {
        // Simple regex-like parsing for common import patterns
        if (std.mem.indexOf(u8, line, " from ")) |from_pos| {
            const from_part = line[from_pos + 6..];
            const quote_start = std.mem.indexOfAny(u8, from_part, "'\"");
            
            if (quote_start == null) return error.InvalidImport;
            
            const quote_char = from_part[quote_start.?];
            const path_start = quote_start.? + 1;
            const path_end = std.mem.indexOfScalar(u8, from_part[path_start..], quote_char);
            
            if (path_end == null) return error.InvalidImport;
            
            const import_path = from_part[path_start..path_start + path_end.?];
            
            return ImportInfo{
                .source_file = try self.allocator.dupe(u8, file_path),
                .import_path = try self.allocator.dupe(u8, import_path),
                .resolved_path = null,
                .import_type = .named_import, // Simplified
                .symbols = &.{},
                .default_import = null,
                .namespace_import = null,
                .line_number = line_number,
                .is_dynamic = false,
                .is_type_only = std.mem.indexOf(u8, line, "import type") != null,
            };
        }
        
        return error.InvalidImport;
    }
    
    fn parseTypeScriptExportLine(self: *Self, line: []const u8, file_path: []const u8, line_number: u32) !ExportInfo {
        return ExportInfo{
            .source_file = try self.allocator.dupe(u8, file_path),
            .export_path = null,
            .symbols = &.{},
            .is_default = std.mem.indexOf(u8, line, "export default") != null,
            .is_namespace = std.mem.indexOf(u8, line, "export *") != null,
            .line_number = line_number,
        };
    }
    
    fn parseZigImportLine(self: *Self, line: []const u8, file_path: []const u8, line_number: u32) !ImportInfo {
        const start = std.mem.indexOf(u8, line, "@import(\"");
        if (start == null) return error.InvalidImport;
        
        const path_start = start.? + 9;
        const path_end = std.mem.indexOf(u8, line[path_start..], "\"");
        if (path_end == null) return error.InvalidImport;
        
        const import_path = line[path_start..path_start + path_end.?];
        
        return ImportInfo{
            .source_file = try self.allocator.dupe(u8, file_path),
            .import_path = try self.allocator.dupe(u8, import_path),
            .resolved_path = null,
            .import_type = .zig_import,
            .symbols = &.{},
            .default_import = null,
            .namespace_import = null,
            .line_number = line_number,
            .is_dynamic = false,
            .is_type_only = false,
        };
    }
    
    fn parseCIncludeLine(self: *Self, line: []const u8, file_path: []const u8, line_number: u32) !ImportInfo {
        var import_type: ImportType = .c_include;
        var path_start: usize = 0;
        var path_end: usize = 0;
        
        if (std.mem.indexOf(u8, line, "#include \"")) |start| {
            path_start = start + 10;
            path_end = std.mem.indexOf(u8, line[path_start..], "\"") orelse return error.InvalidInclude;
            path_end += path_start;
        } else if (std.mem.indexOf(u8, line, "#include <")) |start| {
            path_start = start + 10;
            path_end = std.mem.indexOf(u8, line[path_start..], ">") orelse return error.InvalidInclude;
            path_end += path_start;
            import_type = .c_include_system;
        } else {
            return error.InvalidInclude;
        }
        
        const include_path = line[path_start..path_end];
        
        return ImportInfo{
            .source_file = try self.allocator.dupe(u8, file_path),
            .import_path = try self.allocator.dupe(u8, include_path),
            .resolved_path = null,
            .import_type = import_type,
            .symbols = &.{},
            .default_import = null,
            .namespace_import = null,
            .line_number = line_number,
            .is_dynamic = false,
            .is_type_only = false,
        };
    }
    
    // Svelte section extractors
    
    fn extractSvelteScriptSection(self: *Self, source: []const u8) ?[]const u8 {
        const script_start = std.mem.indexOf(u8, source, "<script");
        if (script_start == null) return null;
        
        const content_start = std.mem.indexOf(u8, source[script_start..], ">");
        if (content_start == null) return null;
        
        const full_start = script_start.? + content_start.? + 1;
        const script_end = std.mem.indexOf(u8, source[full_start..], "</script>");
        if (script_end == null) return null;
        
        const content = source[full_start..full_start + script_end.?];
        return self.allocator.dupe(u8, content) catch null;
    }
    
    fn extractSvelteStyleSection(self: *Self, source: []const u8) ?[]const u8 {
        const style_start = std.mem.indexOf(u8, source, "<style");
        if (style_start == null) return null;
        
        const content_start = std.mem.indexOf(u8, source[style_start..], ">");
        if (content_start == null) return null;
        
        const full_start = style_start.? + content_start.? + 1;
        const style_end = std.mem.indexOf(u8, source[full_start..], "</style>");
        if (style_end == null) return null;
        
        const content = source[full_start..full_start + style_end.?];
        return self.allocator.dupe(u8, content) catch null;
    }
    
    // Utility methods
    
    fn getNodeText(self: *Self, node: ts.Node, source: []const u8) []const u8 {
        _ = self;
        const start = node.startByte();
        const end = node.endByte();
        if (end <= source.len and start <= end) {
            return source[start..end];
        }
        return "";
    }
    
    fn getLineNumber(self: *Self, node: ts.Node, source: []const u8) u32 {
        _ = self;
        const start_byte = node.startByte();
        var line_number: u32 = 1;
        
        for (source[0..@min(start_byte, source.len)]) |char| {
            if (char == '\n') {
                line_number += 1;
            }
        }
        
        return line_number;
    }
    
    fn extractImportPath(self: *Self, node: ts.Node, source: []const u8) ![]const u8 {
        // Look for string literal containing the import path
        const child_count = node.childCount();
        var i: u32 = 0;
        while (i < child_count) : (i += 1) {
            if (node.child(i)) |child| {
                const child_type = child.kind();
                if (std.mem.eql(u8, child_type, "string_literal") or
                    std.mem.eql(u8, child_type, "string")) {
                    const text = self.getNodeText(child, source);
                    // Remove quotes
                    if (text.len >= 2 and (text[0] == '"' or text[0] == '\'')) {
                        return self.allocator.dupe(u8, text[1..text.len-1]);
                    }
                    return self.allocator.dupe(u8, text);
                }
            }
        }
        
        return error.NoImportPath;
    }
    
    fn createCacheKey(self: *Self, file_path: []const u8, source: []const u8) AstCacheKey {
        _ = self;
        _ = file_path; // Future: could include file path in cache key
        
        // Hash the source content
        var hasher = std.hash.XxHash64.init(0);
        hasher.update(source);
        const content_hash = hasher.final();
        
        // Use a constant extraction flags hash for import extraction
        const extraction_hash: u64 = 0x1234567890abcdef;
        
        return AstCacheKey.init(content_hash, 1, extraction_hash);
    }
    
    fn serializeResult(self: *Self, result: ExtractionResult) ![]const u8 {
        // Simple JSON-like serialization for caching
        // In production, could use more efficient binary format
        var output = std.ArrayList(u8).init(self.allocator);
        defer output.deinit();
        
        try output.appendSlice("{\"imports\":[");
        for (result.imports, 0..) |import_info, i| {
            if (i > 0) try output.appendSlice(",");
            try output.writer().print("{{\"path\":\"{s}\",\"type\":{d},\"line\":{d}}}", .{
                import_info.import_path, @intFromEnum(import_info.import_type), import_info.line_number
            });
        }
        try output.appendSlice("],\"exports\":[");
        for (result.exports, 0..) |export_info, i| {
            if (i > 0) try output.appendSlice(",");
            try output.writer().print("{{\"line\":{d},\"default\":{}}}", .{
                export_info.line_number, export_info.is_default
            });
        }
        try output.appendSlice("]}");
        
        return output.toOwnedSlice();
    }
    
    fn deserializeResult(self: *Self, data: []const u8) !ExtractionResult {
        // Simple deserialization - in production would use proper JSON parser
        // For now, return empty result
        _ = data;
        return ExtractionResult{
            .imports = try self.allocator.alloc(ImportInfo, 0),
            .exports = try self.allocator.alloc(ExportInfo, 0),
        };
    }
};

// Tests
test "import extractor initialization" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    const extractor = ImportExtractor.init(allocator);
    
    // Basic test to ensure initialization works
    try testing.expect(extractor.cache == null);
}

test "typescript import extraction fallback" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    var extractor = ImportExtractor.init(allocator);
    
    const source = 
        \\import { foo, bar } from './module';
        \\import React from 'react';
        \\export default function test() {}
    ;
    
    var result = try extractor.extractTypeScriptFallback("test.ts", source);
    defer result.deinit(allocator);
    
    try testing.expect(result.imports.len >= 1);
    try testing.expect(result.exports.len >= 1);
}

test "zig import extraction fallback" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    var extractor = ImportExtractor.init(allocator);
    
    const source = 
        \\const std = @import("std");
        \\const testing = @import("testing");
    ;
    
    var result = try extractor.extractZigFallback("test.zig", source);
    defer result.deinit(allocator);
    
    try testing.expect(result.imports.len == 2);
    try testing.expect(std.mem.eql(u8, result.imports[0].import_path, "std"));
    try testing.expect(std.mem.eql(u8, result.imports[1].import_path, "testing"));
}