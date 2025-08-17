# Dependency Overview

This document explains the purpose and relationship of each vendored dependency in the `deps/` directory.

## Dependencies

### 1. tree-sitter (`deps/tree-sitter/`)
- **What it is**: The core tree-sitter parsing library written in C
- **Purpose**: Provides the foundational parsing engine for language-aware code analysis
- **Key files**:
  - `lib/src/lib.c` - Core parser implementation
  - `lib/include/tree_sitter/api.h` - C API headers
- **How we use it**: Compile as a static C library and link to our Zig code

### 2. zig-tree-sitter (`deps/zig-tree-sitter/`)
- **What it is**: Official Zig bindings to the tree-sitter C library
- **Purpose**: Provides idiomatic Zig interfaces to tree-sitter's C API
- **Key files**:
  - `src/root.zig` - Main Zig module with Parser, Tree, Node, Query types
  - `src/*.zig` - Individual Zig wrappers for tree-sitter types
- **How we use it**: Import as a Zig module named "tree-sitter"
- **Note**: This is NOT a grammar, it's the Zig language bindings to tree-sitter

### 3. tree-sitter-zig (`deps/tree-sitter-zig/`)
- **What it is**: A tree-sitter grammar for parsing Zig source code
- **Purpose**: Enables parsing of Zig language files into AST
- **Key files**:
  - `src/parser.c` - Generated C parser for Zig language
  - `src/tree_sitter/parser.h` - Parser header
  - `queries/*.scm` - Tree-sitter query patterns for syntax highlighting
  - `grammar.js` - Grammar definition (source, not used at runtime)
- **How we use it**: Compile as a static C library that provides `tree_sitter_zig()` function
- **Note**: This is a GRAMMAR (language definition), not bindings

### 4. tree-sitter-css (`deps/tree-sitter-css/`)
- **What it is**: A tree-sitter grammar for parsing CSS files
- **Purpose**: Enables parsing of CSS stylesheets into AST
- **Key files**:
  - `src/parser.c` - Generated C parser for CSS language
  - `src/scanner.c` - Custom scanner for CSS-specific lexing
  - `queries/highlights.scm` - Syntax highlighting patterns
- **How we use it**: Compile as a static C library that provides `tree_sitter_css()` function
- **Note**: Supports modern CSS including variables, media queries, and complex selectors

### 5. tree-sitter-html (`deps/tree-sitter-html/`)
- **What it is**: A tree-sitter grammar for parsing HTML files
- **Purpose**: Enables parsing of HTML documents into AST
- **Key files**:
  - `src/parser.c` - Generated C parser for HTML language
  - `src/scanner.c` - Custom scanner for HTML-specific lexing
  - `src/tag.h` - HTML tag definitions
  - `queries/highlights.scm` - Syntax highlighting patterns
  - `queries/injections.scm` - Language injection patterns for embedded scripts/styles
- **How we use it**: Compile as a static C library that provides `tree_sitter_html()` function
- **Note**: Supports HTML5, custom elements, and language injections

### 6. tree-sitter-json (`deps/tree-sitter-json/`)
- **What it is**: A tree-sitter grammar for parsing JSON files
- **Purpose**: Enables parsing of JSON data into AST
- **Key files**:
  - `src/parser.c` - Generated C parser for JSON language
  - `queries/highlights.scm` - Syntax highlighting patterns
- **How we use it**: Compile as a static C library that provides `tree_sitter_json()` function
- **Note**: Strictly validates JSON syntax, supports all JSON data types

### 7. tree-sitter-svelte (`deps/tree-sitter-svelte/`)
- **What it is**: A tree-sitter grammar for parsing Svelte components
- **Purpose**: Enables parsing of Svelte single-file components into AST
- **Key files**:
  - `src/parser.c` - Generated C parser for Svelte language
  - `src/scanner.c` - Custom scanner for Svelte-specific lexing
  - `src/tag.h` - Svelte tag definitions
  - `queries/highlights.scm` - Syntax highlighting patterns
  - `queries/injections.scm` - Language injection for script/style sections
- **How we use it**: Compile as a static C library that provides `tree_sitter_svelte()` function
- **Note**: Supports Svelte's template syntax, reactive statements, and multi-section components

### 8. tree-sitter-typescript (`deps/tree-sitter-typescript/`)
- **What it is**: A tree-sitter grammar for parsing TypeScript files
- **Purpose**: Enables parsing of TypeScript code into AST
- **Key files**:
  - `src/parser.c` - Generated C parser for TypeScript language
  - `src/scanner.c` - Custom scanner for TypeScript-specific lexing
  - `grammar.js` - Grammar definition
- **How we use it**: Compile as a static C library that provides `tree_sitter_typescript()` function
- **Note**: Supports TypeScript syntax including types, interfaces, generics (no TSX/JSX support)

