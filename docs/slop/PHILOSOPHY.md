# PHILOSOPHY.md

**The core beliefs that guide zz development**

## Unix Philosophy, Modern Execution

We believe in the Unix philosophy: small, composable tools that do one thing well. But we execute with modern discipline: comprehensive testing, type safety, and performance measurement.

```bash
# Unix way: compose simple tools
zz tree | grep ".zig" | wc -l

# Not: one tool trying to do everything  
zz tree --grep=".zig" --count --format=json --output=file.json
```

## Old-School Discipline, Modern Tools

### We embrace from C culture:
- Every byte matters
- Simplicity is elegance
- Measure, don't guess
- Clear code > clever code
- The stack is your friend

### We embrace from modern development:
- Type systems catch bugs
- Tests document behavior  
- Web UIs when appropriate
- LLMs as development tools
- Fast iteration over perfection

## Zero Dependencies, No Compromises

We write what we need. Every dependency is:
- Code we don't control
- Bugs we can't fix
- Performance we can't optimize
- Security we can't audit
- Builds that get slower

If the standard library doesn't have it and we can't write it in a day, we probably don't need it.

## Performance Is A Feature

Users feel performance more than they see features. We optimize for:
- Cold start time (terminal responsiveness)
- Memory efficiency (works on small VMs)
- Predictable latency (no surprises)
- Actual workloads (not synthetic benchmarks)

We measure in microseconds, not percentages.

## Modular, Not Monolithic

The core `zz` binary stays small. Future features live in separate binaries:
- `zz` - Core utilities everyone needs
- `zz-ts` - TypeScript parser for web developers
- `zz-llm` - LLM integration for AI workflows
- `zz-web` - Web framework tools

Each tool excellent at its purpose. Compose them as needed.

## Break Things To Improve Them

We don't carry baggage. When we find a better way:
- We break the old way
- We document the change
- We move forward

Your workflow might break. The tool will be better.

## Security Through Simplicity

Complex systems have complex vulnerabilities. We prefer:
- Read-only operations by default
- Explicit dangerous operations (`dangerously_*` functions)
- No network access except where essential
- No arbitrary code execution
- Clear capability boundaries

## No Marketing, No Noise

We don't need:
- Emoji in our output
- "Blazing fast" claims  
- GitHub star begging
- Conference-driven development
- Hype cycle chasing

We need:
- Tools that work
- Clear documentation
- Actual measurements
- Honest limitations

## The Test: Would We Use This?

Every feature must pass one test: would we use this ourselves, every day, in our actual work?

If the answer is no, we don't build it.

## The Anti-Goals

We explicitly DO NOT want to:
- Support Windows (POSIX is our home)
- Become a framework
- Add configuration for everything
- Chase market share
- Maximize GitHub stars
- Build what we don't need

## The End Goal

Fast, reliable, composable tools that respect the user's intelligence and time. Tools that feel inevitable, not clever. Tools that do their job and get out of the way.

We're not building the future of development tools. We're building good tools for today's work.

---

*"Perfection is achieved not when there is nothing more to add, but when there is nothing left to take away."*

*"Simplicity is the ultimate sophistication."*

*"Make it work, make it right, make it fast - in that order."*