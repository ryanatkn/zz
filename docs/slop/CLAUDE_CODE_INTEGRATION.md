# Claude Code Integration Guide

## Overview

`zz` is designed as a native Claude Code utility, providing secure, high-performance commands that enhance AI-assisted development workflows. This document outlines the integration strategy, best practices, and advanced usage patterns.

## Integration Philosophy

### AI-First Design
`zz` commands are optimized for AI consumption and human oversight:
- **Structured output** for LLM processing
- **Semantic markup** for context preservation  
- **Consistent formats** across all commands
- **Error messages** that suggest corrective actions

### Security-Conscious Integration
Every command is designed for safe AI access:
- **Read-only by default** - No destructive operations without explicit flags
- **Input validation** - Comprehensive sanitization of all inputs
- **Resource limits** - Bounded execution time and memory usage
- **Audit trails** - All operations are logged for security review

## Current Claude Code Configuration

### Basic Integration (`.claude/config.json`)
```json
{
    "tools": {
        "bash": {
            "allowedCommands": [
                "rg:*",
                "zz:*"
            ]
        }
    }
}
```

### Enhanced Security Configuration
```json
{
    "tools": {
        "bash": {
            "allowedCommands": [
                "rg:*",
                "zz:tree",
                "zz:prompt:*",
                "zz:benchmark:--format=*",
                "zz:gather:*",
                "zz:analyze:security"
            ],
            "blockedCommands": [
                "zz:*:--unsafe",
                "zz:*:--execute", 
                "zz:*:--modify"
            ],
            "timeoutMs": 30000,
            "maxConcurrent": 3
        }
    },
    "ai": {
        "enhancedErrorHandling": true,
        "commandSuggestions": true,
        "outputOptimization": "llm-friendly"
    }
}
```

## Command Usage Patterns for Claude Code

### Information Gathering Workflows

#### Project Structure Analysis
```bash
# Get comprehensive project overview
zz tree --format=tree                    # Visual structure
zz tree --format=list | head -20         # Flat list for processing

# Understand codebase scope
zz prompt "src/**/*.zig" --prepend="This project structure:"
```

#### Pattern Discovery and Analysis  
```bash
# Find specific patterns across codebase
zz gather "error handling" --context=patterns --format=markdown
zz gather "TODO|FIXME|XXX" --context=issues --scope=src/

# Analyze dependencies and relationships
zz gather imports --context=dependencies --depth=3 --format=json
```

#### Performance Investigation
```bash
# Current performance baseline
zz benchmark --format=pretty

# Compare with historical data
zz benchmark --baseline=benchmarks/baseline.md --format=markdown
```

### LLM-Optimized Output Patterns

#### Structured Code Aggregation
```bash
# Generate comprehensive context for LLM
zz prompt "src/**/*.zig" \
    --prepend="# Zig Codebase Analysis" \
    --append="Please analyze this codebase for:"

# Focused analysis on specific components
zz prompt "src/tree/**/*.zig" \
    --prepend="# Tree Module Analysis" \
    --append="Focus on performance optimizations"
```

#### Documentation Generation Context
```bash
# Gather all public APIs
zz gather "pub fn|pub const|pub struct" \
    --context=functions \
    --format=markdown \
    --scope=src/

# Extract configuration patterns
zz gather "Config|config|\.zon" \
    --context=config \
    --format=structured
```

### AI-Assisted Development Workflows

#### Code Review Preparation
```bash
# Generate review context
zz prompt "$(git diff --name-only)" \
    --prepend="# Code Review Context" \
    --append="Please review these changes for:"

# Performance impact analysis
zz benchmark --only=affected-modules --compare-baseline
```

#### Feature Implementation Context
```bash
# Gather related patterns before implementing new features
zz gather "similar_feature_pattern" \
    --context=implementations \
    --format=examples

# Understand current architecture
zz prompt "src/lib/**/*.zig" \
    --prepend="# Current Architecture" \
    --append="I want to add a new feature that:"
```

## Advanced Integration Patterns

### Multi-Command Workflows

#### Comprehensive Codebase Analysis
```bash
# Step 1: Structure overview
echo "## Project Structure" && zz tree --format=tree

# Step 2: Key components  
echo "## Core Modules" && zz prompt "src/*/main.zig"

# Step 3: Performance characteristics
echo "## Performance Profile" && zz benchmark --format=pretty

# Step 4: Technical debt analysis
echo "## Technical Debt" && zz gather "TODO|FIXME" --context=issues
```

#### Security Review Workflow
```bash
# Security-focused analysis
zz gather "password|secret|key|token" \
    --context=security \
    --format=audit

zz analyze security \
    --rules=owasp \
    --scope=src/ \
    --format=report
```

### Claude Code Automation Patterns

#### Smart Error Recovery
When commands fail, Claude Code can automatically suggest alternatives:

```bash
# If this fails:
zz prompt "nonexistent/**/*.zig"

# Claude suggests:
zz tree --format=list | grep "\.zig$" | head -10  # Find actual Zig files
zz prompt "$(find . -name '*.zig' | head -5)"     # Alternative pattern
```

