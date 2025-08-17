# Configuration System

> ⚠️ AI slop code and docs, is unstable and full of lies

## Architecture

**Modular Configuration Architecture:**
- **Root-level config** in `zz.zon` - Single source of truth for cross-cutting concerns
- **`src/config/`** - Modular configuration system with clean separation of concerns:
  - `shared.zig` - Core types and SharedConfig structure  
  - `zon.zig` - ZON file loading with integrated configuration resolution
  - `resolver.zig` - Pattern resolution with defaults and custom patterns
- **`src/patterns/`** - High-performance unified pattern matching engine:
  - `matcher.zig` - Optimized pattern matching with fast/slow paths (90/10 split)
  - `gitignore.zig` - Stateless gitignore pattern logic
- **`src/config.zig`** - Clean public API facade for backward compatibility
- **Both tree and prompt modules** use the same underlying configuration system

## Configuration Format

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
    
    // Gitignore support: true (default) respects .gitignore files, false disables
    .respect_gitignore = true,
    
    // Command-specific overrides (optional)
    .tree = .{
        // Tree-specific settings go here if needed in future
    },
    
    .prompt = .{
        // Prompt-specific settings go here if needed in future
    },
    
    .format = .{
        // Format-specific settings (optional)
        .indent_size = 4,
        .indent_style = "space", // or "tab"
        .line_width = 100,
        .trailing_comma = false, // for JSON
        .sort_keys = false,       // for JSON
    },
}
```

## Pattern Resolution

- **"extend" mode:** Combines built-in defaults with your custom patterns
- **Custom array mode:** Use only your specified patterns, no defaults
- **Safe matching:** Exact path component matching prevents leaky substring matches
- **Default ignored patterns:** `.git`, `node_modules`, `.zig-cache`, `zig-out`, build directories, etc.
- **Default hidden files:** `.DS_Store`, `Thumbs.db`
- **Gitignore integration:** Automatically reads and applies `.gitignore` patterns by default
  - Files matching gitignore patterns are completely hidden (like `git ls-files` behavior)  
  - Directories matching gitignore patterns show as `[...]`
  - Use `--no-gitignore` flag to disable gitignore filtering

## Cross-module DRY Helpers

- `shouldIgnorePath()` - Shared ignore logic for both tree and prompt
- `shouldHideFile()` - Shared file hiding logic  
- `handleSymlink()` - Shared symlink behavior

## Command-line Override

Command-line arguments always take precedence over configuration file settings. For example:
- `--no-gitignore` overrides `respect_gitignore = true`
- `--follow-symlinks` overrides `symlink_behavior = "skip"`
- Explicit ignore patterns via CLI override configured patterns

## Loading Order

1. Built-in defaults (if `base_patterns = "extend"`)
2. User configuration from `zz.zon`
3. Command-specific overrides from `zz.zon`
4. Command-line arguments (highest priority)