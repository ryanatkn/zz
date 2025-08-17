const std = @import("std");
const ZonParser = @import("../languages/zon/parser.zig").ZonParser;
const DependencyInfo = @import("../languages/zon/parser.zig").DependencyInfo;

/// Configuration for a single dependency
pub const Dependency = struct {
    name: []const u8,
    url: []const u8,
    version: []const u8,
    include: []const []const u8 = &.{},        // If set, ONLY copy these patterns
    exclude: []const []const u8 = &.{},        // Never copy these patterns
    preserve_files: []const []const u8 = &.{},
    patches: []const []const u8 = &.{},
    // Optional metadata for documentation generation
    category: ?[]const u8 = null,
    language: ?[]const u8 = null,
    purpose: ?[]const u8 = null,
    // Track if this dependency owns its memory (true for allocated, false for literals)
    owns_memory: bool = true,

    pub fn deinit(self: *const Dependency, allocator: std.mem.Allocator) void {
        if (!self.owns_memory) return; // Don't free string literals
        
        allocator.free(self.name);
        allocator.free(self.url);
        allocator.free(self.version);
        
        // Free duplicated arrays
        allocator.free(self.include);
        allocator.free(self.exclude);
        allocator.free(self.preserve_files);
        allocator.free(self.patches);
        
        // Free optional metadata
        if (self.category) |category| allocator.free(category);
        if (self.language) |language| allocator.free(language);
        if (self.purpose) |purpose| allocator.free(purpose);
    }
};

