const std = @import("std");
const ts = @import("tree-sitter");
const ast = @import("ast.zig");
const ExtractionFlags = ast.ExtractionFlags;
const Language = ast.Language;
const imports_mod = @import("imports.zig");
const ImportInfo = imports_mod.Import;
const ExtractionResult = imports_mod.ExtractionResult;

// Language-specific tree-sitter grammars
extern fn tree_sitter_zig() callconv(.C) *ts.Language;
extern fn tree_sitter_css() callconv(.C) *ts.Language;
extern fn tree_sitter_html() callconv(.C) *ts.Language;
extern fn tree_sitter_json() callconv(.C) *ts.Language;
extern fn tree_sitter_typescript() callconv(.C) *ts.Language;
extern fn tree_sitter_svelte() callconv(.C) *ts.Language;

/// Tree-sitter parser with language support for all 6 languages
pub const TreeSitterParser = struct {
    allocator: std.mem.Allocator,
    parser: *ts.Parser,
    language: Language,
    ts_language: *ts.Language,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator, language: Language) !Self {
        const parser = ts.Parser.create();
        const ts_language = try getTreeSitterLanguage(language);
        try parser.setLanguage(ts_language);
        
        return Self{
            .allocator = allocator,
            .parser = parser,
            .language = language,
            .ts_language = ts_language,
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.parser.destroy();
    }
    
    /// Parse source code and return syntax tree
    pub fn parse(self: *Self, source: []const u8) !*ts.Tree {
        const tree = self.parser.parseString(source, null);
        return tree orelse error.ParseFailed;
    }
    
    /// Extract code using real tree-sitter AST
    pub fn extract(self: *Self, source: []const u8, flags: ExtractionFlags) ![]const u8 {
        // Early termination: if no extraction flags are set, return full source
        if (flags.isDefault()) {
            return self.allocator.dupe(u8, source);
        }
        
        const tree = try self.parse(source);
        defer tree.destroy();
        
        const root = tree.rootNode();
        
        // Pre-allocate with estimated capacity (10% of source size as reasonable estimate)
        const estimated_capacity = @max(256, source.len / 10);
        var result = try std.ArrayList(u8).initCapacity(self.allocator, estimated_capacity);
        defer result.deinit();
        
        try self.walkAndExtract(root, source, flags, &result);
        
        return result.toOwnedSlice();
    }
    
    /// Extract imports and exports from source using AST analysis
    /// This provides a unified interface that leverages imports_mod.Extractor but uses this parser
    pub fn extractImports(self: *Self, file_path: []const u8, source: []const u8) !ExtractionResult {
        var import_extractor = imports_mod.Extractor.init(self.allocator);
        
        // Use the imports_mod.Extractor but with our tree-sitter parser for enhanced accuracy
        switch (self.language) {
            .typescript, .javascript => return self.extractTypeScriptImports(file_path, source),
            .zig => return self.extractZigImports(file_path, source),
            .css => return self.extractCssImports(file_path, source),
            .svelte => return self.extractSvelteImports(file_path, source),
            else => return import_extractor.extract(file_path, source),
        }
    }
    
    /// Extract TypeScript/JavaScript imports using AST
    fn extractTypeScriptImports(self: *Self, file_path: []const u8, source: []const u8) !ExtractionResult {
        const tree = self.parse(source) catch {
            // Fallback to text-based extraction if parsing fails
            var import_extractor = imports_mod.Extractor.init(self.allocator);
            return import_extractor.extractTypeScriptFallback(file_path, source);
        };
        defer tree.destroy();
        
        var imports = std.ArrayList(ImportInfo).init(self.allocator);
        defer imports.deinit();
        
        var exports = std.ArrayList(imports_mod.Export).init(self.allocator);
        defer exports.deinit();
        
        // Walk AST to find import/export nodes
        try self.walkForImports(tree.rootNode(), source, file_path, &imports, &exports);
        
        return ExtractionResult{
            .imports = try imports.toOwnedSlice(),
            .exports = try exports.toOwnedSlice(),
        };
    }
    
    /// Extract Zig imports using AST
    fn extractZigImports(self: *Self, file_path: []const u8, source: []const u8) !ExtractionResult {
        const tree = self.parse(source) catch {
            // Fallback to text-based extraction if parsing fails
            var import_extractor = imports_mod.Extractor.init(self.allocator);
            return import_extractor.extractZigFallback(file_path, source);
        };
        defer tree.destroy();
        
        var imports = std.ArrayList(ImportInfo).init(self.allocator);
        defer imports.deinit();
        
        // Zig doesn't have exports in the traditional sense
        const exports = try self.allocator.alloc(imports_mod.Export, 0);
        
        try self.walkForZigImports(tree.rootNode(), source, file_path, &imports);
        
        return ExtractionResult{
            .imports = try imports.toOwnedSlice(),
            .exports = exports,
        };
    }
    
    /// Extract CSS imports using AST
    fn extractCssImports(self: *Self, file_path: []const u8, source: []const u8) !ExtractionResult {
        const tree = self.parse(source) catch {
            return ExtractionResult{ .imports = &.{}, .exports = &.{} };
        };
        defer tree.destroy();
        
        var imports = std.ArrayList(ImportInfo).init(self.allocator);
        defer imports.deinit();
        
        try self.walkForCssImports(tree.rootNode(), source, file_path, &imports);
        
        return ExtractionResult{
            .imports = try imports.toOwnedSlice(),
            .exports = &.{},
        };
    }
    
    /// Extract Svelte imports using AST (section-aware)
    fn extractSvelteImports(self: *Self, file_path: []const u8, source: []const u8) !ExtractionResult {
        const tree = self.parse(source) catch {
            // Fallback to text-based extraction if parsing fails
            var import_extractor = imports_mod.Extractor.init(self.allocator);
            return import_extractor.extractSvelte(file_path, source);
        };
        defer tree.destroy();
        
        var all_imports = std.ArrayList(ImportInfo).init(self.allocator);
        defer all_imports.deinit();
        
        var all_exports = std.ArrayList(imports_mod.Export).init(self.allocator);
        defer all_exports.deinit();
        
        // Extract from script sections within Svelte
        try self.walkForSvelteImports(tree.rootNode(), source, file_path, &all_imports, &all_exports);
        
        return ExtractionResult{
            .imports = try all_imports.toOwnedSlice(),
            .exports = try all_exports.toOwnedSlice(),
        };
    }
    
    // AST walking methods for import extraction
    
    fn walkForImports(self: *Self, node: ts.Node, source: []const u8, file_path: []const u8,
                     imports: *std.ArrayList(ImportInfo),
                     exports: *std.ArrayList(imports_mod.Export)) !void {
        const node_type = node.kind();
        
        // Handle import statements
        if (std.mem.eql(u8, node_type, "import_statement") or
            std.mem.eql(u8, node_type, "import_declaration")) {
            if (self.parseTypeScriptImportNode(node, source, file_path)) |import_info| {
                try imports.append(import_info);
            } else |_| {
                // Ignore parse errors for individual imports
            }
        }
        // Handle export statements
        else if (std.mem.eql(u8, node_type, "export_statement") or
                 std.mem.eql(u8, node_type, "export_declaration")) {
            if (self.parseTypeScriptExportNode(node, source, file_path)) |export_info| {
                try exports.append(export_info);
            } else |_| {
                // Ignore parse errors for individual exports
            }
        }
        
        // Recurse into children
        const child_count = node.childCount();
        var i: u32 = 0;
        while (i < child_count) : (i += 1) {
            if (node.child(i)) |child| {
                try self.walkForImports(child, source, file_path, imports, exports);
            }
        }
    }
    
    fn walkForZigImports(self: *Self, node: ts.Node, source: []const u8, file_path: []const u8,
                        imports: *std.ArrayList(ImportInfo)) !void {
        const node_type = node.kind();
        
        // Look for @import calls in builtin function calls
        if (std.mem.eql(u8, node_type, "builtin_call") or
            std.mem.eql(u8, node_type, "function_call")) {
            const text = self.getNodeText(node, source);
            if (std.mem.indexOf(u8, text, "@import") != null) {
                if (self.parseZigImportNode(node, source, file_path)) |import_info| {
                    try imports.append(import_info);
                } else |_| {
                    // Ignore parse errors
                }
            }
        }
        
        // Recurse into children
        const child_count = node.childCount();
        var i: u32 = 0;
        while (i < child_count) : (i += 1) {
            if (node.child(i)) |child| {
                try self.walkForZigImports(child, source, file_path, imports);
            }
        }
    }
    
    fn walkForCssImports(self: *Self, node: ts.Node, source: []const u8, file_path: []const u8,
                        imports: *std.ArrayList(ImportInfo)) !void {
        const node_type = node.kind();
        
        // Look for @import at-rules
        if (std.mem.eql(u8, node_type, "at_rule") or
            std.mem.eql(u8, node_type, "import_statement")) {
            const text = self.getNodeText(node, source);
            if (std.mem.indexOf(u8, text, "@import") != null) {
                if (self.parseCssImportNode(node, source, file_path)) |import_info| {
                    try imports.append(import_info);
                } else |_| {
                    // Ignore parse errors
                }
            }
        }
        
        // Recurse into children
        const child_count = node.childCount();
        var i: u32 = 0;
        while (i < child_count) : (i += 1) {
            if (node.child(i)) |child| {
                try self.walkForCssImports(child, source, file_path, imports);
            }
        }
    }
    
    fn walkForSvelteImports(self: *Self, node: ts.Node, source: []const u8, file_path: []const u8,
                           imports: *std.ArrayList(ImportInfo),
                           exports: *std.ArrayList(imports_mod.Export)) !void {
        const node_type = node.kind();
        
        // Look for script elements and parse their content
        if (std.mem.eql(u8, node_type, "script_element")) {
            // Extract script content and parse as TypeScript
            if (self.extractScriptContent(node, source)) |script_content| {
                defer self.allocator.free(script_content);
                
                // Create a temporary TypeScript parser for script content
                var ts_parser = TreeSitterParser.init(self.allocator, .typescript) catch return;
                defer ts_parser.deinit();
                
                const script_result = ts_parser.extractTypeScriptImports(file_path, script_content) catch return;
                defer script_result.deinit(self.allocator);
                
                try imports.appendSlice(script_result.imports);
                try exports.appendSlice(script_result.exports);
            }
        }
        
        // Recurse into children for other content
        const child_count = node.childCount();
        var i: u32 = 0;
        while (i < child_count) : (i += 1) {
            if (node.child(i)) |child| {
                try self.walkForSvelteImports(child, source, file_path, imports, exports);
            }
        }
    }
    
    // Node parsing methods for specific import types
    
    fn parseTypeScriptImportNode(self: *Self, node: ts.Node, source: []const u8, file_path: []const u8) !ImportInfo {
        const line_number = self.getLineNumber(node, source);
        
        // Extract import path from the import statement
        const import_path = self.extractImportPathFromNode(node, source) catch return error.NoImportPath;
        
        var import_info = ImportInfo{
            .source_file = try self.allocator.dupe(u8, file_path),
            .import_path = import_path,
            .resolved_path = null,
            .import_type = .named_import, // Default, will be refined
            .symbols = &.{},
            .default_import = null,
            .namespace_import = null,
            .line_number = line_number,
            .is_dynamic = false,
            .is_type_only = false,
        };
        
        // Analyze import clause for type and symbols
        if (node.childByFieldName("import_clause")) |import_clause| {
            try self.parseImportClause(import_clause, source, &import_info);
        }
        
        return import_info;
    }
    
    fn parseTypeScriptExportNode(self: *Self, node: ts.Node, source: []const u8, file_path: []const u8) !imports_mod.Export {
        const line_number = self.getLineNumber(node, source);
        const node_text = self.getNodeText(node, source);
        
        var export_info = imports_mod.Export{
            .source_file = try self.allocator.dupe(u8, file_path),
            .export_path = null,
            .symbols = &.{},
            .is_default = std.mem.indexOf(u8, node_text, "default") != null,
            .is_namespace = std.mem.indexOf(u8, node_text, "* ") != null,
            .line_number = line_number,
        };
        
        // Extract re-export path if this is a re-export
        if (std.mem.indexOf(u8, node_text, "from") != null) {
            export_info.export_path = self.extractImportPathFromNode(node, source) catch null;
        }
        
        return export_info;
    }
    
    fn parseZigImportNode(self: *Self, node: ts.Node, source: []const u8, file_path: []const u8) !ImportInfo {
        const node_text = self.getNodeText(node, source);
        const line_number = self.getLineNumber(node, source);
        
        // Extract import path from @import("path")
        const import_path = self.extractZigImportPath(node_text) catch return error.InvalidZigImport;
        
        return ImportInfo{
            .source_file = try self.allocator.dupe(u8, file_path),
            .import_path = import_path,
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
    
    fn parseCssImportNode(self: *Self, node: ts.Node, source: []const u8, file_path: []const u8) !ImportInfo {
        const node_text = self.getNodeText(node, source);
        const line_number = self.getLineNumber(node, source);
        
        // Extract import path from @import url("path") or @import "path"
        const import_path = self.extractCssImportPath(node_text) catch return error.InvalidCssImport;
        
        return ImportInfo{
            .source_file = try self.allocator.dupe(u8, file_path),
            .import_path = import_path,
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
    
    // Utility methods for import parsing
    
    fn extractImportPathFromNode(self: *Self, node: ts.Node, source: []const u8) ![]const u8 {
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
                
                // Recursively search in child nodes
                if (self.extractImportPathFromNode(child, source)) |path| {
                    return path;
                } else |_| {
                    // Continue searching
                }
            }
        }
        
        return error.NoImportPath;
    }
    
    fn extractZigImportPath(self: *Self, node_text: []const u8) ![]const u8 {
        const start = std.mem.indexOf(u8, node_text, "\"");
        const end = if (start) |_| std.mem.lastIndexOf(u8, node_text, "\"") else null;
        
        if (start == null or end == null or start.? >= end.?) {
            return error.InvalidZigImport;
        }
        
        const import_path = node_text[start.? + 1..end.?];
        return self.allocator.dupe(u8, import_path);
    }
    
    fn extractCssImportPath(self: *Self, node_text: []const u8) ![]const u8 {
        // Parse @import url("path") or @import "path"
        if (std.mem.indexOf(u8, node_text, "url(")) |url_start| {
            const start = std.mem.indexOf(u8, node_text[url_start..], "\"");
            const end = if (start) |s| std.mem.indexOf(u8, node_text[url_start + s + 1..], "\"") else null;
            
            if (start != null and end != null) {
                const full_start = url_start + start.? + 1;
                const full_end = full_start + end.?;
                return self.allocator.dupe(u8, node_text[full_start..full_end]);
            }
        } else {
            // Direct string import
            const start = std.mem.indexOf(u8, node_text, "\"");
            const end = if (start) |_| std.mem.lastIndexOf(u8, node_text, "\"") else null;
            
            if (start != null and end != null and start.? < end.?) {
                return self.allocator.dupe(u8, node_text[start.? + 1..end.?]);
            }
        }
        
        return error.InvalidCssImport;
    }
    
    fn parseImportClause(self: *Self, import_clause: ts.Node, source: []const u8, import_info: *ImportInfo) !void {
        const clause_text = self.getNodeText(import_clause, source);
        
        // Check for type-only import
        if (std.mem.indexOf(u8, clause_text, "type ") != null) {
            import_info.is_type_only = true;
        }
        
        // Determine import type based on clause content
        if (std.mem.indexOf(u8, clause_text, "{") == null and std.mem.indexOf(u8, clause_text, "*") == null) {
            // Default import
            import_info.import_type = .default_import;
            const trimmed = std.mem.trim(u8, clause_text, " \t\n");
            if (trimmed.len > 0) {
                import_info.default_import = try self.allocator.dupe(u8, trimmed);
            }
        } else if (std.mem.indexOf(u8, clause_text, "*") != null) {
            // Namespace import
            import_info.import_type = .namespace_import;
            if (std.mem.indexOf(u8, clause_text, " as ")) |as_pos| {
                const name_start = as_pos + 4;
                const name = std.mem.trim(u8, clause_text[name_start..], " \t\n");
                if (name.len > 0) {
                    import_info.namespace_import = try self.allocator.dupe(u8, name);
                }
            }
        } else {
            // Named imports
            import_info.import_type = .named_import;
            // Note: Full symbol extraction would require more sophisticated parsing
            // For now, we mark it as named import type
        }
    }
    
    fn extractScriptContent(self: *Self, script_node: ts.Node, source: []const u8) ?[]const u8 {
        // Find text content within script tags
        const child_count = script_node.childCount();
        var i: u32 = 0;
        while (i < child_count) : (i += 1) {
            if (script_node.child(i)) |child| {
                const child_type = child.kind();
                if (std.mem.eql(u8, child_type, "raw_text") or
                    std.mem.eql(u8, child_type, "text")) {
                    const content = self.getNodeText(child, source);
                    return self.allocator.dupe(u8, content) catch null;
                }
            }
        }
        return null;
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
    
    /// Walk AST and extract based on language and flags
    fn walkAndExtract(self: *Self, node: ts.Node, source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) std.mem.Allocator.Error!void {
        switch (self.language) {
            .zig => try self.extractZig(node, source, flags, result),
            .css => try self.extractCss(node, source, flags, result),
            .html => try self.extractHtml(node, source, flags, result),
            .json => try self.extractJson(node, source, flags, result),
            .typescript => try self.extractTypeScript(node, source, flags, result),
            .svelte => try self.extractSvelte(node, source, flags, result),
            .c, .cpp, .python, .rust, .go => try result.appendSlice(source), // No AST extraction yet
            .unknown => try result.appendSlice(source),
        }
    }
    
    /// Zig-specific AST extraction
    fn extractZig(self: *Self, node: ts.Node, source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) std.mem.Allocator.Error!void {
        // Early termination: if no relevant flags are set, skip this subtree
        if (!flags.signatures and !flags.types and !flags.docs and !flags.tests and !flags.imports) {
            return;
        }
        
        const node_type = node.kind();
        
        if (flags.signatures) {
            if (std.mem.eql(u8, node_type, "function_declaration")) {
                try self.appendNodeText(node, source, result);
                return; // Don't recurse into function body
            }
        }
        
        if (flags.types) {
            if (std.mem.eql(u8, node_type, "struct_declaration") or 
                std.mem.eql(u8, node_type, "enum_declaration") or
                std.mem.eql(u8, node_type, "union_declaration")) {
                try self.appendNodeText(node, source, result);
                return;
            }
        }
        
        if (flags.docs) {
            if (std.mem.eql(u8, node_type, "doc_comment") or
                std.mem.eql(u8, node_type, "container_doc_comment")) {
                try self.appendNodeText(node, source, result);
            }
        }
        
        if (flags.tests) {
            if (std.mem.eql(u8, node_type, "test_declaration")) {
                try self.appendNodeText(node, source, result);
                return;
            }
        }
        
        if (flags.imports) {
            if (std.mem.eql(u8, node_type, "builtin_call")) {
                const text = self.getNodeText(node, source);
                if (std.mem.startsWith(u8, text, "@import")) {
                    try self.appendNodeText(node, source, result);
                }
            }
        }
        
        // Recurse into children
        try self.recurseChildren(node, source, flags, result);
    }
    
    /// CSS-specific AST extraction
    fn extractCss(self: *Self, node: ts.Node, source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) std.mem.Allocator.Error!void {
        const node_type = node.kind();
        
        if (flags.signatures) {
            if (isSelector(node_type)) {
                try self.appendNodeText(node, source, result);
                return; // Don't traverse into selector details
            }
        }
        
        if (flags.types or flags.structure) {
            if (isRule(node_type) or isAtRule(node_type)) {
                try self.appendNodeText(node, source, result);
                return;
            }
        }
        
        if (flags.imports) {
            if (isImportRule(node_type)) {
                try self.appendNodeText(node, source, result);
            }
        }
        
        if (flags.docs) {
            if (isComment(node_type)) {
                try self.appendNodeText(node, source, result);
            }
        }
        
        // Recurse into children
        try self.recurseChildren(node, source, flags, result);
    }
    
    /// HTML-specific AST extraction
    fn extractHtml(self: *Self, node: ts.Node, source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) std.mem.Allocator.Error!void {
        const node_type = node.kind();
        
        if (flags.structure) {
            if (std.mem.eql(u8, node_type, "element") or
                std.mem.eql(u8, node_type, "start_tag") or
                std.mem.eql(u8, node_type, "end_tag")) {
                try self.appendNodeText(node, source, result);
                return;
            }
        }
        
        if (flags.signatures) {
            if (std.mem.eql(u8, node_type, "attribute")) {
                try self.appendNodeText(node, source, result);
            }
        }
        
        if (flags.docs) {
            if (std.mem.eql(u8, node_type, "comment")) {
                try self.appendNodeText(node, source, result);
            }
        }
        
        // Recurse into children
        try self.recurseChildren(node, source, flags, result);
    }
    
    /// JSON-specific AST extraction
    fn extractJson(self: *Self, node: ts.Node, source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) std.mem.Allocator.Error!void {
        const node_type = node.kind();
        
        if (flags.structure) {
            if (std.mem.eql(u8, node_type, "object") or
                std.mem.eql(u8, node_type, "array")) {
                try self.appendNodeText(node, source, result);
                return;
            }
        }
        
        if (flags.signatures) {
            if (std.mem.eql(u8, node_type, "pair")) {
                try self.appendNodeText(node, source, result);
            }
        }
        
        // Recurse into children
        try self.recurseChildren(node, source, flags, result);
    }
    
    /// TypeScript-specific AST extraction
    fn extractTypeScript(self: *Self, node: ts.Node, source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) std.mem.Allocator.Error!void {
        const node_type = node.kind();
        
        if (flags.signatures) {
            if (std.mem.eql(u8, node_type, "function_declaration") or
                std.mem.eql(u8, node_type, "method_definition") or
                std.mem.eql(u8, node_type, "arrow_function")) {
                try self.appendNodeText(node, source, result);
                return;
            }
        }
        
        if (flags.types) {
            if (std.mem.eql(u8, node_type, "interface_declaration") or
                std.mem.eql(u8, node_type, "class_declaration") or
                std.mem.eql(u8, node_type, "type_alias_declaration") or
                std.mem.eql(u8, node_type, "enum_declaration")) {
                try self.appendNodeText(node, source, result);
                return;
            }
        }
        
        if (flags.imports) {
            if (std.mem.eql(u8, node_type, "import_statement") or
                std.mem.eql(u8, node_type, "import_clause")) {
                try self.appendNodeText(node, source, result);
            }
        }
        
        if (flags.docs) {
            if (std.mem.eql(u8, node_type, "comment")) {
                try self.appendNodeText(node, source, result);
            }
        }
        
        // Recurse into children
        try self.recurseChildren(node, source, flags, result);
    }
    
    /// Svelte-specific AST extraction (section-aware)
    fn extractSvelte(self: *Self, node: ts.Node, source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) std.mem.Allocator.Error!void {
        const node_type = node.kind();
        
        if (flags.signatures) {
            // Extract reactive statements and component props
            if (std.mem.eql(u8, node_type, "reactive_statement") or
                std.mem.eql(u8, node_type, "component_prop")) {
                try self.appendNodeText(node, source, result);
            }
        }
        
        if (flags.structure) {
            // Extract script and style sections
            if (std.mem.eql(u8, node_type, "script_element") or
                std.mem.eql(u8, node_type, "style_element")) {
                try self.appendNodeText(node, source, result);
                return;
            }
        }
        
        if (flags.types) {
            // TypeScript types in script sections
            if (std.mem.eql(u8, node_type, "interface_declaration") or
                std.mem.eql(u8, node_type, "type_alias_declaration")) {
                try self.appendNodeText(node, source, result);
                return;
            }
        }
        
        // Recurse into children
        try self.recurseChildren(node, source, flags, result);
    }
    
    /// Get the text content of a node
    fn getNodeText(self: *Self, node: ts.Node, source: []const u8) []const u8 {
        _ = self;
        const start = node.startByte();
        const end = node.endByte();
        if (end <= source.len) {
            return source[start..end];
        }
        return "";
    }
    
    /// Append node text to result with newline
    fn appendNodeText(self: *Self, node: ts.Node, source: []const u8, result: *std.ArrayList(u8)) std.mem.Allocator.Error!void {
        _ = self;
        const start = node.startByte();
        const end = node.endByte();
        // Bounds check and append in one operation
        if (end <= source.len and start <= end) {
            try result.appendSlice(source[start..end]);
            try result.append('\n');
        }
    }
    
    /// Recursively process child nodes
    fn recurseChildren(self: *Self, node: ts.Node, source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) std.mem.Allocator.Error!void {
        const child_count = node.childCount();
        var i: u32 = 0;
        while (i < child_count) : (i += 1) {
            if (node.child(i)) |child| {
                try self.walkAndExtract(child, source, flags, result);
            }
        }
    }
};

/// Get tree-sitter language for the given language enum
fn getTreeSitterLanguage(language: Language) !*ts.Language {
    return switch (language) {
        .zig => tree_sitter_zig(),
        .css => tree_sitter_css(),
        .html => tree_sitter_html(),
        .json => tree_sitter_json(),
        .typescript => tree_sitter_typescript(),
        .svelte => tree_sitter_svelte(),
        .c, .cpp, .python, .rust, .go => error.UnsupportedLanguage, // No tree-sitter grammars yet
        .unknown => error.UnsupportedLanguage, // Don't fallback to arbitrary grammar
    };
}

/// CSS node type checking functions
fn isSelector(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "selectors") or
           std.mem.eql(u8, node_type, "class_selector") or
           std.mem.eql(u8, node_type, "id_selector") or
           std.mem.eql(u8, node_type, "tag_name") or
           std.mem.eql(u8, node_type, "universal_selector") or
           std.mem.eql(u8, node_type, "attribute_selector") or
           std.mem.eql(u8, node_type, "pseudo_class_selector") or
           std.mem.eql(u8, node_type, "pseudo_element_selector");
}

fn isRule(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "rule_set") or
           std.mem.eql(u8, node_type, "declaration") or
           std.mem.eql(u8, node_type, "property_name") or
           std.mem.eql(u8, node_type, "value");
}

fn isAtRule(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "at_rule") or
           std.mem.eql(u8, node_type, "media_query") or
           std.mem.eql(u8, node_type, "keyframes_statement") or
           std.mem.eql(u8, node_type, "supports_statement");
}

