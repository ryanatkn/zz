# zz - CLI Utilities

Fast command-line utilities written in Zig for POSIX systems. Currently features high-performance filesystem tree visualization and LLM prompt generation.

Performance is a top priority, and we dont care about backwards compat -
always try to get to the final best code. 

## Platform Support

- **Supported:** Linux, macOS, BSD, and other POSIX-compliant systems
- **Not Supported:** Windows (no plans for Windows support)
- All tests and features assume POSIX environment

## Environment

```bash
$ zig version
0.14.1
```

No external dependencies - pure Zig implementation.

## Project Structure

```
└── .
    ├── .claude [...]                  # Claude Code configuration directory
    ├── .git [...]                     # Git repository metadata  
    ├── .zig-cache [...]               # Zig build cache (filtered from tree output)
    ├── docs                           # Documentation
    │   └── glob-patterns.md           # Glob pattern documentation
    ├── src                            # Source code (modular architecture)
    │   ├── cli                        # CLI interface module (command parsing & execution)
    │   │   ├── args.zig               # Argument parsing utilities
    │   │   ├── command.zig            # Command enumeration and string parsing
    │   │   ├── help.zig               # Usage documentation and help text
    │   │   ├── main.zig               # CLI entry point and argument processing
    │   │   └── runner.zig             # Command dispatch and orchestration
    │   ├── prompt                     # Prompt generation module (LLM-optimized file aggregation)
    │   │   ├── test [...]             # Comprehensive test suite
    │   │   ├── builder.zig            # Core prompt building with smart fencing
    │   │   ├── config.zig             # Prompt-specific configuration
    │   │   ├── fence.zig              # Smart fence detection for code blocks
    │   │   ├── glob.zig               # Glob pattern expansion and matching
    │   │   ├── main.zig               # Prompt command entry point
    │   │   └── test.zig               # Test runner for prompt module
    │   ├── tree                       # Tree visualization module (high-performance directory traversal)
    │   │   ├── test [...]             # Comprehensive test suite
    │   │   ├── CLAUDE.md              # Detailed tree module documentation
    │   │   ├── config.zig             # Tree-specific configuration
    │   │   ├── entry.zig              # File/directory data structures
    │   │   ├── filter.zig             # Pattern matching and ignore logic
    │   │   ├── format.zig             # Output format enumeration (tree, list)
    │   │   ├── formatter.zig          # Multi-format output rendering
    │   │   ├── main.zig               # Tree command entry point
    │   │   ├── path_builder.zig       # Path manipulation utilities
    │   │   ├── test.zig               # Test runner for tree functionality
    │   │   └── walker.zig             # Core traversal algorithm with optimizations
    │   ├── config.zig                 # Shared configuration system (ZON parsing, patterns)
    │   ├── main.zig                   # Minimal application entry point
    │   └── test.zig                   # Main test runner for entire project
    ├── zig-out [...]                  # Build output directory (auto-generated)
    ├── .gitignore                     # Git ignore patterns
    ├── CLAUDE.md                      # AI assistant development documentation
    ├── README.md                      # User-facing documentation and usage guide
    ├── build.zig                      # Zig build system configuration
    ├── build.zig.zon                  # Package manifest
    └── zz.zon                         # CLI configuration (tree filtering patterns)
```

## Commands

