const std = @import("std");

/// Simplified error handling - idiomatic Zig with no wrapper types
/// Replaces error_helpers.zig with clean, simple patterns

// ============================================================================
// Error Classification
// ============================================================================

/// Check if error can be safely ignored (e.g., file not found)
pub fn isIgnorable(err: anyerror) bool {
    return switch (err) {
        error.FileNotFound,
        error.AccessDenied,
        error.NotDir,
        error.DirNotEmpty,
        error.IsDir,
        error.NotOpenForReading,
        error.NotOpenForWriting,
        error.InvalidUtf8,
        error.NameTooLong,
        error.SymLinkLoop,
        error.ProcessFdQuotaExceeded,
        error.SystemFdQuotaExceeded,
        error.NoDevice,
        error.NoSpaceLeft,
        error.PathAlreadyExists,
        error.DeviceBusy,
        error.FileTooBig,
        error.FileBusy,
        error.OperationAborted,
        error.BrokenPipe,
        error.ConnectionResetByPeer,
        error.ConnectionTimedOut,
        error.NotSupported,
        error.ProtocolFailure,
        error.ProtocolNotSupported,
        => true,
        else => false,
    };
}

/// Check if error is critical and must be propagated
pub fn isCritical(err: anyerror) bool {
    return switch (err) {
        error.OutOfMemory,
        error.SystemResources,
        error.Unexpected,
        error.InputOutput,
        error.StackOverflow,
        => true,
        else => false,
    };
}

/// Check if operation should be retried
pub fn shouldRetry(err: anyerror) bool {
    return switch (err) {
        error.SystemResources,
        error.ProcessFdQuotaExceeded,
        error.SystemFdQuotaExceeded,
        error.DeviceBusy,
        error.FileBusy,
        error.OperationAborted,
        error.ConnectionTimedOut,
        => true,
        else => false,
    };
}

/// Check if error is filesystem-related
pub fn isFilesystemError(err: anyerror) bool {
    return switch (err) {
        error.FileNotFound,
        error.AccessDenied,
        error.NotDir,
        error.IsDir,
        error.DirNotEmpty,
        error.PathAlreadyExists,
        error.NoSpaceLeft,
        error.FileTooBig,
        error.NameTooLong,
        error.SymLinkLoop,
        error.InvalidUtf8,
        error.NotOpenForReading,
        error.NotOpenForWriting,
        => true,
        else => false,
    };
}

/// Check if error is network-related
pub fn isNetworkError(err: anyerror) bool {
    return switch (err) {
        error.ConnectionRefused,
        error.ConnectionResetByPeer,
        error.ConnectionTimedOut,
        error.NetworkUnreachable,
        error.AddressNotAvailable,
        error.BrokenPipe,
        error.ProtocolFailure,
        error.ProtocolNotSupported,
        => true,
        else => false,
    };
}

/// Check if error is dependency-related
pub fn isDependencyError(err: anyerror) bool {
    return switch (err) {
        error.NoIncludeMatches,
        error.InvalidPattern,
        error.EmptyRepository,
        error.PatternValidationFailed,
        => true,
        else => false,
    };
}

// ============================================================================
// Error Messages
// ============================================================================

/// Get human-readable error message
pub fn getMessage(err: anyerror) []const u8 {
    return switch (err) {
        error.FileNotFound => "File not found",
        error.AccessDenied => "Access denied",
        error.OutOfMemory => "Out of memory",
        error.NotDir => "Not a directory",
        error.IsDir => "Is a directory",
        error.DirNotEmpty => "Directory not empty",
        error.PathAlreadyExists => "Path already exists",
        error.NoSpaceLeft => "No space left on device",
        error.FileTooBig => "File too big",
        error.NameTooLong => "Name too long",
        error.InvalidUtf8 => "Invalid UTF-8",
        error.SystemResources => "System resources exhausted",
        error.ConnectionRefused => "Connection refused",
        error.ConnectionResetByPeer => "Connection reset by peer",
        error.ConnectionTimedOut => "Connection timed out",
        error.NetworkUnreachable => "Network unreachable",
        error.BrokenPipe => "Broken pipe",
        error.Unexpected => "Unexpected error",
        error.NoIncludeMatches => "Include patterns did not match any files",
        error.InvalidPattern => "Invalid pattern syntax",
        error.EmptyRepository => "Repository contains no files",
        error.PatternValidationFailed => "Pattern validation failed",
        else => "Unknown error",
    };
}

