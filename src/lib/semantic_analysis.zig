const std = @import("std");
const CodeAnalysis = @import("code_analysis.zig").CodeAnalysis;
const collections = @import("collections.zig");
const io = @import("io.zig");
const errors = @import("errors.zig");
const path_utils = @import("path.zig");

/// Intelligent code analysis and summarization for optimal LLM context generation
pub const SemanticAnalysis = struct {

    /// Represents the semantic role and importance of a file in a codebase
    pub const FileRole = enum {
        entry_point,        // main.zig, index.js - application entry
        core_module,        // Essential functionality, widely imported
        utility_module,     // Helper functions, utilities
        configuration,      // Config files, constants
        test_file,          // Test code
        documentation,      // README, docs
        build_script,       // build.zig, package.json
        data_file,          // JSON, CSV, static data
        generated_code,     // Auto-generated files
        unknown,           // Cannot determine role
        
        pub fn priority(self: FileRole) u8 {
            return switch (self) {
                .entry_point => 10,
                .core_module => 9,
                .configuration => 8,
                .utility_module => 7,
                .build_script => 6,
                .documentation => 5,
                .test_file => 4,
                .data_file => 3,
                .generated_code => 2,
                .unknown => 1,
            };
        }
    };

    /// File relevance scoring for intelligent context selection
    pub const FileRelevance = struct {
        file_path: []const u8,
        role: FileRole,
        importance_score: f32,      // 0.0 to 1.0 based on multiple factors
        complexity_score: f32,      // 0.0 to 1.0 code complexity
        dependency_score: f32,      // 0.0 to 1.0 how much other code depends on this
        recency_score: f32,         // 0.0 to 1.0 how recently modified
        size_factor: f32,           // 0.0 to 1.0 size appropriateness for context
        
        pub fn totalScore(self: FileRelevance) f32 {
            const role_weight: f32 = 0.3;
            const importance_weight: f32 = 0.25;
            const dependency_weight: f32 = 0.2;
            const recency_weight: f32 = 0.15;
            const size_weight: f32 = 0.1;
            
            const role_score = @as(f32, @floatFromInt(self.role.priority())) / 10.0;
            
            return role_score * role_weight +
                   self.importance_score * importance_weight +
                   self.dependency_score * dependency_weight +
                   self.recency_score * recency_weight +
                   self.size_factor * size_weight;
        }
        
        pub fn lessThan(context: void, a: FileRelevance, b: FileRelevance) bool {
            _ = context;
            return a.totalScore() > b.totalScore(); // Higher scores first
        }
    };

    /// Intelligent code summarizer for LLM context optimization
    pub const CodeSummarizer = struct {
        allocator: std.mem.Allocator,
        call_graph: CodeAnalysis.CallGraphBuilder,
        dependency_analyzer: CodeAnalysis.DependencyAnalyzer,
        
        pub fn init(allocator: std.mem.Allocator) CodeSummarizer {
            return .{
                .allocator = allocator,
                .call_graph = CodeAnalysis.CallGraphBuilder.init(allocator),
                .dependency_analyzer = CodeAnalysis.DependencyAnalyzer.init(allocator),
            };
        }
        
        pub fn deinit(self: *CodeSummarizer) void {
            self.call_graph.deinit();
            self.dependency_analyzer.deinit();
        }
        
        /// Analyze a codebase and determine file roles and importance
        pub fn analyzeCodebase(self: *CodeSummarizer, file_paths: []const []const u8) ![]FileRelevance {
            var relevance_scores = std.ArrayList(FileRelevance).init(self.allocator);
            defer relevance_scores.deinit();
            
            // First pass: Analyze all files to build dependency graph
            for (file_paths) |file_path| {
                try self.call_graph.analyzeFile(file_path);
                try self.dependency_analyzer.analyzeFile(file_path);
            }
            
            // Second pass: Calculate relevance scores
            for (file_paths) |file_path| {
                const relevance = try self.calculateFileRelevance(file_path, file_paths);
                try relevance_scores.append(relevance);
            }
            
            const scores = try relevance_scores.toOwnedSlice();
            
            // Sort by relevance score (highest first)
            std.sort.insertion(FileRelevance, scores, {}, FileRelevance.lessThan);
            
            return scores;
        }
        
        /// Calculate comprehensive relevance score for a file
        fn calculateFileRelevance(self: *CodeSummarizer, file_path: []const u8, all_files: []const []const u8) !FileRelevance {
            const role = self.determineFileRole(file_path);
            const importance = try self.calculateImportanceScore(file_path);
            const complexity = try self.calculateComplexityScore(file_path);
            const dependency = try self.calculateDependencyScore(file_path, all_files);
            const recency = try self.calculateRecencyScore(file_path);
            const size = try self.calculateSizeFactor(file_path);
            
            return FileRelevance{
                .file_path = try self.allocator.dupe(u8, file_path),
                .role = role,
                .importance_score = importance,
                .complexity_score = complexity,
                .dependency_score = dependency,
                .recency_score = recency,
                .size_factor = size,
            };
        }
        
        /// Determine the semantic role of a file based on path and content patterns
        fn determineFileRole(self: *CodeSummarizer, file_path: []const u8) FileRole {
            _ = self;
            
            const basename = path_utils.basename(file_path);
            const dirname = path_utils.dirname(file_path);
            
            // Entry points
            if (std.mem.eql(u8, basename, "main.zig") or
                std.mem.eql(u8, basename, "index.js") or
                std.mem.eql(u8, basename, "index.ts") or
                std.mem.eql(u8, basename, "app.js") or
                std.mem.eql(u8, basename, "main.js")) {
                return .entry_point;
            }
            
            // Build scripts
            if (std.mem.eql(u8, basename, "build.zig") or
                std.mem.eql(u8, basename, "package.json") or
                std.mem.eql(u8, basename, "Makefile") or
                std.mem.eql(u8, basename, "CMakeLists.txt")) {
                return .build_script;
            }
            
            // Configuration files
            if (std.mem.endsWith(u8, basename, ".zon") or
                std.mem.endsWith(u8, basename, ".json") or
                std.mem.endsWith(u8, basename, ".toml") or
                std.mem.endsWith(u8, basename, ".yaml") or
                std.mem.endsWith(u8, basename, ".yml") or
                std.mem.eql(u8, basename, "config.js") or
                std.mem.eql(u8, basename, "settings.js")) {
                return .configuration;
            }
            
            // Documentation
            if (std.mem.startsWith(u8, basename, "README") or
                std.mem.startsWith(u8, basename, "CHANGELOG") or
                std.mem.endsWith(u8, basename, ".md") or
                std.mem.indexOf(u8, dirname, "docs") != null or
                std.mem.indexOf(u8, dirname, "documentation") != null) {
                return .documentation;
            }
            
            // Test files
            if (std.mem.indexOf(u8, basename, "test") != null or
                std.mem.indexOf(u8, dirname, "test") != null or
                std.mem.indexOf(u8, dirname, "tests") != null or
                std.mem.endsWith(u8, basename, "_test.zig") or
                std.mem.endsWith(u8, basename, ".test.js") or
                std.mem.endsWith(u8, basename, ".spec.js")) {
                return .test_file;
            }
            
            // Data files
            if (std.mem.endsWith(u8, basename, ".csv") or
                std.mem.endsWith(u8, basename, ".xml") or
                std.mem.indexOf(u8, dirname, "data") != null or
                std.mem.indexOf(u8, dirname, "assets") != null) {
                return .data_file;
            }
            
            // Generated code indicators
            if (std.mem.indexOf(u8, basename, "generated") != null or
                std.mem.indexOf(u8, dirname, "generated") != null or
                std.mem.indexOf(u8, dirname, "build") != null or
                std.mem.indexOf(u8, dirname, "dist") != null) {
                return .generated_code;
            }
            
            // Core modules (in src/ or lib/ directories, not test or utility)
            if (std.mem.indexOf(u8, dirname, "src") != null or
                std.mem.indexOf(u8, dirname, "lib") != null) {
                if (std.mem.indexOf(u8, dirname, "util") != null or
                    std.mem.indexOf(u8, dirname, "helper") != null) {
                    return .utility_module;
                } else {
                    return .core_module;
                }
            }
            
            // Default classification
            if (std.mem.indexOf(u8, basename, "util") != null or
                std.mem.indexOf(u8, basename, "helper") != null) {
                return .utility_module;
            }
            
            return .unknown;
        }
        
        /// Calculate importance based on function count, complexity, etc.
        fn calculateImportanceScore(self: *CodeSummarizer, file_path: []const u8) !f32 {
            const content = self.file_reader.readToStringOptional(file_path, 1024 * 1024) catch {
                return 0.0;
            };
            
            if (content) |file_content| {
                defer self.allocator.free(file_content);
                
                const metrics = try CodeAnalysis.MetricsCalculator.calculateMetrics(self.allocator, file_path, file_content);
                
                // Normalize metrics to 0.0-1.0 scale
                const loc_factor = std.math.min(1.0, @as(f32, @floatFromInt(metrics.effectiveLinesOfCode())) / 500.0);
                const function_factor = std.math.min(1.0, @as(f32, @floatFromInt(metrics.function_count)) / 20.0);
                const complexity_factor = std.math.min(1.0, @as(f32, @floatFromInt(metrics.cyclomatic_complexity)) / 50.0);
                
                return (loc_factor + function_factor + complexity_factor) / 3.0;
            }
            
            return 0.0;
        }
        
        /// Calculate complexity score (simpler = better for LLM context)
        fn calculateComplexityScore(self: *CodeSummarizer, file_path: []const u8) !f32 {
            const content = self.file_reader.readToStringOptional(file_path, 1024 * 1024) catch {
                return 0.5; // Default middle score
            };
            
            if (content) |file_content| {
                defer self.allocator.free(file_content);
                
                const metrics = try CodeAnalysis.MetricsCalculator.calculateMetrics(self.allocator, file_path, file_content);
                
                // Inverse complexity - simpler files score higher
                const complexity_ratio = @as(f32, @floatFromInt(metrics.cyclomatic_complexity)) / @as(f32, @floatFromInt(std.math.max(1, metrics.function_count)));
                return std.math.max(0.0, 1.0 - std.math.min(1.0, complexity_ratio / 10.0));
            }
            
            return 0.5;
        }
        
        /// Calculate dependency score based on how many files depend on this one
        fn calculateDependencyScore(self: *CodeSummarizer, file_path: []const u8, all_files: []const []const u8) !f32 {
            const dependents = try self.dependency_analyzer.getDependents(file_path);
            defer self.allocator.free(dependents);
            
            if (all_files.len == 0) return 0.0;
            
            const dependency_ratio = @as(f32, @floatFromInt(dependents.len)) / @as(f32, @floatFromInt(all_files.len));
            return std.math.min(1.0, dependency_ratio * 2.0); // Scale up dependency importance
        }
        
        /// Calculate recency score based on file modification time
        fn calculateRecencyScore(self: *CodeSummarizer, file_path: []const u8) !f32 {
            _ = self;
            
            const mod_time = io.FileHelpers.getModTime(file_path) catch {
                return 0.3; // Default score for files we can't stat
            };
            
            if (mod_time) |mtime| {
                const now = std.time.timestamp();
                const age_days = @as(f32, @floatFromInt(now - mtime)) / (24.0 * 60.0 * 60.0);
                
                // Files modified in last 7 days get highest score
                if (age_days <= 7.0) return 1.0;
                if (age_days <= 30.0) return 0.7;
                if (age_days <= 90.0) return 0.5;
                return 0.3;
            }
            
            return 0.3;
        }
        
        /// Calculate size factor (medium-sized files preferred for context)
        fn calculateSizeFactor(self: *CodeSummarizer, file_path: []const u8) !f32 {
            const content = self.file_reader.readToStringOptional(file_path, 10 * 1024 * 1024) catch {
                return 0.1; // Penalize unreadable files
            };
            
            if (content) |file_content| {
                defer self.allocator.free(file_content);
                
                const size = file_content.len;
                
                // Optimal size range: 100-2000 characters gets score of 1.0
                if (size >= 100 and size <= 2000) return 1.0;
                
                // Small files (under 100 chars) - might be too trivial
                if (size < 100) return 0.3;
                
                // Large files get progressively lower scores
                if (size <= 5000) return 0.8;
                if (size <= 10000) return 0.6;
                if (size <= 50000) return 0.4;
                return 0.2; // Very large files are hard to process
            }
            
            return 0.1;
        }
        
        /// Generate intelligent summary for LLM context
        pub fn generateCodebaseSummary(
            self: *CodeSummarizer,
            relevance_scores: []const FileRelevance,
            max_files: u32,
            max_chars: u32
        ) ![]u8 {
            var summary = std.ArrayList(u8).init(self.allocator);
            defer summary.deinit();
            
            try summary.appendSlice("# Codebase Summary\n\n");
            
            // Add overview statistics
            try summary.appendSlice("## Overview\n");
            try summary.appendSlice(try std.fmt.allocPrint(self.allocator, "Total files analyzed: {d}\n", .{relevance_scores.len}));
            
            // Count files by role
            var role_counts = std.EnumArray(FileRole, u32).initFill(0);
            for (relevance_scores) |score| {
                role_counts.set(score.role, role_counts.get(score.role) + 1);
            }
            
            try summary.appendSlice("File types:\n");
            inline for (std.meta.fields(FileRole)) |field| {
                const role = @as(FileRole, @enumFromInt(field.value));
                const count = role_counts.get(role);
                if (count > 0) {
                    try summary.appendSlice(try std.fmt.allocPrint(self.allocator, "- {s}: {d}\n", .{ @tagName(role), count }));
                }
            }
            
            try summary.appendSlice("\n## Most Relevant Files\n\n");
            
            // Add top files with summaries
            var chars_used: u32 = 0;
            var files_included: u32 = 0;
            
            for (relevance_scores[0..std.math.min(relevance_scores.len, max_files)]) |score| {
                if (chars_used >= max_chars or files_included >= max_files) break;
                
                const file_summary = try self.generateFileSummary(score);
                defer self.allocator.free(file_summary);
                
                if (chars_used + file_summary.len > max_chars) break;
                
                try summary.appendSlice(file_summary);
                chars_used += @as(u32, @intCast(file_summary.len));
                files_included += 1;
            }
            
            return summary.toOwnedSlice();
        }
        
        /// Generate summary for individual file
        fn generateFileSummary(self: *CodeSummarizer, relevance: FileRelevance) ![]u8 {
            var summary = std.ArrayList(u8).init(self.allocator);
            defer summary.deinit();
            
            // File header
            try summary.appendSlice(try std.fmt.allocPrint(
                self.allocator, 
                "### {s} (Score: {d:.2})\n",
                .{ path_utils.basename(relevance.file_path), relevance.totalScore() }
            ));
            
            // Role and basic info
            try summary.appendSlice(try std.fmt.allocPrint(
                self.allocator,
                "**Role**: {s} | **Path**: `{s}`\n\n",
                .{ @tagName(relevance.role), relevance.file_path }
            ));
            
            // Try to add key functions/types from the file
            const content = self.file_reader.readToStringOptional(relevance.file_path, 5000) catch {
                try summary.appendSlice("*Unable to read file content*\n\n");
                return summary.toOwnedSlice();
            };
            
            if (content) |file_content| {
                defer self.allocator.free(file_content);
                
                const key_elements = try self.extractKeyElements(file_content, 3);
                defer self.allocator.free(key_elements);
                
                if (key_elements.len > 0) {
                    try summary.appendSlice("**Key Elements**:\n");
                    for (key_elements) |element| {
                        defer self.allocator.free(element);
                        try summary.appendSlice(try std.fmt.allocPrint(self.allocator, "- {s}\n", .{element}));
                    }
                    try summary.appendSlice("\n");
                }
            }
            
            return summary.toOwnedSlice();
        }
        
        /// Extract key functions, types, or classes from file content
        fn extractKeyElements(self: *CodeSummarizer, content: []const u8, max_elements: u32) ![][]const u8 {
            var elements = std.ArrayList([]const u8).init(self.allocator);
            defer elements.deinit();
            
            var lines = std.mem.splitScalar(u8, content, '\n');
            var count: u32 = 0;
            
            while (lines.next()) |line| {
                if (count >= max_elements) break;
                
                const trimmed = std.mem.trim(u8, line, " \t");
                
                // Look for public functions, structures, classes
                if (std.mem.startsWith(u8, trimmed, "pub fn ") or
                    std.mem.startsWith(u8, trimmed, "pub const ") or
                    std.mem.startsWith(u8, trimmed, "pub struct ") or
                    std.mem.startsWith(u8, trimmed, "pub enum ") or
                    std.mem.startsWith(u8, trimmed, "export function ") or
                    std.mem.startsWith(u8, trimmed, "class ") or
                    std.mem.startsWith(u8, trimmed, "interface ")) {
                    
                    // Extract just the declaration line, limit length
                    const element = if (trimmed.len > 80) 
                        try std.fmt.allocPrint(self.allocator, "{s}...", .{trimmed[0..77]})
                    else 
                        try self.allocator.dupe(u8, trimmed);
                    
                    try elements.append(element);
                    count += 1;
                }
            }
            
            return elements.toOwnedSlice();
        }
    };

    /// Context-aware file selector for LLM prompts
    pub const ContextSelector = struct {
        /// Select optimal files for LLM context based on query intent
        pub fn selectFilesForQuery(
            allocator: std.mem.Allocator,
            relevance_scores: []const FileRelevance,
            query_intent: QueryIntent,
            token_budget: u32
        ) ![][]const u8 {
            var selected = std.ArrayList([]const u8).init(allocator);
            defer selected.deinit();
            
            var used_tokens: u32 = 0;
            
            // Apply query-specific filtering and weighting
            for (relevance_scores) |score| {
                if (!isRelevantForQuery(score, query_intent)) continue;
                
                const estimated_tokens = estimateTokens(score.file_path);
                if (used_tokens + estimated_tokens > token_budget) break;
                
                try selected.append(try allocator.dupe(u8, score.file_path));
                used_tokens += estimated_tokens;
            }
            
            return selected.toOwnedSlice();
        }
        
        pub const QueryIntent = enum {
            debugging,          // Focus on error handling, test files
            feature_addition,   // Core modules, related functionality
            refactoring,        // All related code, dependencies
            documentation,      // Public APIs, examples
            performance,        // Core algorithms, bottlenecks
            testing,           // Test files, test utilities
        };
        
        fn isRelevantForQuery(score: FileRelevance, intent: QueryIntent) bool {
            return switch (intent) {
                .debugging => score.role == .core_module or score.role == .test_file or score.role == .entry_point,
                .feature_addition => score.role == .core_module or score.role == .utility_module,
                .refactoring => score.role != .documentation and score.role != .data_file,
                .documentation => score.role == .core_module or score.role == .entry_point,
                .performance => score.role == .core_module or score.role == .entry_point,
                .testing => score.role == .test_file or score.role == .core_module,
            };
        }
        
        fn estimateTokens(file_path: []const u8) u32 {
            _ = file_path;
            // Rough estimation: 1 token per 4 characters for code
            // This would need file size info in practice
            return 250; // Conservative estimate per file
        }
    };
};

