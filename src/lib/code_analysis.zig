const std = @import("std");
const AstNode = @import("ast.zig").AstNode;
const ExtractionFlags = @import("parser.zig").ExtractionFlags;
const collection_helpers = @import("collection_helpers.zig");
const file_helpers = @import("file_helpers.zig");
const error_helpers = @import("error_helpers.zig");

/// Advanced code analysis features for intelligent code understanding and LLM context generation
pub const CodeAnalysis = struct {

    /// Represents a function or method call relationship
    pub const CallRelationship = struct {
        caller: []const u8,        // Function making the call
        callee: []const u8,        // Function being called
        file_path: []const u8,     // File where call occurs
        line_number: u32,          // Line number of call
        call_type: CallType,       // Type of call relationship
        
        pub const CallType = enum {
            direct_call,           // foo()
            method_call,           // obj.foo()
            constructor_call,      // new Foo()
            async_call,            // await foo()
            callback,              // function passed as parameter
            import_usage,          // using imported function
        };
    };

    /// Represents import/export relationships between files
    pub const DependencyRelationship = struct {
        importer: []const u8,      // File doing the import
        imported: []const u8,      // File/module being imported
        import_type: ImportType,   // How it's imported
        symbols: [][]const u8,     // Specific symbols imported
        line_number: u32,          // Line of import statement
        
        pub const ImportType = enum {
            module_import,         // import * from 'module'
            named_import,          // import { foo, bar } from 'module'
            default_import,        // import foo from 'module'
            dynamic_import,        // import('module')
            include_directive,     // #include "file.h"
            zig_import,           // @import("module")
        };
    };

    /// Represents a symbol (function, variable, type) and its usage
    pub const SymbolUsage = struct {
        symbol_name: []const u8,
        symbol_type: SymbolType,
        definition_file: []const u8,
        definition_line: u32,
        usages: []Usage,
        
        pub const SymbolType = enum {
            function,
            variable,
            constant,
            type_definition,
            method,
            field,
            parameter,
        };
        
        pub const Usage = struct {
            file_path: []const u8,
            line_number: u32,
            usage_type: UsageType,
            context: []const u8,  // Surrounding code for context
            
            pub const UsageType = enum {
                definition,
                call,
                assignment,
                read_access,
                type_annotation,
                import,
            };
        };
    };

    /// Call graph builder for analyzing function relationships
    pub const CallGraphBuilder = struct {
        allocator: std.mem.Allocator,
        relationships: collection_helpers.CollectionHelpers.ManagedArrayList(CallRelationship),
        file_reader: file_helpers.FileHelpers.SafeFileReader,
        
        pub fn init(allocator: std.mem.Allocator) CallGraphBuilder {
            return .{
                .allocator = allocator,
                .relationships = collection_helpers.CollectionHelpers.ManagedArrayList(CallRelationship).init(allocator),
                .file_reader = file_helpers.FileHelpers.SafeFileReader.init(allocator),
            };
        }
        
        pub fn deinit(self: *CallGraphBuilder) void {
            // Free all string allocations in relationships
            for (self.relationships.items()) |rel| {
                self.allocator.free(rel.caller);
                self.allocator.free(rel.callee);
                self.allocator.free(rel.file_path);
            }
            self.relationships.deinit();
        }
        
        /// Analyze a file and extract function call relationships
        pub fn analyzeFile(self: *CallGraphBuilder, file_path: []const u8) !void {
            const content = self.file_reader.readToStringOptional(file_path, 10 * 1024 * 1024) catch |err| {
                error_helpers.ErrorHelpers.handleFsError(err, "reading file for call analysis", file_path);
                return;
            };
            
            if (content) |file_content| {
                defer self.allocator.free(file_content);
                try self.extractCallRelationships(file_path, file_content);
            }
        }
        
        /// Extract function calls from source code using pattern matching
        fn extractCallRelationships(self: *CallGraphBuilder, file_path: []const u8, content: []const u8) !void {
            var lines = std.mem.split(u8, content, "\n");
            var line_number: u32 = 1;
            var current_function: ?[]const u8 = null;
            
            while (lines.next()) |line| {
                defer line_number += 1;
                
                // Detect function definitions to track caller context
                if (self.detectFunction(line)) |func_name| {
                    if (current_function) |old_func| {
                        self.allocator.free(old_func);
                    }
                    current_function = try self.allocator.dupe(u8, func_name);
                }
                
                // Detect function calls within current function
                if (current_function) |caller| {
                    var call_iter = self.findFunctionCalls(line);
                    while (call_iter.next()) |callee| {
                        try self.addCallRelationship(
                            caller,
                            callee,
                            file_path,
                            line_number,
                            self.classifyCallType(line, callee)
                        );
                    }
                }
            }
            
            if (current_function) |func| {
                self.allocator.free(func);
            }
        }
        
        /// Detect function definition patterns across languages
        fn detectFunction(self: *CallGraphBuilder, line: []const u8) ?[]const u8 {
            _ = self;
            const trimmed = std.mem.trim(u8, line, " \t");
            
            // Zig functions
            if (std.mem.indexOf(u8, trimmed, "pub fn ") != null or std.mem.indexOf(u8, trimmed, "fn ") != null) {
                const start = std.mem.indexOf(u8, trimmed, "fn ").? + 3;
                const end = std.mem.indexOf(u8, trimmed[start..], "(");
                if (end != null) {
                    return std.mem.trim(u8, trimmed[start..start + end.?], " \t");
                }
            }
            
            // TypeScript/JavaScript functions
            if (std.mem.indexOf(u8, trimmed, "function ") != null) {
                const start = std.mem.indexOf(u8, trimmed, "function ").? + 9;
                const end = std.mem.indexOf(u8, trimmed[start..], "(");
                if (end != null) {
                    return std.mem.trim(u8, trimmed[start..start + end.?], " \t");
                }
            }
            
            // C/C++ functions
            if (std.mem.endsWith(u8, trimmed, "{") and std.mem.indexOf(u8, trimmed, "(") != null) {
                // Simple heuristic for C function definitions
                const paren_pos = std.mem.indexOf(u8, trimmed, "(").?;
                var name_end = paren_pos;
                while (name_end > 0 and !std.ascii.isWhitespace(trimmed[name_end - 1])) {
                    name_end -= 1;
                }
                var name_start = name_end;
                while (name_start > 0 and !std.ascii.isWhitespace(trimmed[name_start - 1])) {
                    name_start -= 1;
                }
                if (name_start < name_end) {
                    return trimmed[name_start..name_end];
                }
            }
            
            return null;
        }
        
        /// Iterator for finding function calls in a line
        fn findFunctionCalls(self: *CallGraphBuilder, line: []const u8) CallIterator {
            _ = self;
            return CallIterator{ .line = line, .pos = 0 };
        }
        
        const CallIterator = struct {
            line: []const u8,
            pos: usize,
            
            fn next(self: *CallIterator) ?[]const u8 {
                while (self.pos < self.line.len) {
                    // Look for pattern: identifier(
                    const start_pos = self.pos;
                    
                    // Skip whitespace
                    while (self.pos < self.line.len and std.ascii.isWhitespace(self.line[self.pos])) {
                        self.pos += 1;
                    }
                    if (self.pos >= self.line.len) break;
                    
                    // Find identifier
                    const id_start = self.pos;
                    while (self.pos < self.line.len and (std.ascii.isAlphabetic(self.line[self.pos]) or 
                           std.ascii.isDigit(self.line[self.pos]) or self.line[self.pos] == '_')) {
                        self.pos += 1;
                    }
                    
                    // Check for opening parenthesis
                    if (self.pos < self.line.len and self.line[self.pos] == '(' and self.pos > id_start) {
                        const identifier = self.line[id_start..self.pos];
                        self.pos += 1; // Move past '('
                        
                        // Skip common control structures
                        if (!std.mem.eql(u8, identifier, "if") and 
                            !std.mem.eql(u8, identifier, "while") and
                            !std.mem.eql(u8, identifier, "for") and
                            !std.mem.eql(u8, identifier, "switch")) {
                            return identifier;
                        }
                    } else if (start_pos == self.pos) {
                        // No progress made, advance by one
                        self.pos += 1;
                    }
                }
                return null;
            }
        };
        
        /// Classify the type of function call
        fn classifyCallType(self: *CallGraphBuilder, line: []const u8, callee: []const u8) CallRelationship.CallType {
            _ = self;
            _ = callee;
            
            if (std.mem.indexOf(u8, line, "await ") != null) {
                return .async_call;
            } else if (std.mem.indexOf(u8, line, "new ") != null) {
                return .constructor_call;
            } else if (std.mem.indexOf(u8, line, ".") != null) {
                return .method_call;
            } else {
                return .direct_call;
            }
        }
        
        /// Add a call relationship to the graph
        fn addCallRelationship(
            self: *CallGraphBuilder,
            caller: []const u8,
            callee: []const u8,
            file_path: []const u8,
            line_number: u32,
            call_type: CallRelationship.CallType
        ) !void {
            const relationship = CallRelationship{
                .caller = try self.allocator.dupe(u8, caller),
                .callee = try self.allocator.dupe(u8, callee),
                .file_path = try self.allocator.dupe(u8, file_path),
                .line_number = line_number,
                .call_type = call_type,
            };
            try self.relationships.append(relationship);
        }
        
        /// Get all functions called by a specific function
        pub fn getCalledBy(self: *const CallGraphBuilder, function_name: []const u8) ![]CallRelationship {
            var results = collection_helpers.CollectionHelpers.ManagedArrayList(CallRelationship).init(self.allocator);
            defer results.deinit();
            
            for (self.relationships.items()) |rel| {
                if (std.mem.eql(u8, rel.caller, function_name)) {
                    try results.append(rel);
                }
            }
            
            return results.toOwnedSlice();
        }
        
        /// Get all functions that call a specific function
        pub fn getCalling(self: *const CallGraphBuilder, function_name: []const u8) ![]CallRelationship {
            var results = collection_helpers.CollectionHelpers.ManagedArrayList(CallRelationship).init(self.allocator);
            defer results.deinit();
            
            for (self.relationships.items()) |rel| {
                if (std.mem.eql(u8, rel.callee, function_name)) {
                    try results.append(rel);
                }
            }
            
            return results.toOwnedSlice();
        }
        
        /// Export call graph as DOT format for visualization
        pub fn exportDot(self: *const CallGraphBuilder, allocator: std.mem.Allocator) ![]u8 {
            var result = collection_helpers.CollectionHelpers.ManagedArrayList(u8).init(allocator);
            defer result.deinit();
            
            try result.appendSlice("digraph CallGraph {\n");
            try result.appendSlice("  rankdir=TB;\n");
            try result.appendSlice("  node [shape=box];\n\n");
            
            for (self.relationships.items()) |rel| {
                try result.appendSlice("  \"");
                try result.appendSlice(rel.caller);
                try result.appendSlice("\" -> \"");
                try result.appendSlice(rel.callee);
                try result.appendSlice("\"");
                
                // Add call type as edge label
                try result.appendSlice(" [label=\"");
                switch (rel.call_type) {
                    .direct_call => try result.appendSlice("call"),
                    .method_call => try result.appendSlice("method"),
                    .constructor_call => try result.appendSlice("new"),
                    .async_call => try result.appendSlice("await"),
                    .callback => try result.appendSlice("callback"),
                    .import_usage => try result.appendSlice("import"),
                }
                try result.appendSlice("\"];\n");
            }
            
            try result.appendSlice("}\n");
            return result.toOwnedSlice();
        }
    };

    /// Dependency analyzer for import/export relationships
    pub const DependencyAnalyzer = struct {
        allocator: std.mem.Allocator,
        dependencies: collection_helpers.CollectionHelpers.ManagedArrayList(DependencyRelationship),
        file_reader: file_helpers.FileHelpers.SafeFileReader,
        
        pub fn init(allocator: std.mem.Allocator) DependencyAnalyzer {
            return .{
                .allocator = allocator,
                .dependencies = collection_helpers.CollectionHelpers.ManagedArrayList(DependencyRelationship).init(allocator),
                .file_reader = file_helpers.FileHelpers.SafeFileReader.init(allocator),
            };
        }
        
        pub fn deinit(self: *DependencyAnalyzer) void {
            for (self.dependencies.items()) |dep| {
                self.allocator.free(dep.importer);
                self.allocator.free(dep.imported);
                for (dep.symbols) |symbol| {
                    self.allocator.free(symbol);
                }
                self.allocator.free(dep.symbols);
            }
            self.dependencies.deinit();
        }
        
        /// Analyze imports in a file
        pub fn analyzeFile(self: *DependencyAnalyzer, file_path: []const u8) !void {
            const content = self.file_reader.readToStringOptional(file_path, 10 * 1024 * 1024) catch |err| {
                error_helpers.ErrorHelpers.handleFsError(err, "reading file for dependency analysis", file_path);
                return;
            };
            
            if (content) |file_content| {
                defer self.allocator.free(file_content);
                try self.extractImports(file_path, file_content);
            }
        }
        
        /// Extract import statements from source code
        fn extractImports(self: *DependencyAnalyzer, file_path: []const u8, content: []const u8) !void {
            var lines = std.mem.split(u8, content, "\n");
            var line_number: u32 = 1;
            
            while (lines.next()) |line| {
                defer line_number += 1;
                const trimmed = std.mem.trim(u8, line, " \t");
                
                // Zig imports: @import("module")
                if (std.mem.indexOf(u8, trimmed, "@import(\"") != null) {
                    try self.extractZigImport(file_path, trimmed, line_number);
                }
                // TypeScript/JavaScript imports
                else if (std.mem.startsWith(u8, trimmed, "import ")) {
                    try self.extractJsImport(file_path, trimmed, line_number);
                }
                // C/C++ includes: #include "file.h"
                else if (std.mem.startsWith(u8, trimmed, "#include ")) {
                    try self.extractCInclude(file_path, trimmed, line_number);
                }
            }
        }
        
        fn extractZigImport(self: *DependencyAnalyzer, file_path: []const u8, line: []const u8, line_number: u32) !void {
            const start = std.mem.indexOf(u8, line, "@import(\"").? + 9;
            const end = std.mem.indexOf(u8, line[start..], "\"");
            if (end == null) return;
            
            const module_name = line[start..start + end.?];
            
            const dependency = DependencyRelationship{
                .importer = try self.allocator.dupe(u8, file_path),
                .imported = try self.allocator.dupe(u8, module_name),
                .import_type = .zig_import,
                .symbols = try self.allocator.alloc([]const u8, 0), // Zig imports entire module
                .line_number = line_number,
            };
            
            try self.dependencies.append(dependency);
        }
        
        fn extractJsImport(self: *DependencyAnalyzer, file_path: []const u8, line: []const u8, line_number: u32) !void {
            // Simplified import parsing - would need more sophisticated parsing for full coverage
            if (std.mem.indexOf(u8, line, "from ") != null) {
                const from_pos = std.mem.indexOf(u8, line, "from ").? + 5;
                var module_start = from_pos;
                while (module_start < line.len and line[module_start] != '"' and line[module_start] != '\'') {
                    module_start += 1;
                }
                if (module_start >= line.len) return;
                
                module_start += 1; // Skip quote
                var module_end = module_start;
                while (module_end < line.len and line[module_end] != '"' and line[module_end] != '\'') {
                    module_end += 1;
                }
                if (module_end >= line.len) return;
                
                const module_name = line[module_start..module_end];
                
                const dependency = DependencyRelationship{
                    .importer = try self.allocator.dupe(u8, file_path),
                    .imported = try self.allocator.dupe(u8, module_name),
                    .import_type = .named_import,
                    .symbols = try self.allocator.alloc([]const u8, 0), // TODO: Parse symbols
                    .line_number = line_number,
                };
                
                try self.dependencies.append(dependency);
            }
        }
        
        fn extractCInclude(self: *DependencyAnalyzer, file_path: []const u8, line: []const u8, line_number: u32) !void {
            var start: usize = 0;
            var end: usize = 0;
            var is_system_header = false;
            
            if (std.mem.indexOf(u8, line, "#include \"") != null) {
                start = std.mem.indexOf(u8, line, "#include \"").? + 10;
                end = std.mem.indexOf(u8, line[start..], "\"");
            } else if (std.mem.indexOf(u8, line, "#include <") != null) {
                start = std.mem.indexOf(u8, line, "#include <").? + 10;
                end = std.mem.indexOf(u8, line[start..], ">");
                is_system_header = true;
            }
            
            if (end == null) return;
            
            const header_name = line[start..start + end.?];
            
            const dependency = DependencyRelationship{
                .importer = try self.allocator.dupe(u8, file_path),
                .imported = try self.allocator.dupe(u8, header_name),
                .import_type = .include_directive,
                .symbols = try self.allocator.alloc([]const u8, 0),
                .line_number = line_number,
            };
            
            _ = is_system_header; // TODO: Use this information
            try self.dependencies.append(dependency);
        }
        
        /// Get all files that depend on a specific file
        pub fn getDependents(self: *const DependencyAnalyzer, file_path: []const u8) ![]DependencyRelationship {
            var results = collection_helpers.CollectionHelpers.ManagedArrayList(DependencyRelationship).init(self.allocator);
            defer results.deinit();
            
            for (self.dependencies.items()) |dep| {
                if (std.mem.eql(u8, dep.imported, file_path)) {
                    try results.append(dep);
                }
            }
            
            return results.toOwnedSlice();
        }
        
        /// Get all dependencies of a specific file
        pub fn getDependencies(self: *const DependencyAnalyzer, file_path: []const u8) ![]DependencyRelationship {
            var results = collection_helpers.CollectionHelpers.ManagedArrayList(DependencyRelationship).init(self.allocator);
            defer results.deinit();
            
            for (self.dependencies.items()) |dep| {
                if (std.mem.eql(u8, dep.importer, file_path)) {
                    try results.append(dep);
                }
            }
            
            return results.toOwnedSlice();
        }
    };
    
    /// Code metrics calculator for complexity analysis
    pub const MetricsCalculator = struct {
        pub const CodeMetrics = struct {
            lines_of_code: u32,
            blank_lines: u32,
            comment_lines: u32,
            function_count: u32,
            class_count: u32,
            cyclomatic_complexity: u32,
            nesting_depth: u32,
            
            pub fn effectiveLinesOfCode(self: CodeMetrics) u32 {
                return self.lines_of_code - self.blank_lines - self.comment_lines;
            }
            
            pub fn commentRatio(self: CodeMetrics) f32 {
                if (self.lines_of_code == 0) return 0.0;
                return @as(f32, @floatFromInt(self.comment_lines)) / @as(f32, @floatFromInt(self.lines_of_code));
            }
        };
        
        pub fn calculateMetrics(allocator: std.mem.Allocator, file_path: []const u8, content: []const u8) !CodeMetrics {
            _ = allocator;
            _ = file_path;
            
            var metrics = CodeMetrics{
                .lines_of_code = 0,
                .blank_lines = 0,
                .comment_lines = 0,
                .function_count = 0,
                .class_count = 0,
                .cyclomatic_complexity = 1, // Start at 1 for linear flow
                .nesting_depth = 0,
            };
            
            var lines = std.mem.split(u8, content, "\n");
            while (lines.next()) |line| {
                metrics.lines_of_code += 1;
                
                const trimmed = std.mem.trim(u8, line, " \t");
                if (trimmed.len == 0) {
                    metrics.blank_lines += 1;
                    continue;
                }
                
                // Comment detection
                if (std.mem.startsWith(u8, trimmed, "//") or 
                    std.mem.startsWith(u8, trimmed, "/*") or
                    std.mem.startsWith(u8, trimmed, "*") or
                    std.mem.startsWith(u8, trimmed, "#")) {
                    metrics.comment_lines += 1;
                    continue;
                }
                
                // Function/method counting
                if (std.mem.indexOf(u8, line, "fn ") != null or
                    std.mem.indexOf(u8, line, "function ") != null) {
                    metrics.function_count += 1;
                }
                
                // Class/struct counting
                if (std.mem.indexOf(u8, line, "struct ") != null or
                    std.mem.indexOf(u8, line, "class ") != null) {
                    metrics.class_count += 1;
                }
                
                // Complexity indicators
                const complexity_keywords = [_][]const u8{ "if", "else", "while", "for", "switch", "case", "catch" };
                for (complexity_keywords) |keyword| {
                    if (std.mem.indexOf(u8, line, keyword) != null) {
                        metrics.cyclomatic_complexity += 1;
                    }
                }
                
                // Simple nesting depth approximation
                var depth: u32 = 0;
                for (line) |char| {
                    if (char == '{') depth += 1;
                }
                if (depth > metrics.nesting_depth) {
                    metrics.nesting_depth = depth;
                }
            }
            
            return metrics;
        }
    };
};