/// Version information stored in .version files
pub const VersionInfo = struct {
    repository: []const u8,
    version: []const u8,
    commit: []const u8,
    updated: i64,
    updated_by: []const u8,

    pub fn deinit(self: *const VersionInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.repository);
        allocator.free(self.version);
        allocator.free(self.commit);
        allocator.free(self.updated_by);
    }

    /// Parse .version file content into VersionInfo
    pub fn parseFromContent(allocator: std.mem.Allocator, content: []const u8) !VersionInfo {
        var repository: []const u8 = "";
        var version: []const u8 = "";
        var commit: []const u8 = "";
        var updated: i64 = 0;
        var updated_by: []const u8 = "";

        var lines = std.mem.splitSequence(u8, content, "\n");
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r\n");
            if (trimmed.len == 0) continue;

            if (std.mem.startsWith(u8, trimmed, "Repository: ")) {
                repository = try allocator.dupe(u8, trimmed[12..]);
            } else if (std.mem.startsWith(u8, trimmed, "Version: ")) {
                version = try allocator.dupe(u8, trimmed[9..]);
            } else if (std.mem.startsWith(u8, trimmed, "Commit: ")) {
                commit = try allocator.dupe(u8, trimmed[8..]);
            } else if (std.mem.startsWith(u8, trimmed, "Updated: ")) {
                const timestamp_str = trimmed[9..];
                updated = parseTimestamp(timestamp_str) catch 0; // Default to 0 if parsing fails
            } else if (std.mem.startsWith(u8, trimmed, "Updated-By: ")) {
                updated_by = try allocator.dupe(u8, trimmed[12..]);
            }
        }

        return VersionInfo{
            .repository = repository,
            .version = version,
            .commit = commit,
            .updated = updated,
            .updated_by = updated_by,
        };
    }

    /// Parse timestamp string in format "YYYY-MM-DD HH:MM:SS UTC" to Unix timestamp
    fn parseTimestamp(timestamp_str: []const u8) !i64 {
        // Expected format: "2024-08-16 14:23:45 UTC"
        if (timestamp_str.len < 19) return error.InvalidTimestamp;
        
        // Parse components
        const year_str = timestamp_str[0..4];
        const month_str = timestamp_str[5..7];
        const day_str = timestamp_str[8..10];
        const hour_str = timestamp_str[11..13];
        const minute_str = timestamp_str[14..16];
        const second_str = timestamp_str[17..19];
        
        const year = try std.fmt.parseInt(u32, year_str, 10);
        const month = try std.fmt.parseInt(u8, month_str, 10);
        const day = try std.fmt.parseInt(u8, day_str, 10);
        const hour = try std.fmt.parseInt(u8, hour_str, 10);
        const minute = try std.fmt.parseInt(u8, minute_str, 10);
        const second = try std.fmt.parseInt(u8, second_str, 10);
        
        // Basic validation
        if (month < 1 or month > 12) return error.InvalidMonth;
        if (day < 1 or day > 31) return error.InvalidDay;
        if (hour > 23) return error.InvalidHour;
        if (minute > 59) return error.InvalidMinute;
        if (second > 59) return error.InvalidSecond;
        
        // Convert to Unix timestamp (simplified - doesn't handle leap years perfectly)
        const days_since_epoch = daysSinceEpoch(year, month, day);
        const seconds_in_day = @as(i64, hour) * 3600 + @as(i64, minute) * 60 + @as(i64, second);
        
        return days_since_epoch * 86400 + seconds_in_day;
    }
    
    /// Calculate days since Unix epoch (1970-01-01)
    fn daysSinceEpoch(year: u32, month: u8, day: u8) i64 {
        // Simplified calculation - good enough for our purposes
        var total_days: i64 = 0;
        
        // Add days for complete years
        var y: u32 = 1970;
        while (y < year) : (y += 1) {
            if (isLeapYear(y)) {
                total_days += 366;
            } else {
                total_days += 365;
            }
        }
        
        // Add days for complete months in current year
        const days_in_month = [_]u8{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
        var m: u8 = 1;
        while (m < month) : (m += 1) {
            total_days += days_in_month[m - 1];
            // Add extra day for February in leap year
            if (m == 2 and isLeapYear(year)) {
                total_days += 1;
            }
        }
        
        // Add days in current month
        total_days += day - 1; // -1 because we want days since, not including
        
        return total_days;
    }
    
    /// Check if a year is a leap year
    fn isLeapYear(year: u32) bool {
        return (year % 4 == 0 and year % 100 != 0) or (year % 400 == 0);
    }

    /// Generate .version file content
    pub fn toContent(self: *const VersionInfo, allocator: std.mem.Allocator) ![]u8 {
        // Use the stored timestamp if available, otherwise current time
        const timestamp = if (self.updated != 0) self.updated else std.time.timestamp();
        const time_info = std.time.epoch.EpochSeconds{ .secs = @intCast(timestamp) };
        const day_seconds = time_info.getDaySeconds();
        const epoch_day = time_info.getEpochDay();
        const year_day = epoch_day.calculateYearDay();
        const month_day = year_day.calculateMonthDay();

        var hostname_buf: [64]u8 = undefined;
        const hostname = std.posix.gethostname(&hostname_buf) catch "unknown";

        const username = std.process.getEnvVarOwned(allocator, "USER") catch |err| switch (err) {
            error.EnvironmentVariableNotFound => try allocator.dupe(u8, "unknown"),
            else => return err,
        };
        defer allocator.free(username);

        return std.fmt.allocPrint(allocator,
            \\Repository: {s}
            \\Version: {s}
            \\Commit: {s}
            \\Updated: {d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2} UTC
            \\Updated-By: {s}@{s}
            \\
        , .{
            self.repository,
            self.version,
            self.commit,
            year_day.year,
            month_day.month.numeric(),
            month_day.day_index + 1,
            day_seconds.getHoursIntoDay(),
            day_seconds.getMinutesIntoHour(),
            day_seconds.getSecondsIntoMinute(),
            username,
            hostname,
        });
    }
};

/// Configuration for dependency operations
pub const UpdateOptions = struct {
    force_all: bool = false,
    force_dep: ?[]const u8 = null,
    check_only: bool = false,
    list_only: bool = false,
    dry_run: bool = false,
    update_pattern: ?[]const u8 = null,
    verbose: bool = false,
    color: bool = true,
    backup: bool = true,
    retries: u32 = 3,
    /// Respect semantic version tags - don't upgrade from tags to main branch
    respect_semantic_versions: bool = true,
    generate_docs: bool = false,
};