test "FileRole priority ordering" {
    const testing = std.testing;
    
    try testing.expect(SemanticAnalysis.FileRole.entry_point.priority() > SemanticAnalysis.FileRole.utility_module.priority());
    try testing.expect(SemanticAnalysis.FileRole.core_module.priority() > SemanticAnalysis.FileRole.test_file.priority());
}

test "FileRelevance total score calculation" {
    const testing = std.testing;
    
    const relevance = SemanticAnalysis.FileRelevance{
        .file_path = "test.zig",
        .role = .core_module,
        .importance_score = 0.8,
        .complexity_score = 0.7,
        .dependency_score = 0.9,
        .recency_score = 1.0,
        .size_factor = 0.9,
    };
    
    const score = relevance.totalScore();
    try testing.expect(score > 0.0 and score <= 1.0);
}

test "CodeSummarizer file role determination" {
    const testing = std.testing;
    
    var summarizer = SemanticAnalysis.CodeSummarizer.init(testing.allocator);
    defer summarizer.deinit();
    
    try testing.expect(summarizer.determineFileRole("src/main.zig") == .entry_point);
    try testing.expect(summarizer.determineFileRole("build.zig") == .build_script);
    try testing.expect(summarizer.determineFileRole("src/test/foo_test.zig") == .test_file);
    try testing.expect(summarizer.determineFileRole("README.md") == .documentation);
    try testing.expect(summarizer.determineFileRole("config.zig") == .configuration);
}