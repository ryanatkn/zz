const std = @import("std");
const fence = @import("fence.zig");
const FilesystemInterface = @import("../lib/filesystem/interface.zig").FilesystemInterface;
const path_utils = @import("../lib/core/path.zig");
const Language = @import("../lib/language/detection.zig").Language;
const ExtractionFlags = @import("../lib/language/flags.zig").ExtractionFlags;
const FileTracker = @import("../lib/analysis/incremental.zig").FileTracker;
const CacheSystem = @import("../lib/analysis/cache.zig").CacheSystem;
const AstCacheKey = @import("../lib/analysis/cache.zig").AstCacheKey;
const WorkerPool = @import("../lib/parallel.zig").WorkerPool;
const Task = @import("../lib/parallel.zig").Task;
const TaskPriority = @import("../lib/parallel.zig").TaskPriority;
const errors = @import("../lib/core/errors.zig");

// Import stratified parser
const StratifiedParser = @import("../lib/parser/mod.zig");
const Lexical = StratifiedParser.Lexical;
const Structural = StratifiedParser.Structural;

pub const PromptBuilder = struct {
    allocator: std.mem.Allocator,
    lines: std.ArrayList([]const u8),
    arena: std.heap.ArenaAllocator,
    quiet: bool,
    filesystem: FilesystemInterface,
    extraction_flags: ExtractionFlags,

    // Incremental and caching support
    file_tracker: ?*FileTracker,
    cache_system: ?*CacheSystem,
    worker_pool: ?*WorkerPool,
    enable_parallel: bool,

    const Self = @This();
    const max_file_size = 10 * 1024 * 1024; // 10MB

    pub fn init(allocator: std.mem.Allocator, filesystem: FilesystemInterface, extraction_flags: ExtractionFlags) Self {
        return Self{
            .allocator = allocator,
            .lines = std.ArrayList([]const u8).init(allocator),
            .arena = std.heap.ArenaAllocator.init(allocator),
            .quiet = false,
            .filesystem = filesystem,
            .extraction_flags = extraction_flags,
            .file_tracker = null,
            .cache_system = null,
            .worker_pool = null,
            .enable_parallel = false,
        };
    }

    /// Initialize for testing
    pub fn initForTest(allocator: std.mem.Allocator, filesystem: FilesystemInterface, extraction_flags: ExtractionFlags) !Self {
        return Self{
            .allocator = allocator,
            .lines = std.ArrayList([]const u8).init(allocator),
            .arena = std.heap.ArenaAllocator.init(allocator),
            .quiet = false,
            .filesystem = filesystem,
            .extraction_flags = extraction_flags,
            .file_tracker = null,
            .cache_system = null,
            .worker_pool = null,
            .enable_parallel = false,
        };
    }

    pub fn initQuiet(allocator: std.mem.Allocator, filesystem: FilesystemInterface, extraction_flags: ExtractionFlags) Self {
        return Self{
            .allocator = allocator,
            .lines = std.ArrayList([]const u8).init(allocator),
            .arena = std.heap.ArenaAllocator.init(allocator),
            .quiet = true,
            .filesystem = filesystem,
            .extraction_flags = extraction_flags,
            .file_tracker = null,
            .cache_system = null,
            .worker_pool = null,
            .enable_parallel = false,
        };
    }

    /// Initialize with incremental support
    pub fn initWithIncremental(allocator: std.mem.Allocator, filesystem: FilesystemInterface, extraction_flags: ExtractionFlags, file_tracker: *FileTracker, cache_system: *CacheSystem) Self {
        return Self{
            .allocator = allocator,
            .lines = std.ArrayList([]const u8).init(allocator),
            .arena = std.heap.ArenaAllocator.init(allocator),
            .quiet = false,
            .filesystem = filesystem,
            .extraction_flags = extraction_flags,
            .file_tracker = file_tracker,
            .cache_system = cache_system,
            .worker_pool = null,
            .enable_parallel = false,
        };
    }

    /// Initialize with parallel support
    pub fn initWithParallel(allocator: std.mem.Allocator, filesystem: FilesystemInterface, extraction_flags: ExtractionFlags, file_tracker: ?*FileTracker, cache_system: ?*CacheSystem, worker_pool: *WorkerPool) Self {
        return Self{
            .allocator = allocator,
            .lines = std.ArrayList([]const u8).init(allocator),
            .arena = std.heap.ArenaAllocator.init(allocator),
            .quiet = false,
            .filesystem = filesystem,
            .extraction_flags = extraction_flags,
            .file_tracker = file_tracker,
            .cache_system = cache_system,
            .worker_pool = worker_pool,
            .enable_parallel = true,
        };
    }

    pub fn deinit(self: *Self) void {
        self.lines.deinit();
        self.arena.deinit();
    }

    pub fn addText(self: *Self, text: []const u8) !void {
        const text_copy = try self.arena.allocator().dupe(u8, text);
        try self.lines.append(text_copy);
        try self.lines.append("");
    }

    /// Extract content using stratified parser
    fn extractContent(self: *Self, language: Language, content: []const u8, file_path: []const u8) ![]const u8 {
        return self.extractWithStratifiedParser(language, content, file_path);
    }

    /// Extract content using the stratified parser
    fn extractWithStratifiedParser(self: *Self, language: Language, content: []const u8, file_path: []const u8) ![]const u8 {
        // Initialize the stratified parser layers
        const lexical_config = Lexical.LexerConfig{
            .language = mapLanguageToLexical(language),
            .buffer_size = @min(content.len * 2, 8192),
            .track_brackets = true,
        };

        const structural_config = Structural.StructuralConfig{
            .language = mapLanguageToStructural(language),
            .performance_threshold_ns = 1_000_000, // 1ms target
            .include_folding = false,
        };

        // Layer 0: Lexical analysis (<0.1ms target)
        const lexical_start = std.time.nanoTimestamp();
        var lexer = try Lexical.StreamingLexer.init(self.allocator, lexical_config);
        defer lexer.deinit();

        const full_span = StratifiedParser.Span.init(0, content.len);
        const tokens = try lexer.tokenizeRange(content, full_span);
        defer self.allocator.free(tokens);
        const lexical_time = std.time.nanoTimestamp() - lexical_start;

        // Layer 1: Structural analysis (<1ms target)
        const structural_start = std.time.nanoTimestamp();
        var structural_parser = try Structural.StructuralParser.init(self.allocator, structural_config);
        defer structural_parser.deinit();

        const parse_result = try structural_parser.parse(tokens);
        defer {
            self.allocator.free(parse_result.boundaries);
            self.allocator.free(parse_result.error_regions);
        }
        const structural_time = std.time.nanoTimestamp() - structural_start;

        // Performance reporting for stratified parser
        if (!self.quiet) {
            const stderr = std.io.getStdErr().writer();
            try stderr.print("🔹 Stratified Parser Performance for {s}:\n", .{file_path});
            try stderr.print("   Layer 0 (Lexical):   {d:.1}μs (tokens: {})\n", .{ @as(f64, @floatFromInt(lexical_time)) / 1000.0, tokens.len });
            try stderr.print("   Layer 1 (Structural): {d:.1}μs (boundaries: {})\n", .{ @as(f64, @floatFromInt(structural_time)) / 1000.0, parse_result.boundaries.len });

            // Check performance targets
            const lexical_target_met = lexical_time < 100_000; // 0.1ms
            const structural_target_met = structural_time < 1_000_000; // 1ms

            try stderr.print("🎯 Performance Targets:\n", .{});
            try stderr.print("   Lexical <0.1ms:    {s}\n", .{if (lexical_target_met) "✅ PASS" else "❌ FAIL"});
            try stderr.print("   Structural <1ms:   {s}\n", .{if (structural_target_met) "✅ PASS" else "❌ FAIL"});
        }

        // For now, return the original content since we're focused on parsing validation
        // TODO: Implement fact-to-content generation for actual extraction
        // The stratified parser excels at structure analysis, not content extraction for prompts
        return self.allocator.dupe(u8, content);
    }

    /// Map Language enum to lexical layer language
    fn mapLanguageToLexical(language: Language) Lexical.Language {
        return switch (language) {
            .zig => .zig,
            .typescript => .typescript,
            .json => .json,
            .css => .css,
            .html => .html,
            .svelte, .zon, .unknown => .generic,
        };
    }

    /// Map Language enum to structural layer language
    fn mapLanguageToStructural(language: Language) Structural.Language {
        return switch (language) {
            .zig => .zig,
            .typescript => .typescript,
            .json => .json,
            .css => .css,
            .html => .html,
            .svelte, .zon, .unknown => .generic,
        };
    }

    pub fn addFile(self: *Self, file_path: []const u8) !void {
        const cwd = self.filesystem.cwd();
        defer cwd.close();

        const file = cwd.openFile(self.allocator, file_path, .{}) catch |err| {
            if (!self.quiet) {
                const stderr = std.io.getStdErr().writer();
                const prefixed_path = try path_utils.addRelativePrefix(self.allocator, file_path);
                defer self.allocator.free(prefixed_path);
                const error_msg = errors.getMessage(err);
                try stderr.print("Error reading file {s}: {s}\n", .{ prefixed_path, error_msg });
            }
            return err;
        };
        defer file.close();

        const stat = try cwd.statFile(self.allocator, file_path);
        if (stat.size > max_file_size) {
            if (!self.quiet) {
                const stderr = std.io.getStdErr().writer();
                const prefixed_path = try path_utils.addRelativePrefix(self.allocator, file_path);
                defer self.allocator.free(prefixed_path);
                try stderr.print("Warning: Skipping large file (>{d}MB): {s}\n", .{ max_file_size / (1024 * 1024), prefixed_path });
            }
            return;
        }

        const content = try file.readAll(self.arena.allocator(), stat.size);

        // Detect file extension for syntax highlighting
        const ext = path_utils.extension(file_path);
        const lang = if (ext.len > 0) ext[1..] else "";

        // Determine language and extract content based on flags
        const language = Language.fromExtension(ext);
        const extracted_content = try self.extractContent(language, content, file_path);
        defer self.allocator.free(extracted_content);

        // Use extracted content instead of raw content
        const display_content = extracted_content;

        // Detect appropriate fence
        const fence_str = try fence.detectFence(display_content, self.arena.allocator());

        // Add file with XML-style tags and markdown code fence
        const prefixed_path = try path_utils.addRelativePrefix(self.arena.allocator(), file_path);
        const header = try std.fmt.allocPrint(self.arena.allocator(), "<File path=\"{s}\">", .{prefixed_path});
        try self.lines.append("");
        try self.lines.append(header);
        try self.lines.append("");

        const fence_start = try std.fmt.allocPrint(self.arena.allocator(), "{s}{s}", .{ fence_str, lang });
        try self.lines.append(fence_start);

        // Add content line by line
        var iter = std.mem.splitScalar(u8, display_content, '\n');
        while (iter.next()) |line| {
            // Copy line to arena allocator to avoid use-after-free
            const line_copy = try self.arena.allocator().dupe(u8, line);
            try self.lines.append(line_copy);
        }

        try self.lines.append(fence_str);
        try self.lines.append("");
        try self.lines.append("</File>");
        try self.lines.append("");
    }

    pub fn addFiles(self: *Self, file_paths: [][]u8) !void {
        if (self.enable_parallel and self.worker_pool != null) {
            try self.addFilesParallel(file_paths);
        } else {
            try self.addFilesSequential(file_paths);
        }
    }

    /// Sequential file processing (original behavior)
    pub fn addFilesSequential(self: *Self, file_paths: [][]u8) !void {
        for (file_paths) |file_path| {
            try self.addFile(file_path);
        }
    }

    /// Parallel file processing using worker pool
    pub fn addFilesParallel(self: *Self, file_paths: [][]u8) !void {
        if (self.worker_pool == null) return error.NoWorkerPool;

        const pool = self.worker_pool.?;

        // Set up progress tracking
        pool.setProgressTracker(@intCast(file_paths.len));

        // Create tasks for each file
        var task_results = std.ArrayList(FileProcessResult).init(self.allocator);
        defer task_results.deinit();
        try task_results.resize(file_paths.len);

        var task_ids = std.ArrayList(u64).init(self.allocator);
        defer task_ids.deinit();

        // Submit tasks to worker pool
        for (file_paths, 0..) |file_path, i| {
            const task_context = try self.allocator.create(FileProcessContext);
            task_context.* = FileProcessContext{
                .builder = self,
                .file_path = file_path,
                .result_index = i,
                .results = &task_results,
            };

            const task_id = try pool.submitTask(.normal, processFileTask, task_context, &.{} // No dependencies for parallel processing
            );

            try task_ids.append(task_id);
        }

        // Wait for all tasks to complete
        pool.waitForCompletion();

        // Collect results in order and add to lines
        for (task_results.items) |result| {
            if (result.success) {
                for (result.lines.items) |line| {
                    try self.lines.append(try self.arena.allocator().dupe(u8, line));
                }
                result.lines.deinit();
            }
            if (result.error_message) |err_msg| {
                self.allocator.free(err_msg);
            }
        }

        // Clean up task contexts
        for (task_ids.items) |_| {
            // Task contexts are cleaned up in processFileTask
        }
    }

    /// Enhanced file processing with caching and incremental support
    pub fn addFileWithCaching(self: *Self, file_path: []const u8) !void {
        // Check if we have incremental support
        if (self.file_tracker) |tracker| {
            try tracker.trackFile(file_path);

            // Check if file has changed
            if (tracker.getFileState(file_path)) |state| {
                // Try to get cached result if available
                if (self.cache_system) |cache| {
                    const cache_key = AstCacheKey.init(state.hash, 1, // Parser version
                        hashExtractionFlags(self.extraction_flags));

                    if (cache.ast_cache.get(cache_key)) |cached_content| {
                        // Use cached content
                        try self.addCachedContent(file_path, cached_content);
                        return;
                    }
                }
            }
        }

        // Fall back to regular processing
        try self.addFile(file_path);
    }

    /// Add content from cache
    fn addCachedContent(self: *Self, file_path: []const u8, cached_content: []const u8) !void {
        const ext = path_utils.extension(file_path);
        const lang = if (ext.len > 0) ext[1..] else "";

        // Detect appropriate fence
        const fence_str = try fence.detectFence(cached_content, self.arena.allocator());

        // Add file with XML-style tags and markdown code fence
        const prefixed_path = try path_utils.addRelativePrefix(self.arena.allocator(), file_path);
        const header = try std.fmt.allocPrint(self.arena.allocator(), "<File path=\"{s}\">", .{prefixed_path});
        try self.lines.append("");
        try self.lines.append(header);
        try self.lines.append("");

        const fence_start = try std.fmt.allocPrint(self.arena.allocator(), "{s}{s}", .{ fence_str, lang });
        try self.lines.append(fence_start);

        // Add cached content line by line
        var iter = std.mem.splitScalar(u8, cached_content, '\n');
        while (iter.next()) |line| {
            try self.lines.append(line);
        }

        try self.lines.append(fence_str);
        try self.lines.append("");
        try self.lines.append("</File>");
        try self.lines.append("");
    }

    pub fn write(self: *Self, writer: anytype) !void {
        for (self.lines.items) |line| {
            try writer.print("{s}\n", .{line});
        }
    }
};