/// ZON configuration structure - direct mapping to deps.zon format
pub const DepsZonConfig = struct {
    dependencies: std.StringHashMap(DependencyZonEntry),
    settings: ?SettingsStruct = null,
    allocator: std.mem.Allocator,
    /// Track if strings were allocated (ZON parsed) or are literals (hardcoded)
    owns_strings: bool = false,

    /// Parse dependencies from ZON content using the dedicated ZON module
    /// This eliminates the memory leak and provides proper string management

    pub fn parseFromZonContent(allocator: std.mem.Allocator, content: []const u8) !DepsZonConfig {
        // Use the dedicated ZON module for proper parsing and memory management
        var zon_parser = ZonParser.init(allocator);
        
        // Parse dependencies using the ZON module
        var zon_dependencies = try zon_parser.parseDependencies(content);
        
        // Convert ZON module results to our internal format
        var dependencies = std.StringHashMap(DependencyZonEntry).init(allocator);
        
        var zon_iterator = zon_dependencies.iterator();
        while (zon_iterator.next()) |entry| {
            const dep_name_orig = entry.key_ptr.*;
            const dep_info = entry.value_ptr.*;
            
            // Duplicate all strings to ensure proper ownership in our structure
            const dep_name = try allocator.dupe(u8, dep_name_orig);
            const dep_entry = DependencyZonEntry{
                .url = if (dep_info.url) |url| try allocator.dupe(u8, url) else try allocator.dupe(u8, "https://example.com/repo.git"),
                .version = if (dep_info.version) |version| try allocator.dupe(u8, version) else try allocator.dupe(u8, "main"),
                .include = &.{},
                .exclude = &.{},
                .preserve_files = &.{},
                .patches = &.{},
                .category = null,
                .language = null,
                .purpose = null,
            };
            
            try dependencies.put(dep_name, dep_entry);
        }
        
        // Clean up ZON dependencies properly using the parser's method
        zon_parser.freeDependencies(&zon_dependencies);
        
        // Default settings (safe literals)
        const settings = SettingsStruct{
            .deps_dir = null,
            .backup_enabled = true,
            .lock_timeout_seconds = 300,
            .clone_retries = 3,
            .clone_timeout_seconds = 60,
        };
        
        return DepsZonConfig{
            .dependencies = dependencies,
            .settings = settings,
            .allocator = allocator,
            .owns_strings = true, // ZON module provides properly allocated strings
        };
    }
    
    
    
    

    pub const DependencyZonEntry = struct {
        url: []const u8,
        version: []const u8,
        include: []const []const u8 = &.{},
        exclude: []const []const u8 = &.{},
        preserve_files: []const []const u8,
        patches: []const []const u8,
        // Optional metadata for documentation generation
        category: ?[]const u8 = null,
        language: ?[]const u8 = null,
        purpose: ?[]const u8 = null,
    };

    pub const SettingsStruct = struct {
        deps_dir: ?[]const u8 = null,
        backup_enabled: ?bool = null,
        lock_timeout_seconds: ?u32 = null,
        clone_retries: ?u32 = null,
        clone_timeout_seconds: ?u32 = null,
        /// Respect semantic version tags - don't upgrade from tags to main branch
        respect_semantic_versions: ?bool = null,
    };

    /// Convert to DepsConfig format for use by dependency manager
    pub fn toDepsConfig(self: *const DepsZonConfig, allocator: std.mem.Allocator) !DepsConfig {
        var deps_config = DepsConfig{
            .dependencies = std.StringHashMap(DepsConfig.DependencyEntry).init(allocator),
        };

        // Copy dependencies from our HashMap
        var iterator = self.dependencies.iterator();
        while (iterator.next()) |entry| {
            const dep_name = entry.key_ptr.*;
            const dep_value = entry.value_ptr.*;
            
            
            const hash_entry = DepsConfig.DependencyEntry{
                .url = dep_value.url,
                .version = dep_value.version,
                .include = dep_value.include,
                .exclude = dep_value.exclude,
                .preserve_files = dep_value.preserve_files,
                .patches = dep_value.patches,
                .category = dep_value.category,
                .language = dep_value.language,
                .purpose = dep_value.purpose,
            };
            
            const key_copy = try allocator.dupe(u8, dep_name);
            try deps_config.dependencies.put(key_copy, hash_entry);
        }

        return deps_config;
    }
    
    
    
    /// Free the dependencies HashMap and all allocated memory
    pub fn deinit(self: *DepsZonConfig) void {
        // Free all allocated strings if they were from ZON parsing
        if (self.owns_strings) {
            var iterator = self.dependencies.iterator();
            while (iterator.next()) |entry| {
                // Free the key (dependency name) - always allocated
                self.allocator.free(entry.key_ptr.*);
                
                // Free the value strings - all are allocated by our conversion
                const dep = entry.value_ptr.*;
                self.allocator.free(dep.url);
                self.allocator.free(dep.version);
                
                // Free string arrays (these are currently empty slices, safe to skip)
                // The include, exclude, preserve_files, patches arrays are currently literals
                // No need to free them in the current implementation
            }
            
            // Free settings if allocated (currently using literals)
            if (self.settings) |settings| {
                if (settings.deps_dir) |dir| {
                    // Only free if it's not a literal
                    if (!std.mem.eql(u8, dir, "deps")) {
                        self.allocator.free(dir);
                    }
                }
            }
        }
        
        self.dependencies.deinit();
    }
};

