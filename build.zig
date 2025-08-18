const std = @import("std");

// Configuration constants
const default_install_prefix = "~/.zz";
const bin_subdir = "bin";
const executable_name = "zz";

const success_message_template =
    \\{s} installed successfully!
    \\
    \\Binary location: {s}/{s}
    \\
    \\To use {s} from anywhere, add this to your shell profile:
    \\export PATH="$PATH:{s}"
    \\
    \\Then reload your shell or run: source ~/.bashrc (or ~/.zshrc)
    \\
;

const already_uptodate_message_template =
    \\{s} is already up-to-date at {s}/{s}
    \\
    \\To use {s} from anywhere, add this to your shell profile:
    \\export PATH="$PATH:{s}"
    \\
    \\Then reload your shell or run: source ~/.bashrc (or ~/.zshrc)
    \\
;

pub fn build(b: *std.Build) void {
    // Build options
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const use_llvm = b.option(bool, "use-llvm", "Use the LLVM backend");
    const install_prefix = b.option([]const u8, "prefix", "Installation prefix (default: " ++ default_install_prefix ++ ")") orelse default_install_prefix;

    // Executable
    const exe = b.addExecutable(.{
        .name = executable_name,
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .use_llvm = use_llvm,
        .use_lld = use_llvm,
    });
    
    // Link libc for POSIX system calls
    exe.linkLibC();


    // Default build step (builds to zig-out/)
    b.installArtifact(exe);

    // Custom install step (installs to user location)
    const install_user_step = b.step("install-user", "Install zz to ~/.zz/bin (or custom --prefix)");
    install_user_step.dependOn(addCustomInstall(b, exe, install_prefix));

    // Run step
    const run_step = b.step("run", "Run the CLI");
    const run = b.addRunArtifact(exe);
    run.step.dependOn(b.getInstallStep());
    if (b.args) |args| run.addArgs(args);
    run_step.dependOn(&run.step);

    // Test steps
    addTestSteps(b, target, optimize);

    // Benchmark step - save to latest.md and compare
    const benchmark_step = b.step("benchmark", "Run benchmarks, save to latest.md, compare with baseline");
    const benchmark_cmd = b.addSystemCommand(&.{ "sh", "-c", "mkdir -p benchmarks && ./zig-out/bin/zz benchmark > benchmarks/latest.md && ./zig-out/bin/zz benchmark --format pretty" });
    benchmark_cmd.step.dependOn(b.getInstallStep());
    benchmark_step.dependOn(&benchmark_cmd.step);

    // Benchmark baseline step - saves new baseline
    const benchmark_baseline_step = b.step("benchmark-baseline", "Save current benchmarks as baseline");
    const baseline_cmd = b.addSystemCommand(&.{ "sh", "-c", "mkdir -p benchmarks && ./zig-out/bin/zz benchmark > benchmarks/baseline.md && echo 'Baseline saved to benchmarks/baseline.md'" });
    baseline_cmd.step.dependOn(b.getInstallStep());
    benchmark_baseline_step.dependOn(&baseline_cmd.step);

    // Benchmark stdout step - just show pretty output
    const benchmark_stdout_step = b.step("benchmark-stdout", "Run benchmarks and show pretty output");
    const stdout_run = b.addRunArtifact(exe);
    stdout_run.addArgs(&.{ "benchmark", "--format", "pretty" });
    stdout_run.step.dependOn(b.getInstallStep());
    benchmark_stdout_step.dependOn(&stdout_run.step);

    // Demo run step (interactive) - now uses main zz binary
    const demo_step = b.step("demo", "Run interactive demo");
    const demo_run = b.addRunArtifact(exe);
    demo_run.addArg("demo");
    demo_run.step.dependOn(b.getInstallStep());
    demo_step.dependOn(&demo_run.step);

    // Demo non-interactive step (for testing)
    const demo_ni_step = b.step("demo-non-interactive", "Run demo in non-interactive mode");
    const demo_ni_run = b.addRunArtifact(exe);
    demo_ni_run.addArgs(&.{ "demo", "--non-interactive" });
    demo_ni_run.step.dependOn(b.getInstallStep());
    demo_ni_step.dependOn(&demo_ni_run.step);

    // Update README step - now uses main zz binary directly
    const update_readme_step = b.step("update-readme", "Update README.md with demo output");

    // Generate demo output directly
    const update_readme_cmd = b.addSystemCommand(&.{ "sh", "-c", "./zig-out/bin/zz demo --non-interactive > demo_output.md" });
    update_readme_cmd.step.dependOn(b.getInstallStep());

    update_readme_step.dependOn(&update_readme_cmd.step);

    // Dependency management steps
    const deps_step = b.step("deps", "Manage vendored dependencies (interactive menu)");
    const deps_run = b.addRunArtifact(exe);
    deps_run.addArg("deps");
    if (b.args) |args| deps_run.addArgs(args);
    deps_run.step.dependOn(b.getInstallStep());
    deps_step.dependOn(&deps_run.step);

    const deps_update_step = b.step("deps-update", "Update all vendored dependencies");
    const deps_update_run = b.addRunArtifact(exe);
    deps_update_run.addArgs(&.{ "deps", "--update" });
    deps_update_run.step.dependOn(b.getInstallStep());
    deps_update_step.dependOn(&deps_update_run.step);

    const deps_check_step = b.step("deps-check", "Check dependency status (CI-friendly)");
    const deps_check_run = b.addRunArtifact(exe);
    deps_check_run.addArgs(&.{ "deps", "--check" });
    deps_check_run.step.dependOn(b.getInstallStep());
    deps_check_step.dependOn(&deps_check_run.step);

    const deps_list_step = b.step("deps-list", "List all dependencies with status");
    const deps_list_run = b.addRunArtifact(exe);
    deps_list_run.addArgs(&.{ "deps", "--list" });
    deps_list_run.step.dependOn(b.getInstallStep());
    deps_list_step.dependOn(&deps_list_run.step);

    const deps_dry_run_step = b.step("deps-dry-run", "Show what dependencies would be updated");
    const deps_dry_run_run = b.addRunArtifact(exe);
    deps_dry_run_run.addArgs(&.{ "deps", "--dry-run" });
    deps_dry_run_run.step.dependOn(b.getInstallStep());
    deps_dry_run_step.dependOn(&deps_dry_run_run.step);
}

