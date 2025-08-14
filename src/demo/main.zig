const std = @import("std");
const terminal = @import("terminal.zig");
const runner = @import("runner.zig");
const steps = @import("steps.zig");
const formatter = @import("formatter.zig");

const DemoMode = enum {
    interactive,
    non_interactive,
    help,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Parse command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    
    const mode = parseArgs(args);
    
    switch (mode) {
        .interactive => try runInteractive(allocator),
        .non_interactive => try runNonInteractive(allocator),
        .help => try showHelp(),
    }
}

fn parseArgs(args: [][:0]u8) DemoMode {
    if (args.len > 1) {
        for (args[1..]) |arg| {
            if (std.mem.eql(u8, arg, "--non-interactive") or std.mem.eql(u8, arg, "-n")) {
                return .non_interactive;
            }
            if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
                return .help;
            }
        }
    }
    return .interactive;
}

fn showHelp() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll(
        \\zz Demo - Interactive demonstration of zz capabilities
        \\
        \\Usage:
        \\  zz-demo [options]
        \\
        \\Options:
        \\  --non-interactive, -n    Run in non-interactive mode (for README generation)
        \\  --help, -h              Show this help message
        \\
        \\Interactive mode:
        \\  - Shows colorful terminal output
        \\  - Pauses between steps
        \\  - Allows user to navigate through demo
        \\
        \\Non-interactive mode:
        \\  - Outputs clean text suitable for documentation
        \\  - No colors or pauses
        \\  - Suitable for piping to files
        \\
    );
}

fn runInteractive(allocator: std.mem.Allocator) !void {
    var term = terminal.Terminal.init(true);
    
    // Check if zz binary exists
    runner.checkZzBinary() catch {
        try term.printError("Error: zz binary not found. Please run 'zig build' first.\n");
        return;
    };
    
    // Clear screen and show header
    try term.clearScreen();
    try term.drawBox("zz CLI Terminal Demo", 60);
    try term.printInfo("\nFast Command-Line Utilities for POSIX Systems\n");
    try term.newline();
    
    // Introduction
    try term.printBold("This demo showcases zz's capabilities:\n");
    try term.print("• High-performance directory tree visualization\n", .{});
    try term.print("• Smart code extraction with language awareness\n", .{});
    try term.print("• LLM-optimized prompt generation\n", .{});
    try term.print("• Multiple output formats (tree, list)\n", .{});
    try term.print("• Gitignore integration\n", .{});
    
    try term.waitForEnter();
    try term.clearScreen();
    
    // Run through each demo step
    for (steps.demo_steps, 1..) |step, step_num| {
        try term.printStep(step_num, step.title);
        try term.printDim(step.description);
        try term.newline();
        
        // Show file preview if requested
        if (step.show_file_preview and step.file_to_preview != null) {
            try showFilePreview(&term, allocator, step.file_to_preview.?, step.preview_lines);
            try term.waitForKey("\nPress Enter to parse this file...");
            try term.newline();
        }
        
        // Format and display the command
        const cmd_line = try runner.formatCommandLine(allocator, step.command, step.args);
        defer allocator.free(cmd_line);
        try term.printCommand(cmd_line);
        try term.newline();
        
        // Execute the command with animation
        var result = try runner.executeCommandWithAnimation(allocator, step.command, step.args, &term);
        defer result.deinit();
        
        // Display the output (truncated if needed)
        if (step.max_lines) |max| {
            const truncated = try runner.truncateOutput(allocator, result.stdout, max);
            defer allocator.free(truncated);
            try term.printOutput(truncated);
        } else {
            try term.printOutput(result.stdout);
        }
        
        if (result.exit_code != 0 and result.stderr.len > 0) {
            try term.printError("Error output:\n");
            try term.printOutput(result.stderr);
        }
        
        try term.waitForEnter();
        
        // Clear for next step (except last one)
        if (step_num < steps.demo_steps.len) {
            try term.clearScreen();
        }
    }
    
    // Show summary
    try showSummary(&term);
}

fn runNonInteractive(allocator: std.mem.Allocator) !void {
    var term = terminal.Terminal.init(false);
    
    // Check if zz binary exists
    runner.checkZzBinary() catch {
        std.debug.print("Error: zz binary not found. Please run 'zig build' first.\n", .{});
        return;
    };
    
    // Simple header
    try term.print("# zz CLI Demo Output\n\n", .{});
    
    // Run through each demo step
    for (steps.demo_steps, 1..) |step, step_num| {
        // Print step header
        try term.print("## {}. {s}\n", .{ step_num, step.title });
        try term.print("{s}\n\n", .{step.description});
        
        // Format and display the command
        const cmd_line = try runner.formatCommandLine(allocator, step.command, step.args);
        defer allocator.free(cmd_line);
        try term.print("```console\n$ {s}\n", .{cmd_line});
        
        // Execute the command
        var result = try runner.executeCommand(allocator, step.command, step.args);
        defer result.deinit();
        
        // Display the output (truncated if needed)
        if (step.max_lines) |max| {
            const truncated = try runner.truncateOutput(allocator, result.stdout, max);
            defer allocator.free(truncated);
            try term.printOutput(truncated);
        } else {
            try term.printOutput(result.stdout);
        }
        
        try term.print("```\n\n", .{});
    }
    
    // Simple summary
    try term.print("## Summary\n\n", .{});
    try term.print("Key features demonstrated:\n", .{});
    for (steps.summary.features) |feature| {
        try term.print("- {s}\n", .{feature});
    }
    try term.newline();
    
    try term.print("Performance highlights:\n", .{});
    for (steps.summary.performance) |perf| {
        try term.print("- {s}: {s}\n", .{ perf.name, perf.value });
    }
}

fn showFilePreview(term: *terminal.Terminal, allocator: std.mem.Allocator, file_path: []const u8, preview_lines: usize) !void {
    const content = std.fs.cwd().readFileAlloc(allocator, file_path, 1024 * 1024) catch |err| {
        try term.printWarning("Could not read file for preview\n");
        std.debug.print("Error reading {s}: {}\n", .{ file_path, err });
        return;
    };
    defer allocator.free(content);
    
    try term.printInfo("Sample file: ");
    try term.print("{s}\n", .{file_path});
    try term.printDim("Showing first lines:\n\n");
    
    // Show first N lines
    var lines_shown: usize = 0;
    var iter = std.mem.tokenizeAny(u8, content, "\n");
    while (iter.next()) |line| {
        if (lines_shown >= preview_lines) {
            try term.printDim("...\n");
            break;
        }
        try term.print("{s}\n", .{line});
        lines_shown += 1;
    }
}

fn showSummary(term: *terminal.Terminal) !void {
    try term.newline();
    try term.drawBox("Demo Complete!", 60);
    try term.newline();
    
    try term.printSuccess("✓ Key Features Demonstrated:\n");
    for (steps.summary.features) |feature| {
        try term.print("  • {s}\n", .{feature});
    }
    try term.newline();
    
    try term.printInfo("Performance Highlights:\n");
    for (steps.summary.performance) |perf| {
        try term.print("  • {s}: {s}\n", .{ perf.name, perf.value });
    }
    try term.newline();
    
    try term.printDim("For more information, see README.md\n");
    try term.print("Repository: {s}\n", .{steps.summary.repository});
}