### 9. zig-spec (`deps/zig-spec/`)
- **What it is**: Official Zig language specification
- **Purpose**: Reference for Zig language syntax and semantics
- **Key files**:
  - `grammar/grammar.peg` - PEG grammar for Zig
  - `grammar/tests/` - Test files covering Zig language features
- **How we use it**: Documentation reference only, not compiled or linked
- **Note**: tree-sitter-zig is based on this specification

## Relationship Diagram

```
                    ┌──────────────────┐
                    │   tree-sitter    │
                    │   (C library)     │
                    └────────┬─────────┘
                             │
                    ┌────────▼─────────┐
                    │ zig-tree-sitter  │
                    │ (Zig bindings)   │
                    └────────┬─────────┘
                             │
                    ┌────────▼─────────┐
                    │   Our Zig Code   │
                    │ (lib/language/)  │
                    └────────┬─────────┘
                             │
        ┌────────────────────┼────────────────────┐
        │                    │                    │
        ▼                    ▼                    ▼
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│ Language     │    │ Language     │    │ Language     │
│ Grammars:    │    │ Grammars:    │    │ Grammars:    │
├──────────────┤    ├──────────────┤    ├──────────────┤
│ • CSS        │    │ • HTML       │    │ • Svelte     │
│ • JSON       │    │ • TypeScript │    │ • Zig        │
└──────────────┘    └──────────────┘    └──────────────┘
                             
                    ┌──────────────┐
                    │   zig-spec   │
                    │ (reference)  │
                    └──────────────┘
```

Each grammar provides a `tree_sitter_{language}()` function that returns
a language parser, which our code uses to parse files of that type.

## Build Process

1. **Core Libraries**:
   - **tree-sitter**: Compiled as static C library (core parsing engine)
   - **zig-tree-sitter**: Used as Zig module (imported, not compiled separately)

2. **Language Grammars** (all compiled as static C libraries):
   - **tree-sitter-css**: Provides `tree_sitter_css()` extern function
   - **tree-sitter-html**: Provides `tree_sitter_html()` extern function  
   - **tree-sitter-json**: Provides `tree_sitter_json()` extern function
   - **tree-sitter-svelte**: Provides `tree_sitter_svelte()` extern function
   - **tree-sitter-typescript**: Provides `tree_sitter_typescript()` extern function
   - **tree-sitter-zig**: Provides `tree_sitter_zig()` extern function

3. **Our Code Integration**:
   - Imports zig-tree-sitter as "tree-sitter" module
   - Links all C libraries (tree-sitter core + all language grammars)
   - Dynamically selects appropriate `tree_sitter_{language}()` based on file extension
   - Uses unified AST visitor pattern for all languages

## Common Confusion Points

- **zig-tree-sitter** is NOT a grammar - it's Zig bindings to tree-sitter
- **tree-sitter-zig** is NOT Zig bindings - it's a grammar for parsing Zig code
- The naming is confusing but follows tree-sitter conventions:
  - `{language}-tree-sitter` = language bindings TO tree-sitter
  - `tree-sitter-{language}` = tree-sitter grammar FOR that language

## Why We Vendor These

- **Reliability**: No network dependencies at build time
- **Reproducibility**: Exact versions locked
- **Compatibility**: We know these versions work together (ABI v15)
- **Simplicity**: No complex package management needed

## Integration with Dependency Management System

The `deps/` directory is managed by our type-safe dependency management system in `src/lib/deps/` and the `zz deps` command.

### Automated Documentation Generation

The dependency system now includes automated documentation generation that creates up-to-date reference files:

- **`deps/DEPS.md`** - Human-readable dependency documentation automatically generated by `zz deps`
- **`deps/manifest.json`** - Machine-readable dependency manifest for programmatic access

These files are automatically updated whenever dependencies are modified via `zz deps` operations, or can be generated on-demand with:

```bash
zz deps --generate-docs
```

The generated documentation includes:
- Dependency categorization (core libraries, language grammars, reference docs)
- Current versions and repository links
- Build integration details extracted from `build.zig`
- Language-specific information for grammar dependencies
- Purpose descriptions from metadata in `deps.zon`

### Configuration: deps.zon

All dependencies are defined in the root `deps.zon` file:

```zon
.{
    .dependencies = .{
        .@"tree-sitter" = .{
            .url = "https://github.com/tree-sitter/tree-sitter.git",
            .version = "v0.25.0",
            .include = .{},
            .exclude = .{ "build.zig", "build.zig.zon", "test/", "script/", "*.md" },
            .preserve_files = .{},
            .patches = .{},
            // Optional metadata for documentation generation
            .category = "core",
            .purpose = "Core tree-sitter parsing engine written in C",
        },
        // ... other dependencies
    },
}
```