```bash
# Build commands (default is Debug mode)
$ zig build                      # Debug build (default)
$ zig build -Doptimize=ReleaseFast  # Fast release build
$ zig build -Doptimize=ReleaseSafe  # Safe release (with runtime checks)
$ zig build -Doptimize=ReleaseSmall # Smallest binary size
$ zig build --use-llvm           # Use LLVM backend

# Run commands
$ zig build run -- tree [dir] [depth] [--format=FORMAT]  # Directory tree
$ zig build run -- prompt [files...] [options]           # Build LLM prompts
$ zig build run -- help                                  # Show available commands

# Or after building:
$ ./zig-out/bin/zz tree [dir] [depth] [--format=FORMAT]
$ ./zig-out/bin/zz prompt [files...] [options]
$ ./zig-out/bin/zz help

# Tree format options
$ zig build run -- tree --format=tree    # Tree format with box characters (default)
$ zig build run -- tree --format=list    # List format with ./path prefixes

# Prompt examples
$ zig build run -- prompt src/*.zig                           # Add all .zig files in src/
$ zig build run -- prompt "src/**/*.zig"                      # Recursive glob (quotes needed)
$ zig build run -- prompt --prepend="Context:" --append="Request:" src/*.zig # Add text before/after
$ zig build run -- prompt "*.{zig,md}" > prompt.md            # Multiple extensions, output to file
$ zig build run -- prompt --allow-empty-glob "*.rs" "*.zig"  # Warn if *.rs matches nothing
$ zig build run -- prompt --allow-missing file1.zig file2.zig # Warn if files don't exist
```

## Testing

```bash
$ zig build test              # Run all tests (recommended)
$ zig build test-tree         # Run tree module tests only
$ zig build test-prompt       # Run prompt module tests only

# Alternative: run tests directly
$ zig test src/test.zig        # Run all tests
$ zig test src/tree/test.zig   # Run tree module tests only
$ zig test src/prompt/test.zig # Run prompt module tests only
```

Comprehensive test suite covers configuration parsing, directory filtering, performance optimization, edge cases, and security patterns.

## Module Structure

**Core Architecture:**
- **CLI Module:** `src/cli/` - Command parsing, validation, and dispatch system
- **Tree Module:** `src/tree/` - High-performance directory traversal with configurable filtering and multiple output formats
- **Prompt Module:** `src/prompt/` - LLM prompt generation with glob support, smart fencing, and deduplication

**Key Components:**
- **Shared Configuration:** Root-level `zz.zon` with cross-cutting concerns (ignore patterns, hidden files, symlink behavior)
- **Performance Optimizations:** Early directory skip, memory management, efficient traversal
- **Modular Design:** Clean interfaces with shared utilities via `src/config.zig`

**Adding New Commands:**
1. Add to `Command` enum in `src/cli/command.zig`
2. Update parsing and help text
3. Add handler in `src/cli/runner.zig`  
4. Complex features get dedicated module with `run(allocator, args)` interface

## Configuration System

**Shared Configuration Architecture:**
- **Root-level config** in `zz.zon` - Single source of truth for cross-cutting concerns
- **`src/config.zig`** - Shared ZON parsing, pattern resolution, and DRY helper functions
- **Both tree and prompt modules** use the same underlying configuration system

**Configuration Format:**
```zon
.{
    // Base patterns behavior: "extend" (defaults + user) or provide custom array
    .base_patterns = "extend",
    
    // Additional patterns to ignore (added to defaults when base_patterns = "extend")
    .ignored_patterns = .{
        "logs",
        "custom_dir",
    },
    
    // Files to completely hide (not displayed at all)
    .hidden_files = .{
        "custom.hidden",
    },
    
    // Symlink behavior: "skip" (default), "follow", or "show"
    .symlink_behavior = "skip",
    
    // Command-specific overrides (optional)
    .tree = .{
        // Tree-specific settings go here if needed in future
    },
    
    .prompt = .{
        // Prompt-specific settings go here if needed in future
    },
}
```

**Pattern Resolution:**
- **"extend" mode:** Combines built-in defaults with your custom patterns
- **Custom array mode:** Use only your specified patterns, no defaults
- **Safe matching:** Exact path component matching prevents leaky substring matches
- **Default ignored patterns:** `.git`, `node_modules`, `.zig-cache`, `zig-out`, build directories, etc.
- **Default hidden files:** `.DS_Store`, `Thumbs.db`

