# TASTE.md

**Design principles and aesthetic philosophy for zz**

## Core Philosophy

This project follows Unix philosophy: do one thing well, compose with other tools, output to stdout. We prioritize substance over flash, function over form.

We're old-school C developers at heart—every byte matters, simplicity is elegance, and the command line is home. But we're not nostalgic purists. We embrace modern web development (TypeScript, Svelte) and LLMs as powerful tools when they solve real problems. No compromises on UX or DX.

## Visual Aesthetics

### What We Want
- **Clean, minimal output** - Information density without clutter
- **Functional symbols** - `✓` for success, `⚠` for warnings, basic ASCII where possible
- **Subtle color coding** - Muted colors that convey meaning without screaming
- **Professional appearance** - Suitable for terminal environments and CI logs
- **Readable typography** - Clear hierarchy, proper spacing, consistent alignment

### What We Avoid
- **Attention-seeking language** - "Blazing fast" and "game-changing" are worse than emoji
- **Emoji decoration** - No 🚀 🎉 💯 or other social media nonsense
- **Excessive Unicode** - Stick to basic symbols that work everywhere
- **Background colors** - Keep terminals readable, use foreground only
- **Animated or flashy elements** - This isn't a game or marketing material
- **Trendy visual noise** - No gradients, shadows, or other eye candy

## Acceptable Symbols

**Core set (always appropriate):**
- `✓` - Simple check mark for success/improvement
- `⚠` - Warning triangle for regressions/issues  
- `?` - Question mark for unknown/new items
- `×` - Multiplication sign for errors/failures
- `-` - Hyphen for neutral/stable states
- `|` - Pipe for tables and structure
- `└` `├` `│` - Tree drawing characters

**Extended set (use sparingly):**
- `▉▊▋▌▍▎▏` - Block characters for progress bars only
- `↗` `↘` `→` - Direction arrows for trends (only when trend is meaningful)
- `≈` - Approximately equal for stable performance

## Color Palette

**Semantic colors only:**
- **Green** - Success, improvement, good status
- **Yellow** - Warnings, minor issues, caution
- **Red** - Errors, failures, critical issues  
- **Blue** - Information, headers, neutral emphasis
- **Gray** - Secondary information, dim content
- **Cyan** - New items, special states

**No gradients, no bright/flashy variants.**

## Text Conventions

- **Sentence case** - Not Title Case For Everything
- **Technical precision** - "~47μs per operation" not "20-30% faster"
- **Actual measurements** - Show the numbers, not percentage improvements
- **Consistent terminology** - Pick terms and stick with them
- **No marketing speak** - "optimized" not "blazing fast"
- **Avoid redundancy** - Don't say "successfully completed" just say "completed"
- **State facts** - "190 tests passing" not "✓ Comprehensive test coverage!"

### Exception: Security APIs
The ONE place we want attention-grabbing names:
```zig
fn dangerously_allow_path_traversal() void
fn unsafe_skip_validation() void
fn insecure_disable_sanitization() void
```
Make dangerous operations impossible to use accidentally.

## Examples

**Good benchmark output:**
```
✓ Path Joining        47μs  ████▊     (-2.1% vs baseline)
⚠ String Pool        155ns  ██▍       (+3.3% vs baseline)  
✓ Memory Pools        51μs  █████     (-0.8% vs baseline)
```

**Bad benchmark output:**
```
🚀 Path Joining BLAZED through tests! 💨 47μs ✨
⚠️🔥 String Pool is slightly slower 📈 155ns 
🎯 Memory Pools performed GREAT! 🎉 51μs 💪
```

## Architecture Philosophy

### Modular Binary Strategy
The core `zz` binary stays small and focused (< 5MB). Future features live in separate binaries or optional modules:
```
zz          # Core utility (tree, prompt, benchmark)
zz-ts       # TypeScript parser (future)
zz-llm      # LLM integration (future)
zz-web      # Web language tools (future)
```

This keeps the Unix philosophy (small, composable tools) while embracing modern needs.

### Integration Without Bloat
When we integrate with web tooling:
- Native performance for system operations
- WASM or separate processes for web features
- Clean API boundaries, not monolithic coupling
- Each tool excellent at its job

## Rationale

We're building tools for professionals who spend their days in terminals and IDEs. They need clear, actionable information presented efficiently. Visual noise distracts from the actual data and makes tools feel unserious.

The best CLI tools are those that get out of your way and let you focus on your work. A `✓` tells you everything you need to know about success. A rocket emoji tells you the developer wanted attention.

**We choose substance over spectacle.**

This isn't about being boring or resistant to change. We love modern tools—TypeScript's type system, Svelte's reactivity, LLMs' code understanding. But we integrate them thoughtfully, not frantically. Each tool should be excellent at its purpose, not mediocre at everything.

The old-school C ethos (simplicity, efficiency, clarity) combined with modern web excellence (great UX, powerful abstractions, AI assistance) creates tools that are both powerful and pleasant.

---

*"Perfection is achieved, not when there is nothing more to add, but when there is nothing left to take away." - Antoine de Saint-Exupéry*

*"Make it work, make it right, make it fast." - Kent Beck*