/// Dependencies configuration structure for runtime use
pub const DepsConfig = struct {
    dependencies: std.StringHashMap(DependencyEntry),

    pub const DependencyEntry = struct {
        url: []const u8,
        version: []const u8,
        include: []const []const u8 = &.{},
        exclude: []const []const u8 = &.{},
        preserve_files: []const []const u8 = &.{},
        patches: []const []const u8 = &.{},
        // Optional metadata for documentation generation
        category: ?[]const u8 = null,
        language: ?[]const u8 = null,
        purpose: ?[]const u8 = null,
    };

    pub fn deinit(self: *DepsConfig, allocator: std.mem.Allocator) void {
        // Free all keys in the hash map
        var iterator = self.dependencies.iterator();
        while (iterator.next()) |entry| {
            allocator.free(entry.key_ptr.*);
        }
        self.dependencies.deinit();
    }

    /// Convert to array of Dependency structs
    pub fn toDependencies(self: *const DepsConfig, allocator: std.mem.Allocator) ![]Dependency {
        var deps = std.ArrayList(Dependency).init(allocator);
        defer deps.deinit();

        var iterator = self.dependencies.iterator();
        while (iterator.next()) |entry| {
            
            const dep = Dependency{
                .name = try allocator.dupe(u8, entry.key_ptr.*),
                .url = try allocator.dupe(u8, entry.value_ptr.url),
                .version = try allocator.dupe(u8, entry.value_ptr.version),
                .include = try allocator.dupe([]const u8, entry.value_ptr.include),
                .exclude = try allocator.dupe([]const u8, entry.value_ptr.exclude),
                .preserve_files = try allocator.dupe([]const u8, entry.value_ptr.preserve_files),
                .patches = try allocator.dupe([]const u8, entry.value_ptr.patches),
                .category = if (entry.value_ptr.category) |cat| try allocator.dupe(u8, cat) else null,
                .language = if (entry.value_ptr.language) |lang| try allocator.dupe(u8, lang) else null,
                .purpose = if (entry.value_ptr.purpose) |purpose| try allocator.dupe(u8, purpose) else null,
                .owns_memory = true, // These are allocated, so we own them
            };
            try deps.append(dep);
        }

        return deps.toOwnedSlice();
    }
};

