const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const use_llvm = b.option(bool, "use-llvm", "Use the LLVM backend");

    const exe = b.addExecutable(.{
        .name = "zz",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .use_llvm = use_llvm,
        .use_lld = use_llvm,
    });

    b.installArtifact(exe);

    // Run step
    const run_step = b.step("run", "Run the CLI");
    const run = b.addRunArtifact(exe);
    run.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run.addArgs(args);
    }
    run_step.dependOn(&run.step);

    // Test steps - all tests
    const test_all = b.addTest(.{
        .root_source_file = b.path("src/test.zig"),
        .target = target,
        .optimize = optimize,
    });

    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&b.addRunArtifact(test_all).step);

    // Test tree module only
    const test_tree = b.addTest(.{
        .root_source_file = b.path("src/tree/test.zig"),
        .target = target,
        .optimize = optimize,
    });

    const test_tree_step = b.step("test-tree", "Run tree module tests");
    test_tree_step.dependOn(&b.addRunArtifact(test_tree).step);

    // Test prompt module only
    const test_prompt = b.addTest(.{
        .root_source_file = b.path("src/prompt/test.zig"),
        .target = target,
        .optimize = optimize,
    });

    const test_prompt_step = b.step("test-prompt", "Run prompt module tests");
    test_prompt_step.dependOn(&b.addRunArtifact(test_prompt).step);
}