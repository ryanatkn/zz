const std = @import("std");

/// Consistent error and status reporting utilities for CLI applications
/// Provides standardized message formatting across all zz commands

// Standard I/O writers
const stderr = std.io.getStdErr().writer();
const stdout = std.io.getStdOut().writer();

/// Report an error that prevents operation from continuing
/// Format: "Error: <message>"
pub fn reportError(comptime format: []const u8, args: anytype) !void {
    try stderr.print("Error: " ++ format ++ "\n", args);
}

/// Report a warning about an issue that doesn't prevent continuation
/// Format: "Warning: <message>"
pub fn reportWarning(comptime format: []const u8, args: anytype) !void {
    try stderr.print("Warning: " ++ format ++ "\n", args);
}

/// Report informational status (not an error or warning)
/// Format: "<message>" (no prefix)
pub fn reportInfo(comptime format: []const u8, args: anytype) !void {
    try stderr.print(format ++ "\n", args);
}

/// Report successful operation completion
/// Format: "<message>" (no prefix, to stdout)
pub fn reportSuccess(comptime format: []const u8, args: anytype) !void {
    try stdout.print(format ++ "\n", args);
}

/// Report debug/diagnostic information
/// Format: "<message>" (no prefix, to stderr for non-primary output)
pub fn reportDebug(comptime format: []const u8, args: anytype) !void {
    try stderr.print(format ++ "\n", args);
}

/// Print usage information (always to stderr after errors)
pub fn printUsage(comptime format: []const u8, args: anytype) !void {
    try stderr.print(format ++ "\n", args);
}
