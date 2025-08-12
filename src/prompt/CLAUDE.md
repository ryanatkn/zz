# Prompt Module - LLM Prompt Generation

LLM-optimized file aggregation with glob support and smart fencing.

## Module Structure

- `main.zig` - Prompt command entry point
- `builder.zig` - Core prompt building with filesystem abstraction
- `config.zig` - Prompt-specific configuration
- `fence.zig` - Smart fence detection for code blocks
- `glob.zig` - Glob pattern expansion with optimizations
- `test.zig` - Comprehensive test suite

## Key Features

- Advanced glob patterns with fast-path optimization
- Directory recursion with ignore pattern respect
- Smart code fence handling for nested blocks
- Automatic file deduplication
- Markdown output with semantic XML tags