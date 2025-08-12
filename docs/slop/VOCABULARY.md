# Natural Language Programming Vocabulary

## Executive Summary

This vocabulary defines terms that facilitate efficient communication between humans and AI in natural language programming environments. These terms are designed to convey complex intentions with minimal cognitive overhead, supporting the development of `zz` and related CLI tools.

## Core Action Verbs

### `gather`
**Meaning:** Intelligently collect and aggregate information from across a codebase  
**Context:** Information retrieval, pattern discovery, context building for LLMs  
**Examples:**
- "gather all error handling patterns"
- "gather TODO items across the project"
- "gather import dependencies"

**Implementation in zz:** `zz gather [pattern] [--context=TYPE]`

### `analyze`
**Meaning:** Apply structured examination to understand properties, relationships, or quality  
**Context:** Static analysis, quality assessment, security review  
**Examples:**
- "analyze security vulnerabilities"
- "analyze performance bottlenecks"
- "analyze code complexity"

**Implementation in zz:** `zz analyze [target] [--type=ANALYSIS]`

### `trace`
**Meaning:** Follow execution paths, data flow, or dependency chains  
**Context:** Understanding system behavior, debugging, architecture visualization  
**Examples:**
- "trace function call chains"
- "trace data transformations"
- "trace circular dependencies"

**Implementation in zz:** `zz trace [operation] [--format=FORMAT]`

### `summarize`
**Meaning:** Create concise, structured overviews appropriate for specific audiences  
**Context:** Documentation generation, onboarding, LLM context preparation  
**Examples:**
- "summarize this module for an LLM"
- "summarize recent changes"
- "summarize architectural decisions"

**Implementation in zz:** `zz summarize [scope] [--for=AUDIENCE]`

### `validate`
**Meaning:** Check conformance against rules, standards, or best practices  
**Context:** Quality assurance, security compliance, architectural constraints  
**Examples:**
- "validate security patterns"
- "validate code style"
- "validate architectural boundaries"

**Implementation in zz:** `zz validate [target] [--rules=RULESET]`

### `extract`
**Meaning:** Transform and export specific information into different formats  
**Context:** Documentation generation, API specification, data transformation  
**Examples:**
- "extract API endpoints to OpenAPI spec"
- "extract type definitions"
- "extract configuration schema"

**Implementation in zz:** `zz extract [what] [--to=FORMAT]`

### `diff`
**Meaning:** Compare and highlight differences beyond traditional textual comparison  
**Context:** Semantic analysis, impact assessment, change review  
**Examples:**
- "diff semantic changes between commits"
- "diff configuration impact"
- "diff behavioral differences"

**Implementation in zz:** `zz diff [old] [new] [--semantic]`

### `reason`
**Meaning:** Apply AI-powered analysis to answer complex questions about code  
**Context:** AI-assisted development, complex problem solving, architectural guidance  
**Examples:**
- "reason about performance implications"
- "reason about security risks"
- "reason about refactoring opportunities"

**Implementation in zz:** `zz reason [query] [--scope=SCOPE]` (AI integration required)

### `suggest`
**Meaning:** Provide intelligent recommendations based on analysis  
**Context:** Code improvement, optimization, best practices  
**Examples:**
- "suggest performance optimizations"
- "suggest test improvements"
- "suggest architectural changes"

**Implementation in zz:** `zz suggest [improvement] [--context=CONTEXT]`

## Context Qualifiers

### Scope Qualifiers
- **`project`** - Entire codebase scope
- **`module`** - Single module or package
- **`component`** - Functional component or subsystem
- **`function`** - Individual function or method
- **`file`** - Single file scope

### Analysis Types
- **`security`** - Security-focused analysis
- **`performance`** - Performance and optimization focus
- **`structure`** - Architectural and organizational focus
- **`patterns`** - Design patterns and code idioms
- **`dependencies`** - Dependency relationships and management
- **`coverage`** - Test coverage and quality
- **`complexity`** - Code complexity and maintainability

### Output Audiences
- **`llm`** - Optimized for Large Language Model consumption
- **`human`** - Optimized for human readability
- **`machine`** - Structured data for programmatic use
- **`docs`** - Documentation-ready format

## Pattern Language

### Glob-Style Patterns
Enhanced glob patterns for precise targeting:
```bash
"error handling"           # Text-based pattern matching
"*.{zig,c,h}"             # File extension patterns  
"src/**/*.test.zig"       # Recursive test file patterns
"TODO|FIXME|XXX"          # Multi-pattern matching
"[Pp]ublic.*function"     # Regex-style patterns
```

### Context Patterns
```bash
--context=functions       # Focus on function definitions
--context=types          # Focus on type definitions
--context=interfaces     # Focus on interface definitions
--context=tests          # Focus on test code
--context=docs           # Focus on documentation
--context=config         # Focus on configuration
```

### Format Patterns
```bash
--format=markdown        # Human-readable markdown
--format=json           # Machine-readable JSON
--format=yaml           # Configuration-friendly YAML
--format=mermaid        # Diagram generation
--format=csv            # Spreadsheet analysis
--format=openapi        # API specification
```

## Semantic Operators

