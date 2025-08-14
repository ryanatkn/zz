const std = @import("std");

/// Show brief help (for -h flag)
pub fn showBrief(program_name: []const u8) void {
    std.debug.print("zz - CLI Utilities\n\n", .{});
    std.debug.print("Usage: {s} <command> [args...]\n\n", .{program_name});
    std.debug.print("Commands:\n", .{});
    std.debug.print("  tree [dir] [depth]    Show directory tree\n", .{});
    std.debug.print("  prompt [files...]     Build LLM prompts from files\n", .{});
    std.debug.print("  benchmark [options]   Run performance benchmarks\n", .{});
    std.debug.print("  format [files...]     Format code files\n", .{});
    std.debug.print("  help                  Show detailed help\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("Use '{s} --help' or '{s} help' for detailed information\n", .{program_name, program_name});
}

/// Show detailed help (for --help flag and help command)
pub fn show(program_name: []const u8) void {
    std.debug.print("zz - CLI Utilities\n\n", .{});
    std.debug.print("Usage: {s} <command> [args...]\n\n", .{program_name});
    std.debug.print("Commands:\n", .{});
    std.debug.print("  tree [directory] [max_depth] [options]\n", .{});
    std.debug.print("                                Show directory tree (defaults to current dir)\n", .{});
    std.debug.print("                                Options:\n", .{});
    std.debug.print("                                  --format=FORMAT, -f FORMAT   Output format: tree (default) or list\n", .{});
    std.debug.print("                                  --show-hidden                 Show hidden files\n", .{});
    std.debug.print("                                  --no-gitignore                Disable .gitignore parsing\n", .{});
    std.debug.print("  prompt [files...] [options]  Build LLM prompts with intelligent code extraction\n", .{});
    std.debug.print("                                Options:\n", .{});
    std.debug.print("                                  --prepend=TEXT       Add text before files\n", .{});
    std.debug.print("                                  --append=TEXT        Add text after files\n", .{});
    std.debug.print("                                  --allow-empty-glob   Warn instead of error for empty globs\n", .{});
    std.debug.print("                                  --allow-missing      Warn instead of error for all missing\n", .{});
    std.debug.print("                                Extraction flags (combine for custom extraction):\n", .{});
    std.debug.print("                                  --signatures         Extract function/method signatures\n", .{});
    std.debug.print("                                  --types              Extract type definitions\n", .{});
    std.debug.print("                                  --docs               Extract documentation comments\n", .{});
    std.debug.print("                                  --structure          Extract code structure\n", .{});
    std.debug.print("                                  --imports            Extract import statements\n", .{});
    std.debug.print("                                  --errors             Extract error handling code\n", .{});
    std.debug.print("                                  --tests              Extract test functions\n", .{});
    std.debug.print("                                  --full               Extract complete source (default)\n", .{});
    std.debug.print("  benchmark [options]           Run performance benchmarks (outputs to stdout)\n", .{});
    std.debug.print("                                Options:\n", .{});
    std.debug.print("                                  --format=FORMAT      Output format: markdown (default), json, csv, pretty\n", .{});
    std.debug.print("                                  --duration=TIME      Duration per benchmark (default: 2s, formats: 1s, 500ms)\n", .{});
    std.debug.print("                                  --baseline=FILE      Compare with baseline file (default: benchmarks/baseline.md)\n", .{});
    std.debug.print("                                  --no-compare         Disable automatic baseline comparison\n", .{});
    std.debug.print("                                  --only=path,string   Run only specific benchmarks (comma-separated)\n", .{});
    std.debug.print("                                  --skip=glob,memory   Skip specific benchmarks (comma-separated)\n", .{});
    std.debug.print("                                  --warmup             Include warmup phase\n", .{});
    std.debug.print("                                  --duration-multiplier=N  Extra multiplier for extending benchmark duration (default: 1.0)\n", .{});
    std.debug.print("                                Examples:\n", .{});
    std.debug.print("                                  zz benchmark                        # Markdown to stdout\n", .{});
    std.debug.print("                                  zz benchmark --format=pretty        # Pretty terminal output\n", .{});
    std.debug.print("                                  zz benchmark > baseline.md          # Save to file\n", .{});
    std.debug.print("                                  zz benchmark --only=path,string     # Run specific benchmarks\n", .{});
    std.debug.print("                                  zz benchmark --duration-multiplier=2    # 2x longer duration for all benchmarks\n", .{});
    std.debug.print("  format [files...] [options]  Format code files with language-aware pretty printing\n", .{});
    std.debug.print("                                Options:\n", .{});
    std.debug.print("                                  --write, -w          Format files in-place\n", .{});
    std.debug.print("                                  --check              Check if files are formatted (exit 1 if not)\n", .{});
    std.debug.print("                                  --stdin              Read from stdin, write to stdout\n", .{});
    std.debug.print("                                  --indent-size=N      Number of spaces for indentation (default: 4)\n", .{});
    std.debug.print("                                  --indent-style=STYLE Use spaces or tabs (default: space)\n", .{});
    std.debug.print("                                  --line-width=N       Maximum line width (default: 100)\n", .{});
    std.debug.print("                                Supported languages:\n", .{});
    std.debug.print("                                  Zig (using zig fmt), JSON, HTML, CSS, TypeScript (basic), Svelte (basic)\n", .{});
    std.debug.print("                                Examples:\n", .{});
    std.debug.print("                                  zz format src/*.zig --check         # Check if files are formatted\n", .{});
    std.debug.print("                                  zz format config.json --write       # Format file in-place\n", .{});
    std.debug.print("                                  echo '{{\"a\":1}}' | zz format --stdin  # Format stdin JSON\n", .{});
    std.debug.print("  help                          Show this help\n", .{});
    std.debug.print("\nGlob Patterns:\n", .{});
    std.debug.print("  *.zig                         Match all .zig files\n", .{});
    std.debug.print("  src/**/*.zig                  Recursive match\n", .{});
    std.debug.print("  *.{{zig,md}}                    Match multiple extensions\n", .{});
    std.debug.print("  log[0-9].txt                  Character classes\n", .{});
    std.debug.print("  file\\*.txt                    Escape special chars\n", .{});
}
