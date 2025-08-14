const std = @import("std");

const README_PATH = "README.md";
const DEMO_SECTION_HEADER = "## Demo";
const LICENSE_SECTION_HEADER = "## License";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Get demo output from stdin or from running the demo
    const demo_output = try getDemoOutput(allocator);
    defer allocator.free(demo_output);

    // Read current README
    const readme_content = try std.fs.cwd().readFileAlloc(allocator, README_PATH, 10 * 1024 * 1024);
    defer allocator.free(readme_content);

    // Update README with new demo section
    const updated_readme = try insertDemoSection(allocator, readme_content, demo_output);
    defer allocator.free(updated_readme);

    // Write back to README
    try std.fs.cwd().writeFile(.{ .sub_path = README_PATH, .data = updated_readme });

    std.debug.print("✓ README.md updated with demo output\n", .{});
}

fn getDemoOutput(allocator: std.mem.Allocator) ![]u8 {
    // First, try to read from stdin
    const stdin = std.io.getStdIn();
    if (!stdin.isTty()) {
        // Reading from pipe/redirect
        return try stdin.reader().readAllAlloc(allocator, 10 * 1024 * 1024);
    }

    // Otherwise, run the demo in non-interactive mode
    std.debug.print("Running demo in non-interactive mode...\n", .{});

    var child = std.process.Child.init(&.{ "./zig-out/bin/zz", "demo", "--non-interactive" }, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    try child.spawn();

    const stdout = try child.stdout.?.reader().readAllAlloc(allocator, 10 * 1024 * 1024);
    errdefer allocator.free(stdout);

    const stderr = try child.stderr.?.reader().readAllAlloc(allocator, 1024 * 1024);
    defer allocator.free(stderr);

    const result = try child.wait();

    if (result != .Exited or result.Exited != 0) {
        std.debug.print("Error running demo: {s}\n", .{stderr});
        return error.DemoFailed;
    }

    return stdout;
}

fn insertDemoSection(
    allocator: std.mem.Allocator,
    readme: []const u8,
    demo_output: []const u8,
) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    // Find the License section (where we'll insert before)
    const license_pos = std.mem.indexOf(u8, readme, LICENSE_SECTION_HEADER);
    if (license_pos == null) {
        std.debug.print("Warning: License section not found, appending demo at end\n", .{});
        try result.appendSlice(readme);
        try result.appendSlice("\n\n");
        try result.appendSlice(createDemoSection(demo_output));
        return result.toOwnedSlice();
    }

    // Check if Demo section already exists
    const demo_pos = std.mem.indexOf(u8, readme, DEMO_SECTION_HEADER);

    if (demo_pos != null and demo_pos.? < license_pos.?) {
        // Demo section exists, replace it

        // Copy everything before the demo section
        try result.appendSlice(readme[0..demo_pos.?]);

        // Add new demo section with header
        try result.appendSlice("## Demo\n\n");
        try result.appendSlice("Sample terminal session showcasing zz's capabilities:\n\n");
        try result.appendSlice(createDemoSection(demo_output));
        try result.appendSlice("\n\n");

        // Skip old demo section and copy from License onwards
        try result.appendSlice(readme[license_pos.?..]);
    } else {
        // Demo section doesn't exist, insert before License

        // Copy everything before License
        try result.appendSlice(readme[0..license_pos.?]);

        // Add demo section with header
        try result.appendSlice("## Demo\n\n");
        try result.appendSlice("Sample terminal session showcasing zz's capabilities:\n\n");
        try result.appendSlice(createDemoSection(demo_output));
        try result.appendSlice("\n\n");

        // Add License and everything after
        try result.appendSlice(readme[license_pos.?..]);
    }

    return result.toOwnedSlice();
}

fn createDemoSection(demo_output: []const u8) []const u8 {
    // The demo output is already formatted from the demo program,
    // but we need to ensure it has the proper section header.
    // If it starts with "# zz CLI Demo Output", we'll replace it with "## Demo"

    // Check if it starts with the demo header
    const demo_header = "# zz CLI Demo Output\n\n";
    if (std.mem.startsWith(u8, demo_output, demo_header)) {
        // Skip the original header, we'll add our own
        return demo_output[demo_header.len..];
    }

    return demo_output;
}

/// Find the end of a section in the README
fn findSectionEnd(content: []const u8, start_pos: usize) usize {
    // Look for the next section header (## ) or end of file
    var pos = start_pos;

    // Skip the current header line
    while (pos < content.len and content[pos] != '\n') : (pos += 1) {}
    if (pos < content.len) pos += 1;

    // Find next section or end
    while (pos < content.len) {
        if (pos + 3 < content.len and
            content[pos] == '#' and
            content[pos + 1] == '#' and
            content[pos + 2] == ' ')
        {
            // Found next section
            return pos;
        }

        // Move to next line
        while (pos < content.len and content[pos] != '\n') : (pos += 1) {}
        if (pos < content.len) pos += 1;
    }

    return content.len;
}
