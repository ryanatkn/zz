const std = @import("std");
const string_helpers = @import("string_helpers.zig");

/// Error context helper module for enhanced error messages and debugging
/// Provides structured error information with file/line context and error chains
pub const ErrorContext = struct {

    // ============================================================================
    // Error Context Types
    // ============================================================================

    /// Enhanced error information with context
    pub const ContextualError = struct {
        error_code: anyerror,
        message: []const u8,
        file_path: ?[]const u8,
        line_number: ?u32,
        column_number: ?u32,
        context: ?[]const u8,
        
        pub fn deinit(self: *ContextualError, allocator: std.mem.Allocator) void {
            if (self.message.len > 0) allocator.free(self.message);
            if (self.file_path) |path| allocator.free(path);
            if (self.context) |ctx| allocator.free(ctx);
        }
    };

    /// Error chain for tracking nested errors
    pub const ErrorChain = struct {
        allocator: std.mem.Allocator,
        errors: std.ArrayList(ContextualError),
        
        pub fn init(allocator: std.mem.Allocator) ErrorChain {
            return ErrorChain{
                .allocator = allocator,
                .errors = std.ArrayList(ContextualError).init(allocator),
            };
        }
        
        pub fn deinit(self: *ErrorChain) void {
            for (self.errors.items) |*err| {
                err.deinit(self.allocator);
            }
            self.errors.deinit();
        }
        
        /// Add an error to the chain
        pub fn add(
            self: *ErrorChain, 
            error_code: anyerror, 
            message: []const u8,
            file_path: ?[]const u8,
            line_number: ?u32
        ) !void {
            const contextual_error = ContextualError{
                .error_code = error_code,
                .message = try self.allocator.dupe(u8, message),
                .file_path = if (file_path) |path| try self.allocator.dupe(u8, path) else null,
                .line_number = line_number,
                .column_number = null,
                .context = null,
            };
            try self.errors.append(contextual_error);
        }
        
        /// Add an error with additional context
        pub fn addWithContext(
            self: *ErrorChain,
            error_code: anyerror,
            message: []const u8,
            file_path: ?[]const u8,
            line_number: ?u32,
            context: []const u8
        ) !void {
            const contextual_error = ContextualError{
                .error_code = error_code,
                .message = try self.allocator.dupe(u8, message),
                .file_path = if (file_path) |path| try self.allocator.dupe(u8, path) else null,
                .line_number = line_number,
                .column_number = null,
                .context = try self.allocator.dupe(u8, context),
            };
            try self.errors.append(contextual_error);
        }
        
        /// Get a formatted error message for the entire chain
        pub fn formatChain(self: *const ErrorChain) ![]u8 {
            if (self.errors.items.len == 0) {
                return try self.allocator.dupe(u8, "No errors in chain");
            }
            
            var result = std.ArrayList(u8).init(self.allocator);
            errdefer result.deinit();
            
            for (self.errors.items, 0..) |err, i| {
                if (i > 0) {
                    try result.appendSlice("\nCaused by: ");
                }
                
                const formatted = try formatSingleError(self.allocator, err);
                defer self.allocator.free(formatted);
                try result.appendSlice(formatted);
            }
            
            return result.toOwnedSlice();
        }
    };

    // ============================================================================
    // Error Formatting Functions
    // ============================================================================

    /// Format a single error with context
    pub fn formatSingleError(allocator: std.mem.Allocator, err: ContextualError) ![]u8 {
        var parts = std.ArrayList([]const u8).init(allocator);
        defer parts.deinit();
        
        // Add error code and message
        const error_msg = try std.fmt.allocPrint(allocator, "{s}: {s}", .{ @errorName(err.error_code), err.message });
        try parts.append(error_msg);
        
        // Add file location if available
        if (err.file_path) |path| {
            const location = if (err.line_number) |line|
                try std.fmt.allocPrint(allocator, "  at {s}:{d}", .{ path, line })
            else
                try std.fmt.allocPrint(allocator, "  at {s}", .{path});
            try parts.append(location);
        }
        
        // Add context if available
        if (err.context) |context| {
            const context_msg = try std.fmt.allocPrint(allocator, "  context: {s}", .{context});
            try parts.append(context_msg);
        }
        
        // Join parts
        const result = try string_helpers.StringHelpers.join(allocator, "\n", parts.items);
        
        // Clean up intermediate allocations
        for (parts.items) |part| {
            allocator.free(part);
        }
        
        return result;
    }

    /// Create a user-friendly error message
    pub fn createUserFriendlyMessage(
        allocator: std.mem.Allocator,
        error_code: anyerror,
        operation: []const u8,
        file_path: ?[]const u8
    ) ![]u8 {
        const suggestion = getSuggestionForError(error_code, operation);
        
        if (file_path) |path| {
            return try std.fmt.allocPrint(allocator,
                "Error: Failed to {s} '{s}' - {s}\n{s}",
                .{ operation, path, @errorName(error_code), suggestion }
            );
        } else {
            return try std.fmt.allocPrint(allocator,
                "Error: Failed to {s} - {s}\n{s}",
                .{ operation, @errorName(error_code), suggestion }
            );
        }
    }

    /// Get helpful suggestions based on error type
    fn getSuggestionForError(error_code: anyerror, operation: []const u8) []const u8 {
        return switch (error_code) {
            error.FileNotFound => if (string_helpers.StringHelpers.contains(operation, "read"))
                "Suggestion: Check that the file exists and the path is correct."
            else
                "Suggestion: Check that the parent directory exists.",
                
            error.AccessDenied => "Suggestion: Check file permissions or run with appropriate privileges.",
            
            error.IsDir => "Suggestion: The path points to a directory, not a file.",
            
            error.NotDir => "Suggestion: The path contains a file where a directory was expected.",
            
            error.OutOfMemory => "Suggestion: The system is out of memory. Try closing other applications.",
            
            error.InvalidUtf8 => "Suggestion: The file contains invalid UTF-8 encoding. Check file encoding.",
            
            error.InvalidArgument => "Suggestion: Check that all arguments are valid.",
            
            else => "Suggestion: Review the operation and try again.",
        };
    }

    // ============================================================================
    // Convenience Macros and Functions
    // ============================================================================

    /// Wrap an operation with error context
    pub fn withContext(
        allocator: std.mem.Allocator,
        operation: anytype,
        context_message: []const u8,
        file_path: ?[]const u8,
        line_number: ?u32
    ) !@TypeOf(operation) {
        _ = line_number; // For future use in logging
        return operation catch |err| {
            const user_message = try createUserFriendlyMessage(
                allocator, 
                err, 
                context_message, 
                file_path
            );
            defer allocator.free(user_message);
            
            // Log the error (could be enhanced to use proper logging)
            std.debug.print("{s}\n", .{user_message});
            
            return err;
        };
    }

    /// Create an error result with context information
    pub fn createError(
        allocator: std.mem.Allocator,
        error_code: anyerror,
        message: []const u8,
        file_path: ?[]const u8,
        line_number: ?u32
    ) !ContextualError {
        return ContextualError{
            .error_code = error_code,
            .message = try allocator.dupe(u8, message),
            .file_path = if (file_path) |path| try allocator.dupe(u8, path) else null,
            .line_number = line_number,
            .column_number = null,
            .context = null,
        };
    }

    // ============================================================================
    // Debug and Diagnostic Helpers
    // ============================================================================

    /// Print error diagnostics with stack trace context
    pub fn printDiagnostics(
        allocator: std.mem.Allocator,
        error_code: anyerror,
        message: []const u8,
        file_path: ?[]const u8,
        line_number: ?u32
    ) !void {
        const diagnostic = try std.fmt.allocPrint(allocator,
            "DIAGNOSTIC: {s} at {s}:{?d}\nMessage: {s}\nError: {s}",
            .{
                if (file_path) |path| string_helpers.StringHelpers.basename(path) else "unknown",
                file_path orelse "unknown",
                line_number,
                message,
                @errorName(error_code)
            }
        );
        defer allocator.free(diagnostic);
        
        std.debug.print("{s}\n", .{diagnostic});
    }

    /// Extract meaningful information from error for logging
    pub const ErrorInfo = struct {
        name: []const u8,
        category: ErrorCategory,
        severity: ErrorSeverity,
        user_actionable: bool,
        
        pub const ErrorCategory = enum {
            filesystem,
            network,
            parsing,
            memory,
            logic,
            system,
            unknown,
        };
        
        pub const ErrorSeverity = enum {
            critical,
            err,
            warning,
            info,
        };
    };

    /// Classify an error for better handling
    pub fn classifyError(error_code: anyerror) ErrorInfo {
        const name = @errorName(error_code);
        
        return switch (error_code) {
            error.FileNotFound,
            error.AccessDenied,
            error.IsDir,
            error.NotDir,
            error.BadPathName => ErrorInfo{
                .name = name,
                .category = .filesystem,
                .severity = .err,
                .user_actionable = true,
            },
            
            error.OutOfMemory => ErrorInfo{
                .name = name,
                .category = .memory,
                .severity = .critical,
                .user_actionable = false,
            },
            
            error.InvalidUtf8,
            error.InvalidCharacter => ErrorInfo{
                .name = name,
                .category = .parsing,
                .severity = .err,
                .user_actionable = true,
            },
            
            error.ConnectionRefused,
            error.NetworkUnreachable => ErrorInfo{
                .name = name,
                .category = .network,
                .severity = .err,
                .user_actionable = true,
            },
            
            else => ErrorInfo{
                .name = name,
                .category = .unknown,
                .severity = .err,
                .user_actionable = false,
            },
        };
    }
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "error context creation and formatting" {
    const allocator = testing.allocator;
    
    // Test single error creation
    var err = try ErrorContext.createError(
        allocator,
        error.FileNotFound,
        "Could not open configuration file",
        "config.zon",
        42
    );
    defer err.deinit(allocator);
    
    // Test formatting
    const formatted = try ErrorContext.formatSingleError(allocator, err);
    defer allocator.free(formatted);
    
    try testing.expect(string_helpers.StringHelpers.contains(formatted, "FileNotFound"));
    try testing.expect(string_helpers.StringHelpers.contains(formatted, "config.zon"));
    try testing.expect(string_helpers.StringHelpers.contains(formatted, "42"));
}

test "error chain management" {
    const allocator = testing.allocator;
    
    var chain = ErrorContext.ErrorChain.init(allocator);
    defer chain.deinit();
    
    // Add multiple errors to chain
    try chain.add(error.FileNotFound, "Config file not found", "config.zon", 1);
    try chain.addWithContext(error.AccessDenied, "Permission denied", "config.zon", 1, "Reading configuration");
    
    // Format the chain
    const formatted = try chain.formatChain();
    defer allocator.free(formatted);
    
    try testing.expect(string_helpers.StringHelpers.contains(formatted, "FileNotFound"));
    try testing.expect(string_helpers.StringHelpers.contains(formatted, "Caused by"));
}

test "user-friendly error messages" {
    const allocator = testing.allocator;
    
    const message = try ErrorContext.createUserFriendlyMessage(
        allocator,
        error.FileNotFound,
        "read",
        "missing_file.txt"
    );
    defer allocator.free(message);
    
    try testing.expect(string_helpers.StringHelpers.contains(message, "Failed to read"));
    try testing.expect(string_helpers.StringHelpers.contains(message, "missing_file.txt"));
    try testing.expect(string_helpers.StringHelpers.contains(message, "Suggestion"));
}

test "error classification" {
    const fs_error = ErrorContext.classifyError(error.FileNotFound);
    try testing.expect(fs_error.category == .filesystem);
    try testing.expect(fs_error.user_actionable);
    
    const memory_error = ErrorContext.classifyError(error.OutOfMemory);
    try testing.expect(memory_error.category == .memory);
    try testing.expect(memory_error.severity == .critical);
}