/// Context for file processing tasks
const FileProcessContext = struct {
    builder: *PromptBuilder,
    file_path: []const u8,
    result_index: usize,
    results: *std.ArrayList(FileProcessResult),
};

/// Result of file processing task
const FileProcessResult = struct {
    success: bool,
    lines: std.ArrayList([]const u8),
    error_message: ?[]const u8,

    pub fn init(allocator: std.mem.Allocator) FileProcessResult {
        return FileProcessResult{
            .success = false,
            .lines = std.ArrayList([]const u8).init(allocator),
            .error_message = null,
        };
    }

    pub fn deinit(self: *FileProcessResult, allocator: std.mem.Allocator) void {
        for (self.lines.items) |line| {
            allocator.free(line);
        }
        self.lines.deinit();
        if (self.error_message) |err_msg| {
            allocator.free(err_msg);
        }
    }
};

/// Task function for parallel file processing
fn processFileTask(task: *Task, context: ?*anyopaque) !void {
    const ctx: *FileProcessContext = @ptrCast(@alignCast(context orelse return));
    defer ctx.builder.allocator.destroy(ctx);

    const allocator = ctx.builder.allocator;
    var result = FileProcessResult.init(allocator);

    // Process file with error handling
    processFileSafe(ctx.builder, ctx.file_path, &result) catch |err| {
        result.success = false;
        const error_msg = std.fmt.allocPrint(allocator, "Failed to process {s}: {}", .{ ctx.file_path, err }) catch return;
        result.error_message = error_msg;
    };

    // Store result at the correct index
    ctx.results.items[ctx.result_index] = result;

    // Store result pointer in task for cleanup if needed
    task.result = &ctx.results.items[ctx.result_index];
}

