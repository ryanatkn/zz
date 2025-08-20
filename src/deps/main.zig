const std = @import("std");
const manager = @import("../lib/deps/manager.zig");
const config = @import("../lib/deps/config.zig");
const zon_parser = @import("../lib/languages/zon/mod.zig");
const FilesystemInterface = @import("../lib/filesystem/interface.zig").FilesystemInterface;
const Args = @import("../lib/args.zig").Args;
const io = @import("../lib/core/io.zig");
const reporting = @import("../lib/core/reporting.zig");
const docs = @import("../lib/deps/docs/mod.zig");

/// CLI entry point for dependency management
pub fn run(allocator: std.mem.Allocator, filesystem: FilesystemInterface, args: [][:0]const u8) !void {
    _ = filesystem; // Dependency management uses real filesystem directly

    // If no additional args beyond program and command name, show usage
    if (args.len <= 2) {
        try showUsage("zz");
        return;
    }

    // Parse command line options using existing Args utility
    var options = config.UpdateOptions{};
    var show_help = false;
    var deps_dir: []const u8 = "deps";

    // Skip the program name in args[0] and command name in args[1] ("deps")
    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        // Use existing Args utility for help parsing
        if (Args.isHelpFlag(arg)) {
            show_help = true;
        } else if (Args.isBoolFlag(arg, "update", null)) {
            // Default operation
        } else if (Args.isBoolFlag(arg, "check", null)) {
            options.check_only = true;
        } else if (Args.isBoolFlag(arg, "list", null)) {
            options.list_only = true;
        } else if (Args.isBoolFlag(arg, "dry-run", null)) {
            options.dry_run = true;
        } else if (Args.isBoolFlag(arg, "force", null)) {
            options.force_all = true;
        } else if (Args.isBoolFlag(arg, "verbose", "v")) {
            options.verbose = true;
        } else if (Args.isBoolFlag(arg, "no-color", null)) {
            options.color = false;
        } else if (Args.isBoolFlag(arg, "no-backup", null)) {
            options.backup = false;
        } else if (Args.isBoolFlag(arg, "generate-manifest", null)) {
            options.generate_docs = true;
        } else if (Args.parseFlag(arg, "force-dep", null)) |dep_name| {
            options.force_dep = dep_name;
        } else if (Args.parseFlag(arg, "update-pattern", null)) |pattern| {
            options.update_pattern = pattern;
        } else if (Args.parseFlag(arg, "deps-dir", null)) |dir| {
            deps_dir = dir;
        } else if (std.mem.startsWith(u8, arg, "--")) {
            try reporting.reportError("Unknown option: {s}", .{arg});
            try showUsage(args[0]);
            return;
        } else {
            try reporting.reportError("Unexpected argument: {s}", .{arg});
            try showUsage(args[0]);
            return;
        }
    }

    if (show_help) {
        try showDetailedHelp();
        return;
    }

    // Load dependencies configuration from deps.zon
    var deps_config = loadDepsConfig(allocator) catch |err| {
        try reporting.reportError("Failed to load dependency configuration", .{});
        return err;
    };
    defer deps_config.deinit(allocator);

    const dependencies = try deps_config.toDependencies(allocator);
    defer {
        for (dependencies) |*dep| {
            dep.deinit(allocator);
        }
        allocator.free(dependencies);
    }

    // Initialize dependency manager
    var dep_manager = manager.DependencyManager.init(allocator, deps_dir);

    // Execute the requested operation
    if (options.list_only) {
        try dep_manager.listDependencies(dependencies, options);
    } else if (options.check_only) {
        var result = try dep_manager.checkDependencies(dependencies);
        defer result.deinit();

        try printCheckResults(&result, options);

        // Exit with code 1 if updates are needed (CI-friendly)
        if (result.missing.items.len > 0 or result.need_update.items.len > 0) {
            std.process.exit(1);
        }
    } else if (options.generate_docs) {
        // Generate documentation only
        try generateDocumentationOnly(allocator, &dep_manager, dependencies);
    } else {
        // Update dependencies
        var result = try dep_manager.updateDependencies(dependencies, options);
        defer result.deinit();

        try printUpdateResults(&result, options);

        // Exit with code 1 if any dependencies failed
        if (result.failed.items.len > 0) {
            std.process.exit(1);
        }
    }
}