### Logical Combinators
- **`AND`** - Intersection of conditions (default)
- **`OR`** - Union of conditions
- **`NOT`** - Exclusion of conditions
- **`XOR`** - Exclusive conditions

**Examples:**
```bash
zz gather "error AND handling" --context=functions
zz gather "TODO OR FIXME" --context=issues
zz gather "public NOT test" --context=functions
```

### Temporal Qualifiers
- **`since=COMMIT`** - Changes since specific commit
- **`until=COMMIT`** - Changes until specific commit
- **`between=COMMIT1..COMMIT2`** - Changes in range
- **`recent=TIMESPAN`** - Recent changes (e.g., "7d", "2w", "1m")

### Depth Qualifiers
- **`--depth=N`** - Limit traversal depth
- **`--shallow`** - Single level only
- **`--deep`** - Full recursive traversal
- **`--infinite`** - No depth limits

## Command Composition Patterns

### Pipeline Patterns
```bash
# Sequential analysis
zz gather "error handling" | zz analyze security | zz summarize --for=llm

# Multi-stage filtering
zz gather functions --context=public | zz validate --rules=api-design

# Cross-reference analysis
zz trace dependencies --circular | zz suggest refactoring --context=architecture
```

### Conditional Execution
```bash
# Execute only if validation passes
zz validate security && zz gather vulnerabilities --format=report

# Execute with fallback
zz analyze performance --baseline=old.json || zz benchmark --create-baseline
```

### Parallel Composition
```bash
# Multiple analyses in parallel
zz gather {functions,types,interfaces} --parallel --merge-output

# Comparative analysis
zz diff --semantic HEAD~1 HEAD & zz analyze performance --compare-baseline &
```

## Candidate CLI Tools

### Complementary CLIs for the zz Ecosystem

#### `pp` (Pattern Processor)
Advanced pattern matching and transformation tool:
```bash
pp match "function.*error" --transform=markdown --context-lines=3
pp replace "TODO" "DONE" --dry-run --scope=src/
pp extract patterns --from=codebase --to=documentation
```

#### `mm` (Markdown Manager)
Markdown-specific processing for documentation workflows:
```bash
mm toc README.md --auto-update               # Table of contents generation
mm link-check docs/ --fix-broken             # Link validation and repair
mm merge sections --from=multiple --to=single # Documentation assembly
```

#### `ss` (Semantic Search)
AI-powered semantic search across codebases:
```bash
ss find "authentication logic" --semantic    # Semantic code search
ss similar --to=function --within=project    # Find similar implementations
ss concepts --extract --from=codebase        # Extract conceptual themes
```

#### `tt` (Tree Tools)
Extended tree visualization and manipulation:
```bash
tt compare dir1/ dir2/ --semantic            # Semantic directory comparison
tt layout optimize --for=navigation          # Optimize directory structure
tt permissions audit --recursive             # Permission analysis
```

#### `ff` (File Flow)
File and data transformation pipeline tool:
```bash
ff transform json --to=yaml --validate       # Format transformation
ff batch rename --pattern="*.old" --to="*.backup" # Batch operations
ff content analyze --type=auto --summarize   # Content analysis
```

## Meta-Language Constructs

### Intent Markers
Prefix markers that clarify intention:
- **`?`** - Query/question ("? why is this slow")
- **`!`** - Assertion/command ("! optimize this function")
- **`@`** - Reference/mention ("@ see authentication module")
- **`#`** - Tag/category ("# performance # security")
- **`~`** - Approximation/similarity ("~ find similar patterns")

### Scope Indicators
- **`./`** - Current directory scope
- **`../`** - Parent directory scope
- **`/`** - Root scope
- **`~`** - Home/project scope
- **`*`** - Wildcard scope

### Priority Markers
- **`+++`** - Critical priority
- **`++`** - High priority
- **`+`** - Normal priority
- **`-`** - Low priority
- **`---`** - Deferred/backlog

## Usage Conventions

### Command Naming Philosophy
1. **Single character** for frequently used commands (`zz`)
2. **Verb-based** for actions (`gather`, `analyze`, `trace`)
3. **Noun-based** for targets (`functions`, `security`, `patterns`)
4. **Hyphenated** for compound concepts (`api-design`, `error-handling`)

### Argument Conventions
1. **Positional arguments** for primary targets
2. **Flags** for behavioral modifiers
3. **Options** for output formatting
4. **Patterns** for filtering and matching

### Output Conventions
1. **Structured data** for machine consumption
2. **Formatted text** for human consumption
3. **Progress indicators** for long-running operations
4. **Error messages** with suggestions and fixes

## Evolution Guidelines

### Adding New Terms
1. **Consistency** - New terms should follow established patterns
2. **Clarity** - Terms should be unambiguous in context
3. **Composability** - Terms should work well in combination
4. **Cultural Fit** - Terms should align with developer mental models

### Deprecation Process
1. **Mark deprecated** in documentation
2. **Provide migration path** to new term
3. **Maintain backward compatibility** for major version
4. **Remove** in next major version

This vocabulary serves as both a specification for `zz` command development and a reference for effective natural language programming communication. As the ecosystem evolves, these terms provide a stable foundation for human-AI collaboration in software development.