test "CallGraphBuilder function detection" {
    const testing = std.testing;
    
    var builder = CodeAnalysis.CallGraphBuilder.init(testing.allocator);
    defer builder.deinit();
    
    // Test Zig function detection
    const zig_func = builder.detectFunction("pub fn testFunction(arg: i32) void {");
    try testing.expect(zig_func != null);
    try testing.expectEqualStrings("testFunction", zig_func.?);
    
    // Test TypeScript function detection
    const ts_func = builder.detectFunction("function myFunction(arg: string) {");
    try testing.expect(ts_func != null);
    try testing.expectEqualStrings("myFunction", ts_func.?);
}

test "CallIterator functionality" {
    const testing = std.testing;
    
    var builder = CodeAnalysis.CallGraphBuilder.init(testing.allocator);
    defer builder.deinit();
    
    var iter = builder.findFunctionCalls("result = foo(bar) + baz(qux);");
    
    const call1 = iter.next();
    try testing.expect(call1 != null);
    try testing.expectEqualStrings("foo", call1.?);
    
    const call2 = iter.next();
    try testing.expect(call2 != null);
    try testing.expectEqualStrings("baz", call2.?);
    
    const call3 = iter.next();
    try testing.expect(call3 == null);
}

test "DependencyAnalyzer Zig import extraction" {
    const testing = std.testing;
    
    var analyzer = CodeAnalysis.DependencyAnalyzer.init(testing.allocator);
    defer analyzer.deinit();
    
    const import_line = "const std = @import(\"std\");";
    try analyzer.extractZigImport("test.zig", import_line, 1);
    
    try testing.expectEqual(@as(usize, 1), analyzer.dependencies.len());
    const dep = analyzer.dependencies.items()[0];
    try testing.expectEqualStrings("test.zig", dep.importer);
    try testing.expectEqualStrings("std", dep.imported);
    try testing.expect(dep.import_type == .zig_import);
}

test "CodeMetrics calculation" {
    const testing = std.testing;
    
    const test_code = 
        \\// This is a comment
        \\pub fn main() void {
        \\    if (true) {
        \\        // Another comment
        \\        std.log.info("Hello");
        \\    }
        \\}
        \\
        \\struct TestStruct {
        \\    field: i32,
        \\}
    ;
    
    const metrics = try CodeAnalysis.MetricsCalculator.calculateMetrics(testing.allocator, "test.zig", test_code);
    
    try testing.expect(metrics.lines_of_code > 0);
    try testing.expect(metrics.comment_lines >= 2);
    try testing.expect(metrics.function_count >= 1);
    try testing.expect(metrics.cyclomatic_complexity >= 2); // Base + if statement
}