**Cross-module DRY Helpers:**
- `shouldIgnorePath()` - Shared ignore logic for both tree and prompt
- `shouldHideFile()` - Shared file hiding logic  
- `handleSymlink()` - Shared symlink behavior

## Prompt Module Features

**Glob Pattern Support:**
- Basic wildcards: `*.zig`, `test?.zig`
- Recursive patterns: `src/**/*.zig`
- Alternatives: `*.{zig,md,txt}`
- Nested braces: `*.{zig,{md,txt}}` expands to `*.zig`, `*.md`, `*.txt`
- Character classes: `log[0-9].txt`, `file[a-zA-Z].txt`, `test[!0-9].txt`
- Escape sequences: `file\*.txt` matches literal `file*.txt`
- Hidden files: `.*` explicitly matches hidden files (`*` does not)
- Symlinks: Symlinks to files are followed
- Automatic deduplication of matched files

**Smart Code Fencing:**
- Automatically detects appropriate fence length
- Handles nested code blocks correctly
- Preserves syntax highlighting

**Output Format:**
- Markdown with semantic XML tags for LLM context
- File paths in structured `<File path="...">` tags
- Configurable ignore patterns via `zz.zon`

**Error Handling:**
- No default pattern: errors if no files specified (no auto `*.zig`)
- Strict by default: errors on missing files or empty globs
- `--allow-empty-glob`: Warnings for non-matching glob patterns
- `--allow-missing`: Warnings for all missing files
- Text-only mode: `--prepend` or `--append` without files is valid

## Tree Module Features

**Output Formats:**
- **Tree Format:** Traditional tree visualization with Unicode box characters
- **List Format:** Flat list with `./` path prefixes for easy parsing

**Performance Optimizations:**
- Early directory skip for ignored paths
- Efficient memory management with arena allocators
- Parallel directory traversal capability
- Smart filtering with .gitignore-style patterns

**Configuration:**
- Load from `zz.zon` for persistent settings
- Command-line arguments override config
- Sensible defaults for common use cases

## Code Style

- We want idiomatic Zig, taking more after C than C++
- Do not support backwards compatibility unless explicitly asked
- Never re-export in modules

## Notes to LLMs

- Focus on performance and clean architecture
- This is a CLI utilities project - no graphics or game functionality
- Never deprecate or preserve backwards compatibility unless explicitly requested
- Do not re-export identifiers from modules
- Test frequently with `zig build run` to ensure each step works
- Performance is top priority - optimize for speed
- Address duplicated code and antipatterns
- Push back against the developer when you think you are correct
    or have understanding they don't, and when in doubt, ask clarifying questions
- Keep modules self-contained and focused on their specific purpose
- We have `rg` (ripgrep) installed, so always prefer `rg` over `grep` and `find`
- Always update docs at ./CLAUDE.md and ./README.md
- Always include tests for new functionality and newly handled edge cases
    (and please don't cheat on tests lol,
    identify root causes and leave `// TODO` if you're stumped)
- Less is more - avoid over-engineering

**Current Status:** ✓ SharedConfig refactor completed successfully with performance optimization. All 158 tests passing (100% success rate). Both `tree` and `prompt` commands use shared configuration system with optimized pattern matching (3650ms performance vs original 4000ms regression).

## Test Coverage

The project has comprehensive test coverage including:
- **Edge cases**: Empty inputs, special characters, Unicode, long filenames
- **Security**: Path traversal, permission handling
- **Performance**: Large files, deep recursion, memory stress tests
- **Integration**: End-to-end command testing, format combinations
- **Glob patterns**: Wildcards, braces, recursive patterns, hidden files

Run all tests with: `zig test src/test.zig`

## Development Status

- **Configuration System**: ✓ SharedConfig refactor complete with optimized performance
- **Test Coverage**: ✓ 100% test success rate (158/158 tests passing)  
- **Performance**: ✓ Pattern matching optimized with fast/slow path split
- **Future Work**: See `REFACTORING_PLAN.md` for optional architecture improvements