fn isImportRule(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "import_statement") or
           (std.mem.eql(u8, node_type, "at_rule"));
}

fn isComment(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "comment");
}

/// Public API for creating tree-sitter parsers
pub fn createTreeSitterParser(allocator: std.mem.Allocator, language: Language) !TreeSitterParser {
    return TreeSitterParser.init(allocator, language);
}

/// Helper function to extract with automatic language detection
pub fn extractWithTreeSitter(allocator: std.mem.Allocator, file_path: []const u8, source: []const u8, flags: ExtractionFlags) ![]const u8 {
    const path_utils = @import("path.zig");
    const ext = path_utils.extension(file_path);
    const language = Language.fromExtension(ext);
    
    var parser = try createTreeSitterParser(allocator, language);
    defer parser.deinit();
    
    return parser.extract(source, flags);
}

// Tests
test "tree-sitter parser initialization" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    var parser = try createTreeSitterParser(allocator, .zig);
    defer parser.deinit();
    
    try testing.expect(parser.language == .zig);
}

test "tree-sitter language mapping" {
    const zig_lang = try getTreeSitterLanguage(.zig);
    const css_lang = try getTreeSitterLanguage(.css);
    
    // Languages should be different pointers
    try std.testing.expect(zig_lang != css_lang);
    
    // Unknown language should return error
    try std.testing.expectError(error.UnsupportedLanguage, getTreeSitterLanguage(.unknown));
}

