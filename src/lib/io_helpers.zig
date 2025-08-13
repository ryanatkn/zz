const std = @import("std");

/// I/O operations helper module to consolidate common output patterns
/// Provides buffered, error-handled, and POSIX-optimized I/O utilities
pub const IOHelpers = struct {

    // ============================================================================
    // Standard Output and Error Management
    // ============================================================================

    /// Buffered writer for stdout with automatic flushing
    pub const StdoutWriter = struct {
        writer: std.io.BufferedWriter(4096, std.fs.File.Writer),
        
        pub fn init() StdoutWriter {
            const stdout = std.io.getStdOut().writer();
            return StdoutWriter{
                .writer = std.io.bufferedWriter(stdout),
            };
        }
        
        pub fn write(self: *StdoutWriter, bytes: []const u8) !void {
            try self.writer.writer().writeAll(bytes);
        }
        
        pub fn print(self: *StdoutWriter, comptime format: []const u8, args: anytype) !void {
            try self.writer.writer().print(format, args);
        }
        
        pub fn flush(self: *StdoutWriter) !void {
            try self.writer.flush();
        }
        
        pub fn deinit(self: *StdoutWriter) void {
            self.flush() catch {};
        }
    };

    /// Buffered writer for stderr with automatic flushing
    pub const StderrWriter = struct {
        writer: std.io.BufferedWriter(4096, std.fs.File.Writer),
        
        pub fn init() StderrWriter {
            const stderr = std.io.getStdErr().writer();
            return StderrWriter{
                .writer = std.io.bufferedWriter(stderr),
            };
        }
        
        pub fn write(self: *StderrWriter, bytes: []const u8) !void {
            try self.writer.writer().writeAll(bytes);
        }
        
        pub fn print(self: *StderrWriter, comptime format: []const u8, args: anytype) !void {
            try self.writer.writer().print(format, args);
        }
        
        pub fn flush(self: *StderrWriter) !void {
            try self.writer.flush();
        }
        
        pub fn deinit(self: *StderrWriter) void {
            self.flush() catch {};
        }
    };

    // ============================================================================
    // Convenience Functions for Common Operations
    // ============================================================================

    /// Write to stdout with automatic flush (for simple cases)
    pub fn writeStdout(text: []const u8) !void {
        const stdout = std.io.getStdOut().writer();
        try stdout.writeAll(text);
    }

    /// Write to stderr with automatic flush (for simple cases)
    pub fn writeStderr(text: []const u8) !void {
        const stderr = std.io.getStdErr().writer();
        try stderr.writeAll(text);
    }

    /// Print to stdout with formatting
    pub fn printStdout(comptime format: []const u8, args: anytype) !void {
        const stdout = std.io.getStdOut().writer();
        try stdout.print(format, args);
    }

    /// Print to stderr with formatting
    pub fn printStderr(comptime format: []const u8, args: anytype) !void {
        const stderr = std.io.getStdErr().writer();
        try stderr.print(format, args);
    }

    // ============================================================================
    // Progress and Status Reporting
    // ============================================================================

    /// Simple progress reporter for terminal output
    pub const ProgressReporter = struct {
        total: usize,
        current: usize,
        last_percent: u8,
        writer: StdoutWriter,
        
        pub fn init(total: usize) ProgressReporter {
            return ProgressReporter{
                .total = total,
                .current = 0,
                .last_percent = 255, // Invalid percent to force first update
                .writer = StdoutWriter.init(),
            };
        }
        
        pub fn update(self: *ProgressReporter, current: usize) !void {
            self.current = current;
            const percent = if (self.total > 0) @as(u8, @intCast((current * 100) / self.total)) else 0;
            
            // Only update if percent changed (reduces flicker)
            if (percent != self.last_percent) {
                try self.writer.print("\rProgress: {d}% ({d}/{d})", .{ percent, current, self.total });
                try self.writer.flush();
                self.last_percent = percent;
            }
        }
        
        pub fn finish(self: *ProgressReporter) !void {
            try self.writer.write("\n");
            try self.writer.flush();
        }
        
        pub fn deinit(self: *ProgressReporter) void {
            self.writer.deinit();
        }
    };

    // ============================================================================
    // Color Output Support
    // ============================================================================

    /// ANSI color codes for terminal output
    pub const Colors = struct {
        pub const reset = "\x1b[0m";
        pub const bold = "\x1b[1m";
        pub const dim = "\x1b[2m";
        pub const red = "\x1b[31m";
        pub const green = "\x1b[32m";
        pub const yellow = "\x1b[33m";
        pub const blue = "\x1b[34m";
        pub const magenta = "\x1b[35m";
        pub const cyan = "\x1b[36m";
        pub const white = "\x1b[37m";
        pub const gray = "\x1b[90m";
        pub const bright_red = "\x1b[91m";
        pub const bright_green = "\x1b[92m";
        pub const bright_yellow = "\x1b[93m";
        pub const bright_blue = "\x1b[94m";
        pub const bright_magenta = "\x1b[95m";
        pub const bright_cyan = "\x1b[96m";
        pub const bright_white = "\x1b[97m";
    };

    /// Check if stdout supports colors (is a TTY)
    pub fn supportsColors() bool {
        return std.io.getStdOut().isTty();
    }

    /// Print colored text to stdout if colors are supported
    pub fn printColored(comptime color: []const u8, text: []const u8) !void {
        if (supportsColors()) {
            try printStdout("{s}{s}{s}", .{ color, text, Colors.reset });
        } else {
            try printStdout("{s}", .{text});
        }
    }

    /// Print colored text with formatting
    pub fn printColoredFmt(comptime color: []const u8, comptime format: []const u8, args: anytype) !void {
        if (supportsColors()) {
            try printStdout("{s}" ++ format ++ "{s}", .{color} ++ args ++ .{Colors.reset});
        } else {
            try printStdout(format, args);
        }
    }

    // ============================================================================
    // File Output Helpers
    // ============================================================================

    /// Safely write content to a file with error handling
    pub fn writeToFile(file_path: []const u8, content: []const u8) !void {
        const file = try std.fs.cwd().createFile(file_path, .{});
        defer file.close();
        
        try file.writeAll(content);
    }

    /// Append content to a file with error handling
    pub fn appendToFile(file_path: []const u8, content: []const u8) !void {
        const file = try std.fs.cwd().openFile(file_path, .{ .mode = .write_only });
        defer file.close();
        
        try file.seekFromEnd(0);
        try file.writeAll(content);
    }

    /// Write content to file with backup (creates .bak if file exists)
    pub fn safeWriteToFile(allocator: std.mem.Allocator, file_path: []const u8, content: []const u8) !void {
        // Check if file exists
        const file_exists = blk: {
            std.fs.cwd().access(file_path, .{}) catch break :blk false;
            break :blk true;
        };
        
        if (file_exists) {
            // Create backup
            const backup_path = try std.fmt.allocPrint(allocator, "{s}.bak", .{file_path});
            defer allocator.free(backup_path);
            
            try std.fs.cwd().copyFile(file_path, std.fs.cwd(), backup_path, .{});
        }
        
        // Write new content
        try writeToFile(file_path, content);
    }

    // ============================================================================
    // Stream Processing Helpers
    // ============================================================================

    /// Generic writer interface for abstraction
    pub fn GenericWriter(comptime WriterType: type) type {
        return struct {
            writer: WriterType,
            
            const Self = @This();
            
            pub fn init(writer: WriterType) Self {
                return Self{ .writer = writer };
            }
            
            pub fn write(self: *Self, bytes: []const u8) !void {
                try self.writer.writeAll(bytes);
            }
            
            pub fn print(self: *Self, comptime format: []const u8, args: anytype) !void {
                try self.writer.print(format, args);
            }
        };
    }

    /// Stream processor for line-by-line processing
    pub const LineProcessor = struct {
        allocator: std.mem.Allocator,
        buffer: std.ArrayList(u8),
        
        pub fn init(allocator: std.mem.Allocator) LineProcessor {
            return LineProcessor{
                .allocator = allocator,
                .buffer = std.ArrayList(u8).init(allocator),
            };
        }
        
        pub fn deinit(self: *LineProcessor) void {
            self.buffer.deinit();
        }
        
        /// Process input stream line by line, calling processor for each line
        pub fn processLines(
            self: *LineProcessor,
            reader: anytype,
            writer: anytype,
            comptime processor: fn ([]const u8) []const u8
        ) !void {
            while (true) {
                self.buffer.clearRetainingCapacity();
                reader.readUntilDelimiterArrayList(&self.buffer, '\n', 8192) catch |err| switch (err) {
                    error.EndOfStream => {
                        if (self.buffer.items.len > 0) {
                            const processed = processor(self.buffer.items);
                            try writer.writeAll(processed);
                        }
                        break;
                    },
                    else => return err,
                };
                
                const processed = processor(self.buffer.items);
                try writer.writeAll(processed);
                try writer.writeAll("\n");
            }
        }
    };

    // ============================================================================
    // Environment Variable Helpers
    // ============================================================================

    /// Get environment variable with default value
    pub fn getEnvVar(allocator: std.mem.Allocator, name: []const u8, default_value: []const u8) ![]u8 {
        return std.process.getEnvVarOwned(allocator, name) catch |err| switch (err) {
            error.EnvironmentVariableNotFound => try allocator.dupe(u8, default_value),
            else => err,
        };
    }

    /// Check if environment variable is set to truthy value
    pub fn isEnvVarTrue(allocator: std.mem.Allocator, name: []const u8) bool {
        const value = std.process.getEnvVarOwned(allocator, name) catch return false;
        defer allocator.free(value);
        
        return std.mem.eql(u8, value, "1") or 
               std.mem.eql(u8, value, "true") or 
               std.mem.eql(u8, value, "TRUE") or
               std.mem.eql(u8, value, "yes") or
               std.mem.eql(u8, value, "YES");
    }
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "stdout and stderr writers" {
    // Basic test to ensure writers can be created and used
    var stdout_writer = IOHelpers.StdoutWriter.init();
    defer stdout_writer.deinit();
    
    var stderr_writer = IOHelpers.StderrWriter.init();
    defer stderr_writer.deinit();
    
    // These would write to actual stdout/stderr in a real test
    // For unit tests, we just verify they can be called without panicking
}

test "progress reporter" {
    var reporter = IOHelpers.ProgressReporter.init(100);
    defer reporter.deinit();
    
    // Test progress updates
    try reporter.update(25);
    try reporter.update(50);
    try reporter.update(100);
    try reporter.finish();
}

test "color support detection" {
    // This will vary based on environment, just test it doesn't crash
    _ = IOHelpers.supportsColors();
}

test "environment variable helpers" {
    const allocator = testing.allocator;
    
    // Test getting env var with default
    const value = try IOHelpers.getEnvVar(allocator, "NONEXISTENT_VAR", "default");
    defer allocator.free(value);
    try testing.expectEqualStrings("default", value);
    
    // Test boolean env var detection
    try testing.expect(!IOHelpers.isEnvVarTrue(allocator, "NONEXISTENT_VAR"));
}

test "line processor" {
    const allocator = testing.allocator;
    
    var processor = IOHelpers.LineProcessor.init(allocator);
    defer processor.deinit();
    
    // Test line processing with simple transformation
    const input = "hello\nworld\n";
    var input_stream = std.io.fixedBufferStream(input);
    
    var output = std.ArrayList(u8).init(allocator);
    defer output.deinit();
    
    const TestProcessor = struct {
        fn process(line: []const u8) []const u8 {
            _ = line;
            return "processed";
        }
    };
    
    try processor.processLines(
        input_stream.reader(),
        output.writer(),
        TestProcessor.process
    );
    
    try testing.expectEqualStrings("processed\nprocessed\n", output.items);
}