/// Load dependency configuration from deps.zon
fn loadDepsConfig(allocator: std.mem.Allocator) !config.DepsConfig {
    // ZON parsing now stable with dedicated parser

    // Read deps.zon file
    const deps_file_content = std.fs.cwd().readFileAlloc(allocator, "deps.zon", 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => {
            try reporting.reportError("deps.zon file not found in current directory", .{});
            return err;
        },
        else => return err,
    };
    defer allocator.free(deps_file_content);

    // Parse ZON content
    var zon_config = config.DepsZonConfig.parseFromZonContent(allocator, deps_file_content) catch |err| {
        try reporting.reportError("Failed to parse deps.zon: {}", .{err});
        return err;
    };
    defer zon_config.deinit();

    const deps_config = try zon_config.toDepsConfig(allocator);
    return deps_config;
}

/// Print results of check operation
fn printCheckResults(result: *const manager.CheckResult, options: config.UpdateOptions) !void {
    const stdout = std.io.getStdOut().writer();

    if (result.missing.items.len > 0) {
        if (options.color) {
            try stdout.writeAll("\x1b[31m"); // Red
        }
        try stdout.print("Missing dependencies: ", .{});
        for (result.missing.items, 0..) |dep, idx| {
            if (idx > 0) try stdout.writeAll(", ");
            try stdout.print("{s}", .{dep});
        }
        if (options.color) {
            try stdout.writeAll("\x1b[0m"); // Reset
        }
        try stdout.writeAll("\n");
    }

    if (result.need_update.items.len > 0) {
        if (options.color) {
            try stdout.writeAll("\x1b[33m"); // Yellow
        }
        try stdout.print("Dependencies needing updates: ", .{});
        for (result.need_update.items, 0..) |dep, idx| {
            if (idx > 0) try stdout.writeAll(", ");
            try stdout.print("{s}", .{dep});
        }
        if (options.color) {
            try stdout.writeAll("\x1b[0m"); // Reset
        }
        try stdout.writeAll("\n");
    }

    if (result.up_to_date.items.len > 0) {
        if (options.color) {
            try stdout.writeAll("\x1b[32m"); // Green
        }
        try stdout.print("Up-to-date dependencies: ", .{});
        for (result.up_to_date.items, 0..) |dep, idx| {
            if (idx > 0) try stdout.writeAll(", ");
            try stdout.print("{s}", .{dep});
        }
        if (options.color) {
            try stdout.writeAll("\x1b[0m"); // Reset
        }
        try stdout.writeAll("\n");
    }
}

/// Print results of update operation
fn printUpdateResults(result: *const manager.UpdateResult, options: config.UpdateOptions) !void {
    const stdout = std.io.getStdOut().writer();

    if (options.dry_run) {
        if (result.would_install.items.len + result.would_update.items.len == 0) {
            try stdout.writeAll("All dependencies are up to date! No actions needed.\n");
        } else {
            try stdout.writeAll("Summary of planned actions:\n");
            for (result.would_install.items) |dep| {
                try stdout.print("  • INSTALL {s}\n", .{dep});
            }
            for (result.would_update.items) |dep| {
                try stdout.print("  • UPDATE {s}\n", .{dep});
            }
            try stdout.writeAll("\nRun without --dry-run to execute these actions.\n");
        }
        return;
    }

    if (result.failed.items.len > 0) {
        if (options.color) {
            try stdout.writeAll("\x1b[31m"); // Red
        }
        try stdout.print("❌ {d} dependencies failed to update\n", .{result.failed.items.len});
        if (options.color) {
            try stdout.writeAll("\x1b[0m"); // Reset
        }
    }

    if (result.updated.items.len == 0 and result.failed.items.len == 0) {
        try reporting.reportSuccess("All dependencies already up to date! ✨", .{});
    } else {
        if (result.updated.items.len > 0) {
            if (options.color) {
                try stdout.writeAll("\x1b[32m"); // Green
            }
            try reporting.reportSuccess("✅ Updated {d} dependencies", .{result.updated.items.len});
            if (options.color) {
                try stdout.writeAll("\x1b[0m"); // Reset
            }
        }

        if (result.skipped.items.len > 0) {
            try stdout.print("  (Skipped {d} already up-to-date)\n", .{result.skipped.items.len});
        }
    }

    // Show next steps if dependencies were updated
    if (result.updated.items.len > 0) {
        try stdout.writeAll("\nNext steps:\n");
        try stdout.writeAll("  1. Review changes:  git diff deps/\n");
        try stdout.writeAll("  2. Test build:      zig build test\n");
        try stdout.writeAll("  3. Commit changes:  git add deps/ && git commit -m 'Update vendored dependencies'\n");
    }
}