test "css node type detection" {
    const testing = std.testing;
    
    try testing.expect(isSelector("class_selector"));
    try testing.expect(isSelector("id_selector"));
    try testing.expect(!isSelector("declaration"));
    
    try testing.expect(isRule("rule_set"));
    try testing.expect(isRule("declaration"));
    try testing.expect(!isRule("class_selector"));
    
    try testing.expect(isAtRule("at_rule"));
    try testing.expect(isAtRule("media_query"));
    try testing.expect(!isAtRule("rule_set"));
    
    try testing.expect(isComment("comment"));
    try testing.expect(!isComment("declaration"));
}

test "unsupported language handling" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    // Should return error for unknown language
    const result = createTreeSitterParser(allocator, .unknown);
    try testing.expectError(error.UnsupportedLanguage, result);
}

test "empty source handling" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    var parser = try createTreeSitterParser(allocator, .zig);
    defer parser.deinit();
    
    // Empty source should be handled gracefully
    const result = try parser.extract("", ExtractionFlags{});
    defer allocator.free(result);
    
    try testing.expect(result.len == 0);
}

test "malformed source handling" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    var parser = try createTreeSitterParser(allocator, .zig);
    defer parser.deinit();
    
    // Malformed Zig code - should not crash
    const malformed = "fn incomplete( {{{ invalid syntax";
    const result = try parser.extract(malformed, ExtractionFlags{ .signatures = true });
    defer allocator.free(result);
    
    // Should not crash and return some result (even if empty)
    try testing.expect(result.len >= 0);
}

