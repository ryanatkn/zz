const std = @import("std");

pub fn show(program_name: []const u8) void {
    std.debug.print("zz - CLI Utilities\n\n", .{});
    std.debug.print("Usage: {s} <command> [args...]\n\n", .{program_name});
    std.debug.print("Commands:\n", .{});
    std.debug.print("  tree [directory] [max_depth] [--format=FORMAT]\n", .{});
    std.debug.print("                                Show directory tree (defaults to current dir)\n", .{});
    std.debug.print("                                FORMAT: tree (default) or list\n", .{});
    std.debug.print("  prompt [files...] [options]  Build LLM prompts from files (supports globs)\n", .{});
    std.debug.print("                                Options:\n", .{});
    std.debug.print("                                  --prepend=TEXT       Add text before files\n", .{});
    std.debug.print("                                  --append=TEXT        Add text after files\n", .{});
    std.debug.print("                                  --allow-empty-glob   Warn instead of error for empty globs\n", .{});
    std.debug.print("                                  --allow-missing      Warn instead of error for all missing\n", .{});
    std.debug.print("  benchmark [options]           Run performance benchmarks\n", .{});
    std.debug.print("                                Options:\n", .{});
    std.debug.print("                                  --iterations=N       Number of iterations (default: 10000)\n", .{});
    std.debug.print("                                  --output=FILE        Write results to markdown file\n", .{});
    std.debug.print("                                  --compare=FILE       Compare with baseline file\n", .{});
    std.debug.print("                                  --save-baseline      Save as benchmarks/baseline.md\n", .{});
    std.debug.print("                                  --verbose            Show detailed output\n", .{});
    std.debug.print("                                  --path               Run path joining benchmarks\n", .{});
    std.debug.print("                                  --string-pool        Run string pool benchmarks\n", .{});
    std.debug.print("                                  --memory-pools       Run memory pool benchmarks\n", .{});
    std.debug.print("                                  --glob               Run glob pattern benchmarks\n", .{});
    std.debug.print("  help                          Show this help\n", .{});
    std.debug.print("\nGlob Patterns:\n", .{});
    std.debug.print("  *.zig                         Match all .zig files\n", .{});
    std.debug.print("  src/**/*.zig                  Recursive match\n", .{});
    std.debug.print("  *.{{zig,md}}                    Match multiple extensions\n", .{});
    std.debug.print("  log[0-9].txt                  Character classes\n", .{});
    std.debug.print("  file\\*.txt                    Escape special chars\n", .{});
}
