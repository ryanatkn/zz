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

    // Add vendored tree-sitter bindings
    const tree_sitter_module = b.addModule("tree-sitter", .{
        .root_source_file = b.path("deps/zig-tree-sitter/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Build tree-sitter core library
    const tree_sitter_lib = b.addStaticLibrary(.{
        .name = "tree-sitter",
        .target = target,
        .optimize = optimize,
    });
    tree_sitter_lib.addCSourceFiles(.{
        .files = &.{
            "deps/tree-sitter/lib/src/lib.c",
        },
        .flags = &.{ "-std=c11", "-D_DEFAULT_SOURCE", "-D_BSD_SOURCE" },
    });
    tree_sitter_lib.addIncludePath(b.path("deps/tree-sitter/lib/include"));
    tree_sitter_lib.addIncludePath(b.path("deps/tree-sitter/lib/src"));
    tree_sitter_lib.linkLibC();

    // Add tree-sitter-zig grammar C library
    const tree_sitter_zig_lib = b.addStaticLibrary(.{
        .name = "tree-sitter-zig",
        .target = target,
        .optimize = optimize,
    });
    tree_sitter_zig_lib.addCSourceFile(.{
        .file = b.path("deps/tree-sitter-zig/src/parser.c"),
        .flags = &.{"-std=c11"},
    });
    tree_sitter_zig_lib.addIncludePath(b.path("deps/tree-sitter-zig/src"));
    tree_sitter_zig_lib.addIncludePath(b.path("deps/tree-sitter/lib/include"));
    tree_sitter_zig_lib.linkLibC();

    // Add tree-sitter-css grammar C library
    const tree_sitter_css_lib = b.addStaticLibrary(.{
        .name = "tree-sitter-css",
        .target = target,
        .optimize = optimize,
    });
    tree_sitter_css_lib.addCSourceFiles(.{
        .files = &.{
            "deps/tree-sitter-css/src/parser.c",
            "deps/tree-sitter-css/src/scanner.c",
        },
        .flags = &.{"-std=c11"},
    });
    tree_sitter_css_lib.addIncludePath(b.path("deps/tree-sitter-css/src"));
    tree_sitter_css_lib.addIncludePath(b.path("deps/tree-sitter/lib/include"));
    tree_sitter_css_lib.linkLibC();

    // Add tree-sitter-html grammar C library
    const tree_sitter_html_lib = b.addStaticLibrary(.{
        .name = "tree-sitter-html",
        .target = target,
        .optimize = optimize,
    });
    tree_sitter_html_lib.addCSourceFiles(.{
        .files = &.{
            "deps/tree-sitter-html/src/parser.c",
            "deps/tree-sitter-html/src/scanner.c",
        },
        .flags = &.{"-std=c11"},
    });
    tree_sitter_html_lib.addIncludePath(b.path("deps/tree-sitter-html/src"));
    tree_sitter_html_lib.addIncludePath(b.path("deps/tree-sitter/lib/include"));
    tree_sitter_html_lib.linkLibC();

    // Add tree-sitter-json grammar C library
    const tree_sitter_json_lib = b.addStaticLibrary(.{
        .name = "tree-sitter-json",
        .target = target,
        .optimize = optimize,
    });
    tree_sitter_json_lib.addCSourceFile(.{
        .file = b.path("deps/tree-sitter-json/src/parser.c"),
        .flags = &.{"-std=c11"},
    });
    tree_sitter_json_lib.addIncludePath(b.path("deps/tree-sitter-json/src"));
    tree_sitter_json_lib.addIncludePath(b.path("deps/tree-sitter/lib/include"));
    tree_sitter_json_lib.linkLibC();

    // Add tree-sitter-typescript grammar C library
    const tree_sitter_typescript_lib = b.addStaticLibrary(.{
        .name = "tree-sitter-typescript",
        .target = target,
        .optimize = optimize,
    });
    tree_sitter_typescript_lib.addCSourceFiles(.{
        .files = &.{
            "deps/tree-sitter-typescript/src/parser.c",
            "deps/tree-sitter-typescript/src/scanner.c",
        },
        .flags = &.{"-std=c11"},
    });
    tree_sitter_typescript_lib.addIncludePath(b.path("deps/tree-sitter-typescript/src"));
    tree_sitter_typescript_lib.addIncludePath(b.path("deps/tree-sitter/lib/include"));
    tree_sitter_typescript_lib.linkLibC();

    // Add tree-sitter-svelte grammar C library
    const tree_sitter_svelte_lib = b.addStaticLibrary(.{
        .name = "tree-sitter-svelte",
        .target = target,
        .optimize = optimize,
    });
    tree_sitter_svelte_lib.addCSourceFiles(.{
        .files = &.{
            "deps/tree-sitter-svelte/src/parser.c",
            "deps/tree-sitter-svelte/src/scanner.c",
        },
        .flags = &.{"-std=c11"},
    });
    tree_sitter_svelte_lib.addIncludePath(b.path("deps/tree-sitter-svelte/src"));
    tree_sitter_svelte_lib.addIncludePath(b.path("deps/tree-sitter/lib/include"));
    tree_sitter_svelte_lib.linkLibC();

    exe.root_module.addImport("tree-sitter", tree_sitter_module);
    exe.linkLibrary(tree_sitter_lib);
    exe.linkLibrary(tree_sitter_zig_lib);
    exe.linkLibrary(tree_sitter_css_lib);
    exe.linkLibrary(tree_sitter_html_lib);
    exe.linkLibrary(tree_sitter_json_lib);
    exe.linkLibrary(tree_sitter_typescript_lib);
    exe.linkLibrary(tree_sitter_svelte_lib);
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
    const benchmark_cmd = b.addSystemCommand(&.{ "sh", "-c", "./zig-out/bin/zz benchmark > benchmarks/latest.md && ./zig-out/bin/zz benchmark --format=pretty" });
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
    stdout_run.addArgs(&.{ "benchmark", "--format=pretty" });
    stdout_run.step.dependOn(b.getInstallStep());
    benchmark_stdout_step.dependOn(&stdout_run.step);
}

// Helper functions

fn addTestSteps(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    // Create tree-sitter module for tests
    const tree_sitter_module = b.addModule("tree-sitter", .{
        .root_source_file = b.path("deps/zig-tree-sitter/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Build tree-sitter core library for tests
    const tree_sitter_lib = b.addStaticLibrary(.{
        .name = "tree-sitter",
        .target = target,
        .optimize = optimize,
    });
    tree_sitter_lib.addCSourceFiles(.{
        .files = &.{
            "deps/tree-sitter/lib/src/lib.c",
        },
        .flags = &.{ "-std=c11", "-D_DEFAULT_SOURCE", "-D_BSD_SOURCE" },
    });
    tree_sitter_lib.addIncludePath(b.path("deps/tree-sitter/lib/include"));
    tree_sitter_lib.addIncludePath(b.path("deps/tree-sitter/lib/src"));
    tree_sitter_lib.linkLibC();

    // Build tree-sitter-zig grammar library for tests
    const tree_sitter_zig_lib = b.addStaticLibrary(.{
        .name = "tree-sitter-zig",
        .target = target,
        .optimize = optimize,
    });
    tree_sitter_zig_lib.addCSourceFile(.{
        .file = b.path("deps/tree-sitter-zig/src/parser.c"),
        .flags = &.{"-std=c11"},
    });
    tree_sitter_zig_lib.addIncludePath(b.path("deps/tree-sitter-zig/src"));
    tree_sitter_zig_lib.addIncludePath(b.path("deps/tree-sitter/lib/include"));
    tree_sitter_zig_lib.linkLibC();

    // Build tree-sitter-css grammar library for tests
    const tree_sitter_css_lib = b.addStaticLibrary(.{
        .name = "tree-sitter-css",
        .target = target,
        .optimize = optimize,
    });
    tree_sitter_css_lib.addCSourceFiles(.{
        .files = &.{
            "deps/tree-sitter-css/src/parser.c",
            "deps/tree-sitter-css/src/scanner.c",
        },
        .flags = &.{"-std=c11"},
    });
    tree_sitter_css_lib.addIncludePath(b.path("deps/tree-sitter-css/src"));
    tree_sitter_css_lib.addIncludePath(b.path("deps/tree-sitter/lib/include"));
    tree_sitter_css_lib.linkLibC();

    // Build tree-sitter-html grammar library for tests
    const tree_sitter_html_lib = b.addStaticLibrary(.{
        .name = "tree-sitter-html",
        .target = target,
        .optimize = optimize,
    });
    tree_sitter_html_lib.addCSourceFiles(.{
        .files = &.{
            "deps/tree-sitter-html/src/parser.c",
            "deps/tree-sitter-html/src/scanner.c",
        },
        .flags = &.{"-std=c11"},
    });
    tree_sitter_html_lib.addIncludePath(b.path("deps/tree-sitter-html/src"));
    tree_sitter_html_lib.addIncludePath(b.path("deps/tree-sitter/lib/include"));
    tree_sitter_html_lib.linkLibC();

    // Build tree-sitter-json grammar library for tests
    const tree_sitter_json_lib = b.addStaticLibrary(.{
        .name = "tree-sitter-json",
        .target = target,
        .optimize = optimize,
    });
    tree_sitter_json_lib.addCSourceFile(.{
        .file = b.path("deps/tree-sitter-json/src/parser.c"),
        .flags = &.{"-std=c11"},
    });
    tree_sitter_json_lib.addIncludePath(b.path("deps/tree-sitter-json/src"));
    tree_sitter_json_lib.addIncludePath(b.path("deps/tree-sitter/lib/include"));
    tree_sitter_json_lib.linkLibC();

    // Build tree-sitter-typescript grammar library for tests
    const tree_sitter_typescript_lib = b.addStaticLibrary(.{
        .name = "tree-sitter-typescript",
        .target = target,
        .optimize = optimize,
    });
    tree_sitter_typescript_lib.addCSourceFiles(.{
        .files = &.{
            "deps/tree-sitter-typescript/src/parser.c",
            "deps/tree-sitter-typescript/src/scanner.c",
        },
        .flags = &.{"-std=c11"},
    });
    tree_sitter_typescript_lib.addIncludePath(b.path("deps/tree-sitter-typescript/src"));
    tree_sitter_typescript_lib.addIncludePath(b.path("deps/tree-sitter/lib/include"));
    tree_sitter_typescript_lib.linkLibC();

    // Build tree-sitter-svelte grammar library for tests
    const tree_sitter_svelte_lib = b.addStaticLibrary(.{
        .name = "tree-sitter-svelte",
        .target = target,
        .optimize = optimize,
    });
    tree_sitter_svelte_lib.addCSourceFiles(.{
        .files = &.{
            "deps/tree-sitter-svelte/src/parser.c",
            "deps/tree-sitter-svelte/src/scanner.c",
        },
        .flags = &.{"-std=c11"},
    });
    tree_sitter_svelte_lib.addIncludePath(b.path("deps/tree-sitter-svelte/src"));
    tree_sitter_svelte_lib.addIncludePath(b.path("deps/tree-sitter/lib/include"));
    tree_sitter_svelte_lib.linkLibC();

    // All tests
    const test_all = b.addTest(.{
        .root_source_file = b.path("src/test.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_all.root_module.addImport("tree-sitter", tree_sitter_module);
    test_all.linkLibrary(tree_sitter_lib);
    test_all.linkLibrary(tree_sitter_zig_lib);
    test_all.linkLibrary(tree_sitter_css_lib);
    test_all.linkLibrary(tree_sitter_html_lib);
    test_all.linkLibrary(tree_sitter_json_lib);
    test_all.linkLibrary(tree_sitter_typescript_lib);
    test_all.linkLibrary(tree_sitter_svelte_lib);
    test_all.linkLibC();

    // Create test step
    const test_step = b.step("test", "Run all tests");

    // Run tests and show output
    const run_test = b.addRunArtifact(test_all);
    test_step.dependOn(&run_test.step);

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