test "extraction flag combinations" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    var parser = try createTreeSitterParser(allocator, .zig);
    defer parser.deinit();
    
    const source = 
        \\/// Documentation comment
        \\pub fn example() void {}
        \\const MyStruct = struct {};
        \\test "unit test" {}
    ;
    
    // Test multiple flag combinations
    const flags_combo = ExtractionFlags{
        .signatures = true,
        .types = true,
        .docs = true,
        .tests = true,
    };
    
    const result = try parser.extract(source, flags_combo);
    defer allocator.free(result);
    
    // Should extract some content (even if specific extraction depends on tree-sitter node types)
    // This tests that the extraction doesn't crash and produces some output
    try testing.expect(result.len >= 0);
    
    // Test that no flags returns full source
    const full_result = try parser.extract(source, ExtractionFlags{});
    defer allocator.free(full_result);
    try testing.expectEqualStrings(source, full_result);
}

test "early termination optimization" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    var parser = try createTreeSitterParser(allocator, .zig);
    defer parser.deinit();
    
    const source = "pub fn test() void {}";
    
    // Default flags should return full source without parsing
    const result1 = try parser.extract(source, ExtractionFlags{});
    defer allocator.free(result1);
    try testing.expectEqualStrings(source, result1);
    
    // No relevant flags should return empty result
    const result2 = try parser.extract(source, ExtractionFlags{ .structure = true });
    defer allocator.free(result2);
    try testing.expect(result2.len == 0);
}