/// Generate dependency documentation only (without updating)
fn generateDocumentationOnly(allocator: std.mem.Allocator, dep_manager: *manager.DependencyManager, dependencies: []const config.Dependency) !void {
    const stdout = std.io.getStdOut().writer();

    var doc_generator = docs.DocumentationGenerator.init(allocator, dep_manager.deps_dir);

    // Check if regeneration is needed
    const needs_regen = doc_generator.needsRegeneration() catch {
        // If we can't check, assume we need to regenerate
        try stdout.print("📦 Generating dependency documentation (change detection failed)...\n", .{});
        doc_generator.generateDocumentation(dependencies) catch |gen_err| {
            try reporting.reportError("  ✗ Failed to generate dependency documentation: {}", .{gen_err});
            return gen_err;
        };
        try reporting.reportSuccess("  ✓ Generated manifest.json", .{});
        return;
    };

    if (needs_regen) {
        try stdout.print("📦 Generating dependency documentation...\n", .{});

        doc_generator.generateDocumentation(dependencies) catch |err| {
            try reporting.reportError("  ✗ Failed to generate dependency documentation: {}", .{err});
            return err;
        };

        try reporting.reportSuccess("  ✓ Generated manifest.json", .{});
    } else {
        try reporting.reportInfo("📦 Dependency documentation up to date (no changes in deps.zon)", .{});
        try reporting.reportInfo("  ✓ Skipped manifest generation", .{});
    }
}

/// Show usage information
fn showUsage(program_name: []const u8) !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("Usage: {s} deps <command> [options]\n\n", .{program_name});
    try stdout.writeAll("Manage vendored dependencies declared in deps.zon\n\n");
    try stdout.writeAll("Commands:\n");
    try stdout.writeAll("  list                     List all dependencies and their status (default)\n");
    try stdout.writeAll("  check                    Check status without updating (CI-friendly)\n");
    try stdout.writeAll("  update                   Update all dependencies\n");
    try stdout.writeAll("\nOptions:\n");
    try stdout.writeAll("  --dry-run                Show what would be updated without doing it\n");
    try stdout.writeAll("  --force                  Force update even if up-to-date\n");
    try stdout.writeAll("  --force-dep=NAME         Force update specific dependency only\n");
    try stdout.writeAll("  --update-pattern=PATTERN Update dependencies matching pattern (glob)\n");
    try stdout.writeAll("  --no-backup              Disable automatic backups\n");
    try stdout.writeAll("  --no-color               Disable colored output\n");
    try stdout.writeAll("  --generate-manifest      Generate dependency manifest.json\n");
    try stdout.writeAll("  --verbose, -v            Enable verbose output\n");
    try stdout.writeAll("  --help, -h               Show this help\n");
}

/// Show detailed help
fn showDetailedHelp() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll("zz deps - Dependency Management\n\n");
    try stdout.writeAll("Manages vendored dependencies declared in deps.zon configuration file.\n\n");
    try stdout.writeAll("Features:\n");
    try stdout.writeAll("  • Idempotent operations - only updates when needed\n");
    try stdout.writeAll("  • Atomic updates with backup and rollback\n");
    try stdout.writeAll("  • Version tracking with .version files\n");
    try stdout.writeAll("  • Lock files to prevent concurrent updates\n");
    try stdout.writeAll("  • Colored output and progress indicators\n");
    try stdout.writeAll("  • Dry-run mode for safe previewing\n\n");
    try showUsage("zz");
    try stdout.writeAll("\nExamples:\n");
    try stdout.writeAll("  zz deps                             # List all dependencies (default)\n");
    try stdout.writeAll("  zz deps check                       # Check status (good for CI)\n");
    try stdout.writeAll("  zz deps update                      # Update all dependencies\n");
    try stdout.writeAll("  zz deps update --dry-run            # Preview what would change\n");
    try stdout.writeAll("  zz deps update --force              # Force update all deps\n");
    try stdout.writeAll("  zz deps update --force-dep=tree-sitter # Force update tree-sitter only\n");
    try stdout.writeAll("  zz deps update --update-pattern=\"tree*\" # Update all tree-sitter deps\n");
    try stdout.writeAll("  zz deps --generate-manifest         # Generate manifest.json only\n");
    try stdout.writeAll("\nConfiguration:\n");
    try stdout.writeAll("  Dependencies are declared in deps.zon at the project root.\n");
    try stdout.writeAll("  See existing deps.zon for configuration format.\n");
}
