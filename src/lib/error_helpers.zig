const std = @import("std");

/// Standardized error handling patterns to eliminate duplicate switch statements
pub const ErrorHelpers = struct {

    /// Result type for operations that may gracefully fail
    pub fn Result(comptime T: type) type {
        return union(enum) {
            success: T,
            not_found: void,
            access_denied: void,
            other_error: anyerror,

            pub fn isSuccess(self: @This()) bool {
                return std.meta.activeTag(self) == .success;
            }

            pub fn unwrap(self: @This()) !T {
                return switch (self) {
                    .success => |value| value,
                    .not_found => error.FileNotFound,
                    .access_denied => error.AccessDenied,
                    .other_error => |err| err,
                };
            }

            pub fn unwrapOr(self: @This(), default: T) T {
                return switch (self) {
                    .success => |value| value,
                    else => default,
                };
            }
        };
    }

    /// Execute file operation with standardized error handling
    pub fn safeFileOperation(comptime T: type, operation: anytype) Result(T) {
        const result = operation catch |err| switch (err) {
            error.FileNotFound => return Result(T){ .not_found = {} },
            error.AccessDenied => return Result(T){ .access_denied = {} },
            else => return Result(T){ .other_error = err },
        };
        return Result(T){ .success = result };
    }

    /// Execute directory operation with standardized error handling
    pub fn safeDirOperation(comptime T: type, operation: anytype) Result(T) {
        const result = operation catch |err| switch (err) {
            error.FileNotFound, error.NotDir => return Result(T){ .not_found = {} },
            error.AccessDenied => return Result(T){ .access_denied = {} },
            else => return Result(T){ .other_error = err },
        };
        return Result(T){ .success = result };
    }

    /// Graceful file opening - returns null instead of error for common cases
    pub fn gracefulOpenFile(file_path: []const u8, flags: std.fs.File.OpenFlags) ?std.fs.File {
        return std.fs.cwd().openFile(file_path, flags) catch |err| switch (err) {
            error.FileNotFound, error.AccessDenied, error.IsDir => null,
            else => {
                std.log.warn("Unexpected file error for {s}: {}", .{ file_path, err });
                return null;
            },
        };
    }

    /// Graceful directory opening - returns null instead of error for common cases  
    pub fn gracefulOpenDir(dir_path: []const u8, flags: std.fs.Dir.OpenFlags) ?std.fs.Dir {
        return std.fs.cwd().openDir(dir_path, flags) catch |err| switch (err) {
            error.FileNotFound, error.AccessDenied, error.NotDir => null,
            else => {
                std.log.warn("Unexpected directory error for {s}: {}", .{ dir_path, err });
                return null;
            },
        };
    }

    /// Graceful stat file operation
    pub fn gracefulStatFile(file_path: []const u8) ?std.fs.File.Stat {
        return std.fs.cwd().statFile(file_path) catch |err| switch (err) {
            error.FileNotFound, error.AccessDenied => null,
            else => {
                std.log.warn("Unexpected stat error for {s}: {}", .{ file_path, err });
                return null;
            },
        };
    }

    /// Handle filesystem errors with context logging
    pub fn handleFsError(err: anyerror, operation: []const u8, path: []const u8) void {
        switch (err) {
            error.FileNotFound => std.log.debug("{s} failed: file not found: {s}", .{ operation, path }),
            error.AccessDenied, error.PermissionDenied => std.log.warn("{s} failed: permission denied: {s}", .{ operation, path }),
            error.IsDir => std.log.debug("{s} failed: is directory: {s}", .{ operation, path }),
            error.NotDir => std.log.debug("{s} failed: not a directory: {s}", .{ operation, path }),
            error.SystemResources => std.log.warn("{s} failed: system resources exhausted: {s}", .{ operation, path }),
            error.FileBusy => std.log.warn("{s} failed: file busy: {s}", .{ operation, path }),
            else => std.log.err("{s} failed with unexpected error {}: {s}", .{ operation, err, path }),
        }
    }

    /// Convert common filesystem errors to user-friendly messages
    pub fn errorToMessage(err: anyerror) []const u8 {
        return switch (err) {
            error.FileNotFound => "File or directory not found",
            error.AccessDenied, error.PermissionDenied => "Permission denied",
            error.IsDir => "Expected file but found directory", 
            error.NotDir => "Expected directory but found file",
            error.SystemResources => "Insufficient system resources",
            error.FileBusy => "File is busy or locked",
            error.NoSpaceLeft => "No space left on device",
            error.PathAlreadyExists => "Path already exists",
            error.NameTooLong => "Path name too long",
            else => "Unknown filesystem error",
        };
    }

    /// Retry operation with exponential backoff
    pub fn retryOperation(
        comptime T: type, 
        operation: anytype, 
        max_retries: u32,
        base_delay_ms: u64
    ) !T {
        var retries: u32 = 0;
        var delay_ms = base_delay_ms;
        
        while (retries <= max_retries) {
            if (operation) |result| {
                return result;
            } else |err| switch (err) {
                error.FileBusy, error.SystemResources => {
                    if (retries == max_retries) return err;
                    std.time.sleep(delay_ms * std.time.ns_per_ms);
                    delay_ms *= 2; // Exponential backoff
                    retries += 1;
                },
                else => return err,
            }
        }
        
        return error.MaxRetriesExceeded;
    }
};

test "Result type basic functionality" {
    const testing = std.testing;
    
    // Test success case
    const success_result = ErrorHelpers.Result(i32){ .success = 42 };
    try testing.expect(success_result.isSuccess());
    try testing.expectEqual(@as(i32, 42), try success_result.unwrap());
    try testing.expectEqual(@as(i32, 42), success_result.unwrapOr(0));
    
    // Test not_found case
    const not_found_result = ErrorHelpers.Result(i32){ .not_found = {} };
    try testing.expect(!not_found_result.isSuccess());
    try testing.expectEqual(@as(i32, 0), not_found_result.unwrapOr(0));
    try testing.expectError(error.FileNotFound, not_found_result.unwrap());
}

test "safeFileOperation wrapper" {
    const testing = std.testing;
    
    // Test operation that would normally throw FileNotFound
    const result = ErrorHelpers.safeFileOperation(std.fs.File, std.fs.cwd().openFile("nonexistent.txt", .{}));
    try testing.expect(!result.isSuccess());
    try testing.expectError(error.FileNotFound, result.unwrap());
}

test "graceful file operations" {
    const testing = std.testing;
    
    // Test graceful file open returns null for non-existent file
    const file = ErrorHelpers.gracefulOpenFile("nonexistent.txt", .{});
    try testing.expect(file == null);
    
    // Test graceful stat returns null for non-existent file  
    const stat = ErrorHelpers.gracefulStatFile("nonexistent.txt");
    try testing.expect(stat == null);
}