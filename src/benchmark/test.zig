const std = @import("std");
const main = @import("main.zig");

test "output format parsing" {
    const OutputFormat = main.OutputFormat;
    
    try std.testing.expect(OutputFormat.fromString("markdown") == .markdown);
    try std.testing.expect(OutputFormat.fromString("json") == .json);
    try std.testing.expect(OutputFormat.fromString("csv") == .csv);
    try std.testing.expect(OutputFormat.fromString("pretty") == .pretty);
    try std.testing.expect(OutputFormat.fromString("invalid") == null);
    try std.testing.expect(OutputFormat.fromString("") == null);
    try std.testing.expect(OutputFormat.fromString("MARKDOWN") == null); // case sensitive
}

test "benchmark module compiles" {
    // Ensure the main module compiles and exports are accessible
    _ = main.run;
    _ = main.OutputFormat;
    
    // If we get here, the module compiled successfully
    try std.testing.expect(true);
}