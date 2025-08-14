const std = @import("std");
const AstFormatter = @import("ast_formatter.zig").AstFormatter;
const AstCache = @import("cache.zig").AstCache;
const AstCacheKey = @import("cache.zig").AstCacheKey;
const FormatterOptions = @import("formatter.zig").FormatterOptions;
const Language = @import("parser.zig").Language;
const FileTracker = @import("incremental.zig").FileTracker;

/// A formatter manager that coordinates AST formatters with shared caching
pub const CachedFormatterManager = struct {
    allocator: std.mem.Allocator,
    cache: AstCache,
    file_tracker: ?*FileTracker,
    formatters: std.HashMap(Language, AstFormatter, LanguageContext, 80),
    
    const Self = @This();
    
    const LanguageContext = struct {
        pub fn hash(self: @This(), s: Language) u64 {
            _ = self;
            return @intFromEnum(s);
        }
        pub fn eql(self: @This(), a: Language, b: Language) bool {
            _ = self;
            return a == b;
        }
    };
    
    pub fn init(allocator: std.mem.Allocator, max_cache_entries: usize) !Self {
        const cache = AstCache.init(allocator, max_cache_entries, 64); // 64MB max memory
        
        return Self{
            .allocator = allocator,
            .cache = cache,
            .file_tracker = null,
            .formatters = std.HashMap(Language, AstFormatter, LanguageContext, 80).init(allocator),
        };
    }
    
    pub fn initWithFileTracker(allocator: std.mem.Allocator, max_cache_entries: usize, file_tracker: *FileTracker) !Self {
        const cache = AstCache.init(allocator, max_cache_entries, 64); // 64MB max memory
        
        // Integrate cache with file tracker for automatic invalidation
        file_tracker.ast_cache = &cache;
        
        return Self{
            .allocator = allocator,
            .cache = cache,
            .file_tracker = file_tracker,
            .formatters = std.HashMap(Language, AstFormatter, LanguageContext, 80).init(allocator),
        };
    }
    
    pub fn deinit(self: *Self) void {
        // Clean up all formatters
        var iter = self.formatters.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.formatters.deinit();
        
        self.cache.deinit();
    }
    
    /// Get or create a formatter for the specified language
    pub fn getFormatter(self: *Self, language: Language, options: FormatterOptions) !*AstFormatter {
        // Check if we already have a formatter for this language
        if (self.formatters.getPtr(language)) |formatter| {
            // Update options if they've changed
            formatter.options = options;
            return formatter;
        }
        
        // Create new formatter with cache integration
        const formatter = try AstFormatter.initWithCache(self.allocator, language, options, &self.cache);
        
        // Store in our cache
        try self.formatters.put(language, formatter);
        
        return self.formatters.getPtr(language).?;
    }
    
    /// Format a file with automatic language detection and caching
    pub fn formatFile(self: *Self, file_path: []const u8, source: []const u8, options: FormatterOptions) ![]const u8 {
        // Detect language from file extension
        const language = Language.fromExtension(std.fs.path.extension(file_path));
        
        if (language == .unknown) {
            // Return original source for unknown file types
            return self.allocator.dupe(u8, source);
        }
        
        // Get or create formatter for this language
        var formatter = try self.getFormatter(language, options);
        
        // Format with file path for better caching
        return formatter.formatWithFilePath(source, file_path);
    }
    
    /// Format source with explicit language
    pub fn formatSource(self: *Self, language: Language, source: []const u8, options: FormatterOptions) ![]const u8 {
        if (language == .unknown) {
            return self.allocator.dupe(u8, source);
        }
        
        var formatter = try self.getFormatter(language, options);
        return formatter.format(source);
    }
    
    /// Invalidate cache entries for a specific file
    pub fn invalidateFile(self: *Self, file_path: []const u8) void {
        if (self.file_tracker) |tracker| {
            // Use the public interface for cache invalidation
            tracker.invalidateAstCacheForFiles(&[_][]const u8{file_path}) catch {
                // If invalidation fails, clear entire cache as fallback
                self.cache.clear();
            };
        } else {
            // Without FileTracker, we can't efficiently invalidate specific files
            // Future: could implement manual cache key invalidation here using file_path
            // For now, users should use FileTracker integration for proper cache invalidation
        }
    }
    
    /// Get cache statistics
    pub fn getCacheStats(self: *Self) @import("cache.zig").AstCache.CacheStats {
        return self.cache.getStats();
    }
    
    /// Clear the entire cache
    pub fn clearCache(self: *Self) void {
        self.cache.clear();
    }
    
    /// Get the number of cached formatters
    pub fn getFormatterCount(self: *Self) usize {
        return self.formatters.count();
    }
};