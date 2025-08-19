const std = @import("std");
pub const Span = @import("../parser/foundation/types/span.zig").Span;

/// Core type definitions for the transform system
/// Based on existing patterns from the codebase
/// Result type for transforms that can partially succeed
/// Similar to our existing error handling patterns in filesystem.zig
pub const TransformResult = union(enum) {
    success: struct {
        output: []const u8,
        warnings: []Diagnostic,
        allocator: std.mem.Allocator, // Track allocator for cleanup
    },
    partial: struct {
        output: []const u8,
        errors: []Diagnostic,
        recovered_count: usize,
        allocator: std.mem.Allocator,
    },
    failure: struct {
        errors: []Diagnostic,
        allocator: std.mem.Allocator,
    },

    pub fn deinit(self: *TransformResult) void {
        switch (self.*) {
            .success => |s| {
                s.allocator.free(s.output);
                for (s.warnings) |*w| {
                    w.deinit(s.allocator);
                }
                s.allocator.free(s.warnings);
            },
            .partial => |p| {
                p.allocator.free(p.output);
                for (p.errors) |*e| {
                    e.deinit(p.allocator);
                }
                p.allocator.free(p.errors);
            },
            .failure => |f| {
                for (f.errors) |*e| {
                    e.deinit(f.allocator);
                }
                f.allocator.free(f.errors);
            },
        }
    }
};

/// Diagnostic information for errors and warnings
/// Similar to our existing linter diagnostics
pub const Diagnostic = struct {
    level: Level,
    message: []const u8,
    span: ?Span,
    line: ?u32,
    column: ?u32,
    suggestion: ?[]const u8,
    code: ?[]const u8, // Error code for categorization

    pub const Level = enum {
        err,
        warning,
        info,
        hint,
    };

    /// Free diagnostic resources
    pub fn deinit(self: Diagnostic, allocator: std.mem.Allocator) void {
        allocator.free(self.message);
        if (self.suggestion) |suggestion| {
            allocator.free(suggestion);
        }
        if (self.code) |code| {
            allocator.free(code);
        }
    }

    /// Create an error diagnostic
    pub fn err(allocator: std.mem.Allocator, message: []const u8, span: ?Span) !Diagnostic {
        return Diagnostic{
            .level = .err,
            .message = try allocator.dupe(u8, message),
            .span = span,
            .line = null,
            .column = null,
            .suggestion = null,
            .code = null,
        };
    }

    /// Create a warning diagnostic
    pub fn warn(allocator: std.mem.Allocator, message: []const u8, span: ?Span) !Diagnostic {
        return Diagnostic{
            .level = .warning,
            .message = try allocator.dupe(u8, message),
            .span = span,
            .line = null,
            .column = null,
            .suggestion = null,
            .code = null,
        };
    }

    /// Create an error diagnostic with line/column info
    pub fn errWithLineCol(allocator: std.mem.Allocator, message: []const u8, span: ?Span, line: ?u32, column: ?u32) !Diagnostic {
        return Diagnostic{
            .level = .err,
            .message = try allocator.dupe(u8, message),
            .span = span,
            .line = line,
            .column = column,
            .suggestion = null,
            .code = null,
        };
    }
};

/// IO mode for parameterized execution
/// Following the TODO in core/io.zig
pub const IOMode = enum {
    synchronous,
    asynchronous,
    streaming,
};

/// Transform metadata for introspection and optimization
pub const TransformMetadata = struct {
    name: []const u8,
    description: []const u8,
    reversible: bool = false,
    streaming_capable: bool = false,
    estimated_memory: usize = 0,
    performance_class: PerformanceClass = .moderate,
    language: ?[]const u8 = null, // Optional language association

    pub const PerformanceClass = enum {
        fast, // <1ms typical
        moderate, // 1-10ms typical
        slow, // >10ms typical
    };
};

