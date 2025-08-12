# CLI Module - Command Interface System

Simple, functional command dispatch with decentralized argument parsing.

## Architecture

**Design Philosophy:** Simplicity over flexibility - each module handles its own argument parsing.

## Module Structure

- `main.zig` - Entry point, basic validation, command recognition
- `args.zig` - **Deprecated/unused** - centralized parsing exists but modules parse independently
- `command.zig` - Command enum with string conversion
- `help.zig` - Static help text display
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

**Static Display:** Hardcoded usage patterns for all commands
**Triggers:** No args, `help` command, unknown command

## Architectural Decisions

1. **Decentralized parsing** - Each module owns its argument logic
2. **Filesystem abstraction** - All commands receive interface for testability
3. **Simple dispatch** - Basic switch rather than registry/plugin system
4. **Static help** - Hardcoded rather than dynamic generation
5. **Mixed error strategy** - Pragmatic but inconsistent

## Test Coverage

✅ Command parsing, runner init, help dispatch, basic structure
❌ Edge cases, error propagation, integration, complex arguments

## Future Improvements

- Centralize argument parsing using existing `args.zig`
- Standardize error handling across modules
- Dynamic help generation from command definitions
- Command registry pattern for extensibility