// Helper functions

fn addTestSteps(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const test_filter = b.option([]const u8, "test-filter", "Run only tests matching this pattern");

    // All tests
    const test_all = b.addTest(.{
        .root_source_file = b.path("src/test.zig"),
        .target = target,
        .optimize = optimize,
        .filters = if (test_filter) |filter| &.{filter} else &.{},
    });
    
    // Link libc for tests (needed for POSIX system calls)
    test_all.linkLibC();

    // Create test step
    const test_step = b.step("test", "Run all tests");

    // Run tests with filtering feedback
    if (test_filter) |filter| {
        // Show filter being applied
        const filter_info_cmd = b.addSystemCommand(&.{ "echo", b.fmt("Filter: '{s}' (no output = no matches, exits 0 for now)", .{filter}) });
        test_step.dependOn(&filter_info_cmd.step);
        
        const run_test = b.addRunArtifact(test_all);
        run_test.step.dependOn(&filter_info_cmd.step);
        test_step.dependOn(&run_test.step);
    } else {
        // Normal test run without filter
        const run_test = b.addRunArtifact(test_all);
        test_step.dependOn(&run_test.step);
    }

    // Note: Individual module tests (test-tree, test-prompt, etc.) were removed
    // due to complexity with module imports creating circular dependencies.
    // Use 'zig build test' to run all tests, which works correctly and runs
    // all 206 tests including tree, prompt, and benchmark module tests.
}

fn addCustomInstall(b: *std.Build, exe: *std.Build.Step.Compile, prefix: []const u8) *std.Build.Step {
    const allocator = b.allocator;

    // Expand ~ to home directory
    const expanded_prefix = if (std.mem.startsWith(u8, prefix, "~"))
        expandHomeDirectory(allocator, prefix) catch prefix
    else
        b.dupe(prefix);

    // Create installation directory path
    const install_dir = std.fs.path.join(allocator, &.{ expanded_prefix, bin_subdir }) catch @panic("OOM");
    const target_path = std.fs.path.join(allocator, &.{ install_dir, executable_name }) catch @panic("OOM");
    const source_path = "./zig-out/bin/zz";

    // Create directory first
    const mkdir_step = b.addSystemCommand(&.{ "mkdir", "-p", install_dir });

    // Build the executable first
    const build_step = b.addInstallArtifact(exe, .{});
    build_step.step.dependOn(&mkdir_step.step);

    // Check if we need to copy and create appropriate feedback
    const install_script = std.fmt.allocPrint(allocator,
        \\if [ ! -f "{s}" ] || [ "{s}" -nt "{s}" ]; then
        \\  cp "{s}" "{s}"
        \\  printf '{s}'
        \\else
        \\  printf '{s}'
        \\fi
    , .{ target_path, source_path, target_path, source_path, target_path, std.fmt.allocPrint(allocator, success_message_template, .{ executable_name, install_dir, executable_name, executable_name, install_dir }) catch @panic("OOM"), std.fmt.allocPrint(allocator, already_uptodate_message_template, .{ executable_name, install_dir, executable_name, executable_name, install_dir }) catch @panic("OOM") }) catch @panic("OOM");

    const install_step = b.addSystemCommand(&.{ "sh", "-c", install_script });
    install_step.step.dependOn(&build_step.step);

    return &install_step.step;
}

fn expandHomeDirectory(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    if (!std.mem.startsWith(u8, path, "~")) return path;

    const home_dir = std.posix.getenv("HOME") orelse return path;

    if (path.len == 1) {
        // Just "~"
        return allocator.dupe(u8, home_dir);
    } else if (path[1] == '/') {
        // "~/ ..."
        return std.fmt.allocPrint(allocator, "{s}{s}", .{ home_dir, path[1..] });
    }

    // "~user" - not supported, return as-is
    return path;
}
