# LLM Development Guidelines

This document outlines the development philosophy, coding standards, and guidelines for LLM assistants working on the zz project.

## Core Philosophy

### Performance First
- **Performance is a feature** - every cycle counts
- Always optimize for speed over convenience
- Benchmark performance impacts of changes
- Default to the fastest solution

### No Backwards Compatibility
- **Do not support backwards compatibility** unless explicitly asked
- Delete old code aggressively by default
- Never deprecate or preserve legacy code unless explicitly requested
- Always aim for the final, best solution

### Simplicity Over Complexity
- **Less is more** - avoid over-engineering
- When in doubt, choose the simple option
- Keep modules self-contained and focused
- Ask clarifying questions rather than assuming complexity

## Coding Standards

### Zig Style Guidelines

#### Language Preferences
- Write **idiomatic Zig**, taking more after C than C++
- This is a CLI utilities project - no graphics or game functionality
- Focus on clean, performant architecture

#### Module Patterns
- **Never re-export identifiers** from modules
- Do not use the facade pattern - it's considered a code smell
- Never re-export unless explicitly justified with a comment
- Keep modules self-contained with single responsibilities

#### Code Organization
- Address duplicated code and antipatterns immediately
- Leave `// TODO terse explanation` for unknowns and incomplete work
- Identify root causes in tests - don't cheat on test coverage

## Development Workflow

### Testing Requirements
- Test frequently with `zig build run` to ensure each step works
- Always include tests for new functionality
- Always include tests for newly handled edge cases
- Identify root causes in failing tests
- Leave `// TODO` comments if stumped by test failures

### Benchmarking
- Add and extend benchmarks when appropriate
- Measure performance impact of changes
- Compare against baseline performance

### Documentation
- Always update `./CLAUDE.md` and `./README.md`
- Keep documentation in sync with code changes
- Document performance characteristics
- Explain design decisions briefly

## Tool Preferences

### Search and Analysis
- **Always prefer `rg` (ripgrep)** over `grep` and `find`
- Claude Code is configured to prefer `rg` via `.claude/config.json`
- Use ripgrep for all text searching tasks
- Leverage ripgrep's performance advantages

### Build and Development
- Use `zig build` for all build tasks
- Prefer `zig build run -- <command>` for development
- Use `zig build test` with filters when needed

## Communication Guidelines

### Collaboration Approach
- **Push back** when you think you are correct
- Share understanding the developer might not have
- Ask clarifying questions when requirements are ambiguous
- Provide reasoning for technical decisions

### Problem Solving
- Identify root causes, not symptoms
- Propose solutions with performance implications
- Consider edge cases and error conditions
- Think about maintenance and future changes

## Project-Specific Rules

### What This Project Is
- Fast command-line utilities for POSIX systems
- Performance-optimized tools
- Clean, maintainable architecture
- Modular, self-contained components

### What This Project Is Not
- Not a graphics or game project
- Not concerned with Windows support
- Not maintaining backwards compatibility
- Not prioritizing convenience over performance

## Anti-Patterns to Avoid

### Module Anti-Patterns
- Facade pattern (unnecessary indirection)
- Re-exporting for convenience
- Circular dependencies
- God objects or modules

### Code Anti-Patterns
- Premature abstraction
- Over-engineering solutions
- Ignoring performance implications
- Copy-paste programming without understanding

### Testing Anti-Patterns
- Cheating on test coverage
- Testing implementation instead of behavior
- Ignoring flaky tests
- Not identifying root causes

## Decision Making

### When to Make Decisions
- Choose simple solution when uncertain
- Optimize for performance by default
- Delete rather than deprecate
- Refactor rather than patch

### When to Ask Questions
- Ambiguous requirements
- Performance vs functionality tradeoffs
- Architectural decisions with long-term impact
- Breaking changes to public APIs

## Performance Optimization Priorities

1. **Algorithm complexity** - O(n) vs O(n²)
2. **Memory allocation** - Minimize allocations
3. **Cache efficiency** - Data locality
4. **I/O operations** - Batch and buffer
5. **Parallelization** - When beneficial

## Code Quality Metrics

### Must Have
- Compiles without warnings
- Passes all tests
- No memory leaks
- Documented public APIs

### Should Have
- Benchmark comparisons
- Edge case handling
- Error messages that help users
- Consistent style

### Nice to Have
- Performance optimizations beyond requirements
- Additional test coverage
- Extended documentation
- Usage examples

## Final Reminders

- **Performance is top priority** - optimize for speed
- **Delete aggressively** - don't preserve old code
- **Test thoroughly** - ensure correctness
- **Document changes** - keep CLAUDE.md and README.md updated
- **Ask questions** - when in doubt, clarify requirements
- **Push back** - when you have better understanding

Remember: This project values performance, simplicity, and clean architecture above all else. Every decision should align with these core values.