// Tests
test "Dependency memory management" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    // Test string literal (no ownership)
    const dep1 = Dependency{
        .name = "test-dep",
        .url = "https://example.com/repo.git",
        .version = "v1.0.0",
        .include = &.{},
        .exclude = &.{"build.zig", "*.md"},
        .preserve_files = &.{},
        .patches = &.{},
        .owns_memory = false,
    };
    
    // Should not crash when deinitializing string literals
    dep1.deinit(allocator);
    
    // Test allocated strings (with ownership)
    const dep2 = Dependency{
        .name = try allocator.dupe(u8, "test-dep"),
        .url = try allocator.dupe(u8, "https://example.com/repo.git"),
        .version = try allocator.dupe(u8, "v1.0.0"),
        .include = try allocator.dupe([]const u8, &.{}),
        .exclude = try allocator.dupe([]const u8, &.{"build.zig", "*.md"}),
        .preserve_files = try allocator.dupe([]const u8, &.{}),
        .patches = try allocator.dupe([]const u8, &.{}),
        .owns_memory = true,
    };
    
    // Should properly free allocated memory
    dep2.deinit(allocator);
}

test "VersionInfo parsing and serialization" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    const original = VersionInfo{
        .repository = "https://github.com/test/repo.git",
        .version = "v1.2.3",
        .commit = "abc123def456",
        .updated = 1704067200, // 2024-01-01 00:00:00 UTC
        .updated_by = "",
    };
    
    // Convert to content string
    const content = try original.toContent(allocator);
    defer allocator.free(content);
    
    // Parse back from content
    const parsed = try VersionInfo.parseFromContent(allocator, content);
    defer parsed.deinit(allocator);
    
    // Verify fields match
    try testing.expectEqualStrings(original.repository, parsed.repository);
    try testing.expectEqualStrings(original.version, parsed.version);
    try testing.expectEqualStrings(original.commit, parsed.commit);
}

test "parseTimestamp" {
    const testing = std.testing;
    
    // Test valid ISO-like timestamps
    const ts1 = VersionInfo.parseTimestamp("2024-01-01 00:00:00 UTC") catch 0;
    const ts2 = VersionInfo.parseTimestamp("2024-01-01 12:00:00 UTC") catch 0;
    
    // Basic validation - timestamps should be positive and reasonable
    try testing.expect(ts1 > 0);
    try testing.expect(ts2 > ts1); // 12:00 is after 00:00
    
    // Test invalid timestamps
    const invalid1 = VersionInfo.parseTimestamp("invalid") catch 0;
    const invalid2 = VersionInfo.parseTimestamp("") catch 0;
    const invalid3 = VersionInfo.parseTimestamp("2024-01-01") catch 0; // Too short
    
    try testing.expectEqual(@as(i64, 0), invalid1);
    try testing.expectEqual(@as(i64, 0), invalid2);
    try testing.expectEqual(@as(i64, 0), invalid3);
}

test "isLeapYear" {
    const testing = std.testing;
    
    // Test leap years
    try testing.expect(VersionInfo.isLeapYear(2000)); // Divisible by 400
    try testing.expect(VersionInfo.isLeapYear(2004)); // Divisible by 4
    try testing.expect(VersionInfo.isLeapYear(2020)); // Divisible by 4
    
    // Test non-leap years
    try testing.expect(!VersionInfo.isLeapYear(1900)); // Divisible by 100 but not 400
    try testing.expect(!VersionInfo.isLeapYear(2001)); // Not divisible by 4
    try testing.expect(!VersionInfo.isLeapYear(2100)); // Divisible by 100 but not 400
}

test "DepsConfig operations" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    var config = DepsConfig{
        .dependencies = std.StringHashMap(DepsConfig.DependencyEntry).init(allocator),
    };
    defer config.deinit(allocator);
    
    // Add a dependency
    const key = try allocator.dupe(u8, "test-dep");
    try config.dependencies.put(key, DepsConfig.DependencyEntry{
        .url = "https://example.com/repo.git",
        .version = "v1.0.0",
        .include = &.{},
        .exclude = &.{},
        .preserve_files = &.{},
        .patches = &.{},
    });
    
    // Convert to Dependencies array
    const deps = try config.toDependencies(allocator);
    defer {
        for (deps) |*dep| {
            dep.deinit(allocator);
        }
        allocator.free(deps);
    }
    
    try testing.expectEqual(@as(usize, 1), deps.len);
    try testing.expectEqualStrings("test-dep", deps[0].name);
    try testing.expectEqualStrings("https://example.com/repo.git", deps[0].url);
}