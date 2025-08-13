# CLI Module - Command Interface System

Simple, functional command dispatch with decentralized argument parsing.

## Architecture

**Design Philosophy:** Simplicity over flexibility - each module handles its own argument parsing.

## Module Structure

- `main.zig` - Entry point, basic validation, command recognition
- `args.zig` - **Deprecated/unused** - centralized parsing exists but modules parse independently
- `command.zig` - Command enum with string conversion
- `help.zig` - Static help text display with detailed command options
- `runner.zig` - Command dispatch via switch statement
- `test.zig` - Basic smoke tests

## Command Flow

1. `main.zig:run()` - Parse system args with `std.process.argsAlloc()`
2. Validate arg count (≥2: program + command)
3. `Command.fromString()` - Convert string to enum
4. `Runner.init()` - Create with allocator + filesystem
5. `Runner.run()` - Switch dispatch to modules
6. Module `run()` - Each handles own arg parsing

## Key Data Structures

```zig
Command = enum { tree, prompt, benchmark, help };

Runner = struct {
    allocator: std.mem.Allocator,
    filesystem: FilesystemInterface,
};

ArgError = error{
    InvalidFlag, MissingValue, InvalidFormat, OutOfMemory
};
```

## Module Integration

**Standard Interface:**
```zig
pub fn run(allocator: Allocator, filesystem: FilesystemInterface, args: [][:0]const u8) !void
// Exception: benchmark doesn't need filesystem
```

**Direct Imports:** `tree.run()`, `prompt.run()`, `benchmark.run()`

## Error Handling

**Mixed Strategy:**
- Unknown commands: Print error + help, `std.process.exit(1)`
- Prompt module: Catches specific errors, custom exit codes
- Tree/Benchmark: Errors bubble up via `try`
- Broken pipe: Graceful handling for shell pipelines

## Help System

**Static Display:** Hardcoded usage patterns for all commands with comprehensive option documentation

**Help Modes:**
- **Brief Help (`-h`):** Concise command overview with basic syntax
- **Detailed Help (`--help`, `help`):** Full documentation with all options and examples

**Command Descriptions:**
- Tree: Directory visualization with format options
- Prompt: "Build LLM prompts with intelligent code extraction" (updated from "Build LLM prompts from files")
- Benchmark: Performance testing with multiple output formats

**Prompt Command Help Features:**
- **Standard Options:** `--prepend`, `--append`, `--allow-empty-glob`, `--allow-missing`
- **Extraction Flags Section:** 8 specialized code extraction options:
  - `--signatures`: Extract function/method signatures
  - `--types`: Extract type definitions  
  - `--docs`: Extract documentation comments
  - `--structure`: Extract code structure
  - `--imports`: Extract import statements
  - `--errors`: Extract error handling code
  - `--tests`: Extract test functions
  - `--full`: Extract complete source (default)

**Triggers:** 
- Brief help: `-h` flag, no args, unknown command
- Detailed help: `--help` flag, `help` command

## Architectural Decisions

1. **Decentralized parsing** - Each module owns its argument logic
2. **Filesystem abstraction** - All commands receive interface for testability
3. **Simple dispatch** - Basic switch rather than registry/plugin system
4. **Static help** - Hardcoded comprehensive help with detailed option documentation rather than dynamic generation
5. **Mixed error strategy** - Pragmatic but inconsistent

## Test Coverage

✓ Command parsing, runner init, help dispatch, basic structure
🞪 Edge cases, error propagation, integration, complex arguments

## Future Improvements

- Centralize argument parsing using existing `args.zig`
- Standardize error handling across modules
- Dynamic help generation from command definitions (current static help is comprehensive but hardcoded)
- Command registry pattern for extensibility
- Consider help text organization as extraction flags grow