#### Context-Aware Command Selection
Claude Code can choose optimal commands based on context:

```bash
# For documentation tasks:
zz gather "pub fn" --context=api --format=docs

# For debugging:
zz gather "error|fail|panic" --context=issues --format=debug

# For performance work:
zz benchmark --include=relevant-modules --format=analysis
```

## Output Format Optimization

### LLM-Friendly Formats

#### Markdown with Semantic Structure
```markdown
# Project Analysis

## Structure
<File path="src/main.zig">
```zig
pub fn main() !void {
    // Implementation
}
```
</File>

## Performance Characteristics
| Metric | Value | Baseline | Change |
|--------|-------|----------|---------|
| Path Operations | 47μs | 52μs | -9.6% |
```

#### JSON for Programmatic Processing
```json
{
    "analysis_type": "codebase_overview",
    "timestamp": "2024-01-15T10:30:00Z",
    "files": [
        {
            "path": "src/main.zig",
            "type": "source",
            "size": 1024,
            "content": "...",
            "metadata": {
                "functions": ["main"],
                "imports": ["std"]
            }
        }
    ],
    "summary": {
        "total_files": 42,
        "total_lines": 5280,
        "languages": ["zig"]
    }
}
```

### Error Message Enhancement for AI

#### Before (Standard Error)
```
Error: Pattern '*.nonexistent' matched no files
```

#### After (AI-Enhanced Error)
```
Error: Pattern '*.nonexistent' matched no files

Suggestions:
- Check available file extensions: zz tree --format=list | grep -o '\.[^.]*$' | sort -u
- Use broader pattern: zz prompt "*" --allow-empty-glob
- List directory contents: zz tree

Similar patterns that might work:
- *.zig (found 45 files)
- *.md (found 12 files)
- *.json (found 3 files)
```

## Performance Optimization for AI Workflows

### Response Time Targets
- **Small projects** (<1K files): <100ms
- **Medium projects** (1K-10K files): <1s  
- **Large projects** (10K+ files): <10s with progress

### Memory Efficiency
- **Streaming output** for large results
- **Chunked processing** for massive codebases
- **Incremental updates** for repeated operations

### Caching Strategy
```zig
// Intelligent caching for repeated AI queries
pub const AIOptimizedCache = struct {
    // Cache frequently accessed file patterns
    pattern_cache: PatternCache,
    
    // Cache analysis results for unchanged files
    analysis_cache: AnalysisCache,
    
    // Cache structured output formats
    format_cache: FormatCache,
};
```

## Future Claude Code Enhancements

### Planned Integration Features

#### Smart Command Completion
```bash
# AI suggests next logical command based on context
$ zz tree
# AI: "Would you like to generate a prompt from these files? Try: zz prompt 'src/**/*.zig'"

$ zz benchmark
# AI: "Performance looks good! To analyze specific bottlenecks: zz analyze performance --hotspots"
```

#### Context-Aware Error Recovery
```bash
# AI automatically suggests fixes for common issues
$ zz prompt "*.typo"
# AI: "No files found. Did you mean: zz prompt '*.zig' (45 files available)?"

$ zz gather "nonexistent_pattern"  
# AI: "Pattern not found. Analyzing codebase for similar patterns..."
# AI: "Found related patterns: error_handling, exception_handling, failure_modes"
```

#### Interactive Workflow Guidance
```bash
# AI guides through complex workflows
$ zz analyze security
# AI: "Security analysis complete. Next steps:"
# AI: "1. Review findings: zz gather 'security_issues' --format=detailed"
# AI: "2. Generate fix recommendations: zz suggest security-fixes"
# AI: "3. Validate fixes: zz validate security --rules=updated"
```

### Advanced AI Integration (Future)

#### Semantic Understanding
- **Intent recognition** from natural language queries
- **Context preservation** across command sequences  
- **Adaptive output formatting** based on AI model preferences

#### Collaborative Intelligence
- **AI-suggested command combinations** for complex tasks
- **Workflow learning** from repeated patterns
- **Predictive caching** based on AI usage patterns

## Best Practices for Claude Code Users

### Command Composition
```bash
# Good: Clear, focused commands
zz tree src/ 2                          # Specific scope and depth
zz prompt "src/cli/*.zig" --prepend="CLI module analysis:"

# Better: Composed workflows
zz tree --format=list | grep "\.zig$" | head -20 | xargs zz prompt
```

### Error Handling
```bash
# Graceful degradation
zz prompt "*.zig" || zz tree --format=list | grep "\.zig$" | head -5

# Informative alternatives
zz gather "pattern" --context=strict || zz gather "pattern" --context=fuzzy
```

### Performance Awareness
```bash
# Scope limitation for large projects
zz prompt "src/**/*.zig" --max-files=100

# Progress indication for long operations
zz analyze dependencies --progress --timeout=30s
```

This integration guide ensures that `zz` provides maximum value in Claude Code environments while maintaining security, performance, and usability standards. Every feature is designed to enhance AI-assisted development workflows while preserving human control and oversight.