### Dependency Management Architecture

The system consists of several key modules in `src/lib/deps/`:

#### Core Modules

**`manager.zig`** - Main orchestration logic
- `DependencyManager` struct coordinates all operations
- Handles update workflows with atomic operations
- Provides status checking and dependency listing
- Integrates with filesystem abstraction for testing

**`config.zig`** - Configuration parsing and validation
- Parses `deps.zon` file into structured data
- Validates dependency definitions
- Manages memory for configuration objects
- Provides fallback hardcoded config if parsing fails

**`versioning.zig`** - Version comparison and update detection
- Semantic version parsing and comparison
- Reads `.version` files in each dependency directory
- Determines if updates are needed
- Integrates with filesystem abstraction

**`operations.zig`** - Atomic file operations
- Backup and rollback capabilities for safe updates
- Directory tree operations (copy, delete, move)
- Atomic file writes with temporary files
- Error recovery and cleanup

**`lock.zig`** - Concurrency control
- PID-based locks prevent concurrent updates
- POSIX-portable lock management
- Graceful handling of stale locks
- Automatic cleanup on process exit

**`git.zig`** - Git operations wrapper
- Repository cloning and fetching
- Commit hash resolution
- Tag and branch checkout
- Clean workspace management

### Version Tracking

Each dependency directory contains a `.version` file tracking current state:

```
Repository: https://github.com/tree-sitter/tree-sitter.git
Version: v0.25.0
Commit: a8a8b8b9c9d9e9f9a8a8b8b9c9d9e9f9a8a8b8b9
Updated: 1692123456
Updated-By: zz-deps-v1.0.0
```

This enables:
- **Update detection**: Compare current vs available versions
- **Rollback capability**: Track what was installed
- **Audit trail**: Know when and how dependencies were updated
- **Version consistency**: Ensure all dependencies match expected versions

### Command Workflow

#### Status Checking (`zz deps --list`)

```
╔══════════════════════════════════════════════════════╗
║                   Dependencies                        ║
╠════════════════╦═════════════╦═══════════════════════╣
║ tree-sitter    ║ v0.25.0     ║ Up to date            ║
║ tree-sitter-zig║ main        ║ Needs update          ║
╚════════════════╩═════════════╩═══════════════════════╝
```

1. **Parse deps.zon**: Load dependency configuration
2. **Read .version files**: Get current installed versions
3. **Check remote versions**: Query Git repositories for latest versions
4. **Compare and report**: Show status with colored output

#### Update Process (`zz deps --update`)

1. **Acquire lock**: Prevent concurrent updates using PID-based locking
2. **Backup current state**: Create backup of existing dependencies
3. **Clone/fetch repositories**: Get latest code from Git
4. **Apply filters**: Use include/exclude patterns from config
5. **Atomic replacement**: Replace old with new in single operation
6. **Update .version files**: Record new versions and metadata
7. **Verify installation**: Ensure all files properly installed
8. **Release lock**: Allow future operations

#### Error Recovery

- **Failed updates**: Automatic rollback to previous state
- **Interrupted operations**: Lock cleanup and state recovery
- **Network failures**: Graceful handling with clear error messages
- **Disk space issues**: Cleanup temporary files and report clearly

### Integration with Build System

The dependency system integrates seamlessly with the Zig build system:

```zig
// build.zig uses vendored dependencies
const tree_sitter = b.addStaticLibrary(.{
    .name = "tree-sitter",
    .target = target,
    .optimize = optimize,
});
tree_sitter.addCSourceFiles(.{
    .files = &.{"deps/tree-sitter/lib/src/lib.c"},
    .flags = &.{"-std=c11"},
});
tree_sitter.addIncludePath(.{ .path = "deps/tree-sitter/lib/include" });
```

### Testing with Mock Filesystem

The dependency system uses filesystem abstraction enabling:

- **Deterministic tests**: Mock filesystem for reproducible testing
- **CI/CD integration**: Tests run without network dependencies
- **Error condition testing**: Simulate disk full, permission errors
- **Performance testing**: Measure operations without real I/O

### Memory Management

The system follows Zig best practices:

- **RAII patterns**: Automatic cleanup with defer statements
- **Arena allocators**: Temporary allocations during operations
- **Proper ownership**: Clear memory ownership throughout
- **Leak detection**: All allocations properly tracked and freed

### Future Enhancements

The dependency system is designed for extensibility:

- **Parallel updates**: Multiple dependencies updated concurrently
- **Delta updates**: Only update changed files
- **Signature verification**: Verify dependency integrity
- **Local mirrors**: Support for internal dependency mirrors
- **Custom hooks**: Pre/post update scripts for complex dependencies

See [docs/deps.md](../docs/deps.md) for complete architecture details and usage examples.