/// Format error with context
pub fn format(allocator: std.mem.Allocator, err: anyerror, context: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}: {s}", .{ context, getMessage(err) });
}

// ============================================================================
// Common Error Handlers
// ============================================================================

/// Handle file operation errors with default behavior
pub fn handleFileError(err: anyerror) !void {
    if (isIgnorable(err)) {
        // Silently ignore
        return;
    }

    if (isCritical(err)) {
        // Must propagate
        return err;
    }

    // Log and continue
    std.debug.print("Warning: {s}\n", .{getMessage(err)});
}

/// Try operation with retry logic
pub fn tryWithRetry(
    comptime T: type,
    operation: anytype,
    max_retries: u32,
) !T {
    var retries: u32 = 0;

    while (retries < max_retries) : (retries += 1) {
        const result = operation() catch |err| {
            if (!shouldRetry(err) or retries == max_retries - 1) {
                return err;
            }

            // Wait before retry (exponential backoff)
            const delay_ms = std.math.pow(u32, 2, retries) * 100;
            std.time.sleep(delay_ms * std.time.ns_per_ms);
            continue;
        };

        return result;
    }

    return error.MaxRetriesExceeded;
}

// ============================================================================
// File Operation Helpers
// ============================================================================

/// Open file with graceful error handling
pub fn openFile(path: []const u8) !?std.fs.File {
    return std.fs.cwd().openFile(path, .{}) catch |err| {
        if (isIgnorable(err)) {
            return null;
        }
        return err;
    };
}

/// Create directory with graceful error handling
pub fn makeDir(path: []const u8) !void {
    std.fs.cwd().makePath(path) catch |err| {
        if (err == error.PathAlreadyExists) {
            return; // Already exists, that's fine
        }
        return err;
    };
}

/// Delete file with graceful error handling
pub fn deleteFile(path: []const u8) !void {
    std.fs.cwd().deleteFile(path) catch |err| {
        if (err == error.FileNotFound) {
            return; // Already gone, that's fine
        }
        return err;
    };
}

// ============================================================================
// Tests
// ============================================================================

test "error classification" {
    const testing = std.testing;

    try testing.expect(isIgnorable(error.FileNotFound));
    try testing.expect(isIgnorable(error.AccessDenied));
    try testing.expect(!isIgnorable(error.OutOfMemory));

    try testing.expect(isCritical(error.OutOfMemory));
    try testing.expect(isCritical(error.SystemResources));
    try testing.expect(!isCritical(error.FileNotFound));

    try testing.expect(shouldRetry(error.SystemResources));
    try testing.expect(shouldRetry(error.DeviceBusy));
    try testing.expect(!shouldRetry(error.FileNotFound));

    try testing.expect(isFilesystemError(error.FileNotFound));
    try testing.expect(isFilesystemError(error.NotDir));
    try testing.expect(!isFilesystemError(error.OutOfMemory));

    try testing.expect(isNetworkError(error.ConnectionRefused));
    try testing.expect(isNetworkError(error.BrokenPipe));
    try testing.expect(!isNetworkError(error.FileNotFound));

    try testing.expect(isDependencyError(error.NoIncludeMatches));
    try testing.expect(isDependencyError(error.InvalidPattern));
    try testing.expect(!isDependencyError(error.FileNotFound));
}

test "error messages" {
    const testing = std.testing;

    try testing.expectEqualStrings("File not found", getMessage(error.FileNotFound));
    try testing.expectEqualStrings("Out of memory", getMessage(error.OutOfMemory));
    try testing.expectEqualStrings("Include patterns did not match any files", getMessage(error.NoIncludeMatches));
    try testing.expectEqualStrings("Unknown error", getMessage(error.InvalidCharacter));
}

test "error formatting" {
    const testing = std.testing;

    const msg = try format(testing.allocator, error.FileNotFound, "config.json");
    defer testing.allocator.free(msg);

    try testing.expectEqualStrings("config.json: File not found", msg);
}

test "file operations" {
    const testing = std.testing;

    // Test opening non-existent file
    const file = try openFile("non_existent_file.txt");
    try testing.expect(file == null);

    // Test creating directory that may already exist
    try makeDir("/tmp/test_dir");
    try makeDir("/tmp/test_dir"); // Should not error

    // Test deleting non-existent file
    try deleteFile("/tmp/non_existent_file.txt"); // Should not error
}