/// Progress tracking for long-running operations
/// Based on existing patterns in benchmark code
pub const Progress = struct {
    total_steps: usize,
    current_step: usize,
    current_name: []const u8,
    start_time: i64,
    step_times: std.ArrayList(i64),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Progress {
        return .{
            .total_steps = 0,
            .current_step = 0,
            .current_name = "",
            .start_time = std.time.milliTimestamp(),
            .step_times = std.ArrayList(i64).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Progress) void {
        self.step_times.deinit();
    }

    pub fn setTotal(self: *Progress, total: usize) !void {
        self.total_steps = total;
        try self.step_times.ensureTotalCapacity(total);
    }

    pub fn setStep(self: *Progress, step: usize, name: []const u8) !void {
        self.current_step = step;
        self.current_name = name;
        try self.step_times.append(std.time.milliTimestamp());
    }

    pub fn completeStep(self: *Progress, step: usize) !void {
        _ = self;
        _ = step;
        // Could emit progress events here
    }

    pub fn getPercentage(self: Progress) f32 {
        if (self.total_steps == 0) return 0;
        return @as(f32, @floatFromInt(self.current_step)) / @as(f32, @floatFromInt(self.total_steps)) * 100;
    }

    pub fn getElapsedMs(self: Progress) i64 {
        return std.time.milliTimestamp() - self.start_time;
    }
};

/// Error types for transform operations
pub const TransformError = error{
    // Transform-specific errors
    NotReversible,
    InvalidInput,
    InvalidOutput,
    IncompatibleTypes,
    PipelineBroken,
    Cancelled,

    // Parse errors (from existing parsers)
    UnexpectedToken,
    UnexpectedEof,
    InvalidSyntax,
    InvalidEscape,

    // Memory errors
    OutOfMemory,

    // IO errors
    FileNotFound,
    AccessDenied,
    BrokenPipe,

    // Generic
    Unknown,
};

/// Options storage similar to FormatOptions but more generic
pub const OptionsMap = struct {
    map: std.StringHashMap(Value),
    allocator: std.mem.Allocator,

    pub const Value = union(enum) {
        boolean: bool,
        integer: i64,
        unsigned: u64,
        float: f64,
        string: []const u8,

        pub fn deinit(self: *Value, allocator: std.mem.Allocator) void {
            switch (self.*) {
                .string => |s| allocator.free(s),
                else => {},
            }
        }
    };

    pub fn init(allocator: std.mem.Allocator) OptionsMap {
        return .{
            .map = std.StringHashMap(Value).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *OptionsMap) void {
        var iter = self.map.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(self.allocator);
        }
        self.map.deinit();
    }

    pub fn setBool(self: *OptionsMap, key: []const u8, value: bool) !void {
        // Check if key already exists and free old values
        if (self.map.fetchRemove(key)) |kv| {
            switch (kv.value) {
                .string => |s| self.allocator.free(s),
                else => {},
            }
            self.allocator.free(kv.key);
        }

        const owned_key = try self.allocator.dupe(u8, key);
        try self.map.put(owned_key, .{ .boolean = value });
    }

    pub fn setInt(self: *OptionsMap, key: []const u8, value: i64) !void {
        // Check if key already exists and free old values
        if (self.map.fetchRemove(key)) |kv| {
            switch (kv.value) {
                .string => |s| self.allocator.free(s),
                else => {},
            }
            self.allocator.free(kv.key);
        }

        const owned_key = try self.allocator.dupe(u8, key);
        try self.map.put(owned_key, .{ .integer = value });
    }

    pub fn setString(self: *OptionsMap, key: []const u8, value: []const u8) !void {
        // Check if key already exists and free old values
        if (self.map.fetchRemove(key)) |kv| {
            switch (kv.value) {
                .string => |s| self.allocator.free(s),
                else => {},
            }
            self.allocator.free(kv.key);
        }

        const owned_key = try self.allocator.dupe(u8, key);
        const owned_value = try self.allocator.dupe(u8, value);
        try self.map.put(owned_key, .{ .string = owned_value });
    }

    pub fn getBool(self: OptionsMap, key: []const u8) ?bool {
        if (self.map.get(key)) |value| {
            return switch (value) {
                .boolean => |b| b,
                else => null,
            };
        }
        return null;
    }

    pub fn getInt(self: OptionsMap, key: []const u8) ?i64 {
        if (self.map.get(key)) |value| {
            return switch (value) {
                .integer => |i| i,
                else => null,
            };
        }
        return null;
    }

    pub fn getString(self: OptionsMap, key: []const u8) ?[]const u8 {
        if (self.map.get(key)) |value| {
            return switch (value) {
                .string => |s| s,
                else => null,
            };
        }
        return null;
    }
};

// Tests
const testing = std.testing;

test "Span operations" {
    const span1 = Span.init(10, 20);
    const span2 = Span.init(15, 25);

    try testing.expectEqual(@as(usize, 10), span1.len());
    try testing.expect(span1.contains(15));
    try testing.expect(!span1.contains(25));
    try testing.expect(span1.overlaps(span2));
}

test "Diagnostic creation" {
    const allocator = testing.allocator;

    const diag = try Diagnostic.err(allocator, "test error", Span.init(0, 10));
    defer {
        var mut_diag = diag;
        mut_diag.deinit(allocator);
    }

    try testing.expectEqual(Diagnostic.Level.err, diag.level);
    try testing.expectEqualStrings("test error", diag.message);
}

test "OptionsMap" {
    const allocator = testing.allocator;

    var options = OptionsMap.init(allocator);
    defer options.deinit();

    try options.setBool("enabled", true);
    try options.setInt("count", 42);
    try options.setString("name", "test");

    try testing.expectEqual(@as(?bool, true), options.getBool("enabled"));
    try testing.expectEqual(@as(?i64, 42), options.getInt("count"));
    try testing.expectEqualStrings("test", options.getString("name").?);
    try testing.expectEqual(@as(?bool, null), options.getBool("missing"));
}

test "Progress tracking" {
    const allocator = testing.allocator;

    var progress = Progress.init(allocator);
    defer progress.deinit();

    try progress.setTotal(5);
    try progress.setStep(0, "step1");
    try progress.completeStep(0);

    try testing.expectEqual(@as(f32, 0), progress.getPercentage());

    try progress.setStep(2, "step3");
    try testing.expectEqual(@as(f32, 40), progress.getPercentage());
}
