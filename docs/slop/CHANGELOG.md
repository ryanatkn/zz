# Changelog

All notable changes to zz will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project will adhere to [Semantic Versioning](https://semver.org/spec/v2.0.0.html) after v1.0.0.

## [Unreleased]

### Added
- Color-enhanced benchmark output with progress bars
- Human-readable time units (ns, μs, ms, s) in benchmarks
- Comprehensive documentation suite:
  - ARCHITECTURE.md - System design and module relationships
  - CONTRIBUTING.md - Contribution guidelines
  - PERFORMANCE.md - Optimization guide
  - DX_SUGGESTIONS.md - Developer experience improvements
  - BENCHMARK_PROPOSALS.md - Future benchmark plans
  - TROUBLESHOOTING.md - Common issues and solutions
  - PATTERNS.md - Usage patterns and recipes
  - ROADMAP.md - Future direction and features
  - TESTING.md - Testing guide
  - FAQ.md - Frequently asked questions
  - CHANGELOG.md - This file

### Changed
- Benchmark system now outputs to stdout (Unix philosophy)
- Benchmark regression threshold increased to 20% for Debug builds
- Performance baselines updated with actual measurements

### Fixed
- Benchmark format string errors with slices
- Progress bar rendering with ASCII characters

## [0.1.0] - 2024-01-15

### Added
- **Tree command**: Fast directory visualization
  - Tree and list output formats
  - Gitignore support
  - Configurable ignore patterns
  - Depth limiting
  - Multiple output formats

- **Prompt command**: LLM prompt generation
  - Glob pattern support with 40-60% optimization
  - Smart code fence detection
  - Directory traversal
  - File deduplication
  - Prepend/append text options

- **Benchmark command**: Performance measurement
  - Markdown, JSON, CSV output formats
  - Baseline comparison
  - Regression detection
  - Auto-scaling iterations

- **Core optimizations**:
  - 20-30% faster path operations
  - String interning with 15-25% memory reduction
  - Memory pool allocators
  - Fast-path pattern matching
  - Early directory skipping

- **Infrastructure**:
  - Filesystem abstraction layer
  - Mock filesystem for testing
  - Unified pattern matching engine
  - Arena allocators
  - 190+ comprehensive tests

### Performance Metrics
- Path operations: ~47μs per operation
- String pooling: ~145ns per operation
- Memory pools: ~50μs per allocation
- Glob patterns: ~25ns per match
- Tree rendering: <50ms for 1000 files

## [0.0.1] - 2024-01-01 (Internal)

### Initial Implementation
- Basic tree visualization
- Simple prompt generation
- Initial benchmark framework
- Project structure setup
- Build system configuration

---

## Version History Summary

| Version | Date | Highlights |
|---------|------|------------|
| 0.1.0 | 2024-01-15 | First public release |
| 0.0.1 | 2024-01-01 | Internal prototype |

## Versioning Policy

### Before v1.0.0
- Minor versions (0.x.0) may include breaking changes
- Patch versions (0.x.y) for bug fixes only
- No compatibility guarantees

### After v1.0.0
- Follow Semantic Versioning strictly
- Major versions for breaking changes
- Minor versions for new features
- Patch versions for bug fixes

## Deprecation Policy

### Before v1.0.0
- Features may be removed without notice
- No deprecation warnings required

### After v1.0.0
- Deprecation warnings for one minor version
- Removal in next major version
- Migration guide provided

## Release Process

1. **Development**
   - Features developed on feature branches
   - Merged to main after review
   - Continuous integration runs tests

2. **Release Preparation**
   - Update version in build.zig.zon
   - Update CHANGELOG.md
   - Run full test suite
   - Run benchmarks, check for regressions

3. **Release**
   - Tag release: `git tag v0.x.y`
   - Push tag: `git push origin v0.x.y`
   - Create GitHub release with notes

4. **Post-Release**
   - Update documentation if needed
   - Announce in discussions
   - Monitor for issues

## How to Read This Changelog

### Change Types
- **Added**: New features
- **Changed**: Changes in existing functionality
- **Deprecated**: Soon-to-be removed features
- **Removed**: Removed features
- **Fixed**: Bug fixes
- **Security**: Vulnerability fixes

### Version Links
- **[Unreleased]**: Changes in main branch not yet released
- **[0.1.0]**: Specific version release

### Performance Notes
Performance improvements are noted with percentages:
- **Relative**: "20% faster than stdlib"
- **Absolute**: "50μs per operation"
- **Memory**: "15% reduction"

## Contributing to Changelog

When contributing, add your changes to the [Unreleased] section:

```markdown
### Added
- Your new feature description

### Fixed
- Bug you fixed with issue number (#123)
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for more details.