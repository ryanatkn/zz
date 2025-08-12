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

    // Benchmark step
    const benchmark_step = b.step("benchmark", "Run performance benchmarks");
    const benchmark_run = b.addRunArtifact(exe);
    benchmark_run.addArg("benchmark");
    benchmark_run.step.dependOn(b.getInstallStep());
    benchmark_step.dependOn(&benchmark_run.step);
    
    // Benchmark save step - writes results to file
    const benchmark_save_step = b.step("benchmark-save", "Run benchmarks and save to benchmarks/latest.md");
    const save_run = b.addRunArtifact(exe);
    save_run.addArgs(&.{ "benchmark", "--output=benchmarks/latest.md" });
    save_run.step.dependOn(b.getInstallStep());
    benchmark_save_step.dependOn(&save_run.step);
    
    // Benchmark compare step - compares with baseline
    const benchmark_compare_step = b.step("benchmark-compare", "Compare benchmarks with baseline");
    const compare_run = b.addRunArtifact(exe);
    compare_run.addArgs(&.{ "benchmark", "--output=benchmarks/latest.md", "--compare=benchmarks/baseline.md" });
    compare_run.step.dependOn(b.getInstallStep());
    benchmark_compare_step.dependOn(&compare_run.step);
    
    // Benchmark baseline step - updates baseline
    const benchmark_baseline_step = b.step("benchmark-baseline", "Save current benchmarks as baseline");
    const baseline_run = b.addRunArtifact(exe);
    baseline_run.addArgs(&.{ "benchmark", "--output=benchmarks/baseline.md", "--save-baseline" });
    baseline_run.step.dependOn(b.getInstallStep());
    benchmark_baseline_step.dependOn(&baseline_run.step);
}

// Helper functions

fn addTestSteps(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    // All tests
    const test_all = b.addTest(.{
        .root_source_file = b.path("src/test.zig"),
        .target = target,
        .optimize = optimize,
    });
    const test_step = b.step("test", "Run all tests");
    const run_test = b.addRunArtifact(test_all);
    run_test.has_side_effects = true;
    test_step.dependOn(&run_test.step);

    // Tree module tests
    const test_tree = b.addTest(.{
        .root_source_file = b.path("src/tree/test.zig"),
        .target = target,
        .optimize = optimize,
    });
    const test_tree_step = b.step("test-tree", "Run tree module tests");
    test_tree_step.dependOn(&b.addRunArtifact(test_tree).step);

    // Prompt module tests
    const test_prompt = b.addTest(.{
        .root_source_file = b.path("src/prompt/test.zig"),
        .target = target,
        .optimize = optimize,
    });
    const test_prompt_step = b.step("test-prompt", "Run prompt module tests");
    test_prompt_step.dependOn(&b.addRunArtifact(test_prompt).step);
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
    
    // Create directory first
    const mkdir_step = b.addSystemCommand(&.{ "mkdir", "-p", install_dir });
    
    // Build the executable first
    const build_step = b.addInstallArtifact(exe, .{});
    build_step.step.dependOn(&mkdir_step.step);
    
    // Copy the built binary to the target location
    const copy_step = b.addSystemCommand(&.{ "cp", "./zig-out/bin/zz", target_path });
    copy_step.step.dependOn(&build_step.step);
    
    // Create feedback step
    const feedback_content = std.fmt.allocPrint(allocator, success_message_template, .{ 
        executable_name, install_dir, executable_name, executable_name, install_dir 
    }) catch @panic("OOM");
    
    const print_feedback = b.addSystemCommand(&.{ "printf", feedback_content });
    print_feedback.step.dependOn(&copy_step.step);
    
    return &print_feedback.step;
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