/// Safe file processing that captures errors
fn processFileSafe(builder: *PromptBuilder, file_path: []const u8, result: *FileProcessResult) !void {
    // Create temporary arena for this file processing
    var temp_arena = std.heap.ArenaAllocator.init(builder.allocator);
    defer temp_arena.deinit();
    const temp_allocator = temp_arena.allocator();

    // Process file using same logic as addFile but store in result
    const cwd = builder.filesystem.cwd();
    defer cwd.close();

    const file = cwd.openFile(builder.allocator, file_path, .{}) catch |err| {
        const error_msg = errors.getMessage(err);
        if (!builder.quiet) {
            const stderr = std.io.getStdErr().writer();
            const prefixed_path = path_utils.addRelativePrefix(builder.allocator, file_path) catch return;
            defer builder.allocator.free(prefixed_path);
            stderr.print("Error reading file {s}: {s}\n", .{ prefixed_path, error_msg }) catch {};
        }
        result.error_message = try builder.allocator.dupe(u8, error_msg);
        return;
    };
    defer file.close();

    const stat = try cwd.statFile(builder.allocator, file_path);
    if (stat.size > PromptBuilder.max_file_size) {
        // Skip large files
        result.success = true;
        return;
    }

    const content = try file.readAll(temp_allocator, stat.size);

    // Extract content using stratified parser
    const ext = path_utils.extension(file_path);
    const lang = if (ext.len > 0) ext[1..] else "";

    // For now, just use the content directly since we're focused on parsing validation
    // TODO: Implement fact-to-content extraction for parallel processing
    const extracted_content = content;
    const fence_str = try fence.detectFence(extracted_content, temp_allocator);

    // Build result lines
    const prefixed_path = try path_utils.addRelativePrefix(temp_allocator, file_path);
    const header = try std.fmt.allocPrint(temp_allocator, "<File path=\"{s}\">", .{prefixed_path});

    // Copy lines to result (using main allocator for persistence)
    try result.lines.append(try builder.allocator.dupe(u8, ""));
    try result.lines.append(try builder.allocator.dupe(u8, header));
    try result.lines.append(try builder.allocator.dupe(u8, ""));

    const fence_start = try std.fmt.allocPrint(temp_allocator, "{s}{s}", .{ fence_str, lang });
    try result.lines.append(try builder.allocator.dupe(u8, fence_start));

    // Add content line by line
    var iter = std.mem.splitScalar(u8, extracted_content, '\n');
    while (iter.next()) |line| {
        try result.lines.append(try builder.allocator.dupe(u8, line));
    }

    try result.lines.append(try builder.allocator.dupe(u8, fence_str));
    try result.lines.append(try builder.allocator.dupe(u8, ""));
    try result.lines.append(try builder.allocator.dupe(u8, "</File>"));
    try result.lines.append(try builder.allocator.dupe(u8, ""));

    result.success = true;
}

/// Hash extraction flags for cache key generation
fn hashExtractionFlags(flags: ExtractionFlags) u64 {
    var hasher = std.hash.XxHash64.init(0);
    hasher.update(std.mem.asBytes(&flags.signatures));
    hasher.update(std.mem.asBytes(&flags.types));
    hasher.update(std.mem.asBytes(&flags.docs));
    hasher.update(std.mem.asBytes(&flags.structure));
    hasher.update(std.mem.asBytes(&flags.imports));
    hasher.update(std.mem.asBytes(&flags.errors));
    hasher.update(std.mem.asBytes(&flags.tests));
    hasher.update(std.mem.asBytes(&flags.full));
    return hasher.final();
}
