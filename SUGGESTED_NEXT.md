# Development Roadmap

## Context

Parser reliability has been restored, error handling enhanced, and test quality improved. The codebase now has 100% parser functionality across all supported languages with meaningful error messages at critical touchpoints. Code formatting capabilities have been added with language-aware pretty printing. The foundation is solid for advancing toward real tree-sitter AST integration.

## Recently Completed ✅

- **Code Formatter Implementation** - Language-aware pretty printing for JSON, CSS, HTML, Zig
- **Parser Simple Extraction Fixed** - All languages now correctly extract content based on flags
- **Enhanced Error Messages** - Deployed ErrorHelpers in 5+ critical user touchpoints
- **Test Quality Improved** - Tests validate actual extraction content vs crash testing
- **Filesystem Import Standardization** - Core modules updated (10 test files remain)

## Immediate Priorities

### 1. Complete Real Tree-sitter Integration
**Impact:** High | **Effort:** High
- Replace mock AST with actual tree-sitter node wrappers
- Infrastructure exists in `ast.zig`, needs real implementation
- Enable true semantic analysis beyond text matching
- Enhance formatter quality with proper AST-based formatting
- Current: Simple extraction works, AST extraction is mocked

### 2. Formatter Enhancements
**Impact:** High | **Effort:** Medium
- Fix memory leak in glob expansion
- Add configuration support via `zz.zon`
- Implement TypeScript formatter with tree-sitter
- Add Python formatter (high demand)
- Performance optimization for large files

### 3. Integration Testing Suite
**Impact:** High | **Effort:** Medium
- End-to-end workflow validation
- Real-world usage patterns
- Command composition verification
- Performance regression detection
- Formatter validation tests

### 4. Complete Filesystem Import Migration
**Impact:** Low | **Effort:** Low
- 10 test files still use old `filesystem.zig` imports
- Update to `filesystem/interface.zig` for consistency
- Simple mechanical refactor

### 5. Performance Profiling & Optimization
**Impact:** High | **Effort:** Medium
- Profile with real-world data sets
- Target hot paths in traversal and matching
- Optimize parser extraction paths
- Optimize formatter performance
- Memory pool tuning (current: 11μs, target: 8μs)

### 6. Async I/O Preparation
**Impact:** High | **Effort:** Medium
- Extend parameterized I/O patterns
- Prepare for Zig 0.15's async implementation
- Focus on parallel file processing
- Enable parallel formatting

## Near-term Goals

### 7. Language Grammar Expansion
**Impact:** High | **Effort:** Medium
- Add Python grammar and formatter (high demand)
- Add Rust grammar and formatter (systems programming)
- Add Go grammar and formatter (cloud native)
- Leverage vendored tree-sitter infrastructure

### 8. Formatter Configuration System
**Impact:** Medium | **Effort:** Low
- Extend `zz.zon` for format preferences
- Per-project formatting rules
- Language-specific options
- Editor integration support

### 9. Centralized Argument Parsing
**Impact:** Medium | **Effort:** Medium
- Consolidate module-specific parsing
- Leverage existing `args.zig` infrastructure
- Improve consistency across commands

### 10. Shell Completions
**Impact:** Medium | **Effort:** Low
- Bash completion script
- Zsh completion script
- Fish completion script
- Auto-generate from command definitions

### 11. Incremental Processing Enhancement
**Impact:** High | **Effort:** Medium
- Leverage FileTracker for change detection
- Implement proper AST cache invalidation
- Add file watching capability
- Cache formatted files for --check mode

### 12. Documentation Consolidation
**Impact:** Medium | **Effort:** Low
- Create comprehensive user guide
- Extract API documentation
- Module-specific READMEs
- Performance tuning guide
- Formatter style guide

## Long-term Considerations

### Advanced Analysis Features
- Call graph visualization
- Dependency graph generation
- Code complexity metrics
- Security vulnerability scanning
- Format enforcement in CI/CD

### Build System Evolution
- Cross-compilation support
- Package manager integration
- Binary distribution strategy
- CI/CD optimization
- Pre-commit hooks for formatting

### Developer Experience
- LSP server for editor integration
- Interactive configuration wizard
- Plugin architecture
- Custom language support API
- Format-on-save integration

### Community Infrastructure
- Language grammar registry
- Pattern library marketplace
- Configuration sharing platform
- Performance benchmark suite
- Formatter style presets

## Performance Targets

Current baselines (Release mode, 2025-08-13):
- Path operations: 11μs (target: sub-10μs)
- String pooling: 11ns (maintained) ✅
- Memory pools: 11μs (target: 8μs)
- Glob patterns: 4ns (maintained) ✅
- Code extraction: 21μs (target: 15μs with real AST)
- Parser simple extraction: ~5μs (achieved) ✅
- JSON formatting: ~50μs for 1KB file (target: 30μs)
- CSS formatting: ~40μs for 1KB file (target: 25μs)

## Engineering Philosophy

### Core Principles
- Performance is non-negotiable
- Every abstraction must justify its cost
- POSIX-first, cross-platform never
- Measure, optimize, verify

### Quality Metrics
- Zero performance regressions
- 100% parser functionality ✅
- Meaningful error messages ✅
- Comprehensive test validation ✅
- Consistent formatting output ✅

### On Reliability
With parser extraction now fully functional, error handling enhanced, and formatting capabilities added, the focus shifts to leveraging this reliable foundation for advanced features. The mock AST infrastructure awaits real tree-sitter integration to unlock semantic analysis capabilities and improve formatting quality.

## Next Sprint Focus

**Recommended sequence:**
1. Fix formatter memory leak (quick win)
2. Add formatter configuration support (user value)
3. Complete filesystem import migration (consistency)
4. Build integration test suite (validate current state)
5. Begin real tree-sitter integration (high value)
6. Add Python language support with formatter (user demand)
7. Profile and optimize hot paths (performance)

## Technical Debt

### Addressed ✅
- Parser simple extraction (fixed)
- Error message quality (enhanced)
- Test validation depth (improved)
- Core module imports (80% complete)
- Basic formatting implementation (completed)

### Remaining
- Mock AST to real tree-sitter
- Test file import consistency
- Centralized argument parsing
- Full incremental processing
- Formatter memory leak
- TypeScript/Svelte formatter implementation
- Format configuration system

## Formatter Roadmap

### Phase 1 (Completed) ✅
- Core infrastructure
- JSON, CSS, HTML formatters
- CLI integration
- Basic documentation

### Phase 2 (Next)
- Fix memory leak
- Configuration support
- TypeScript formatter with AST
- Python formatter
- Performance optimization

### Phase 3 (Future)
- Rust, Go formatters
- Format enforcement tools
- Editor integrations
- Style preset library

---

*Performance is a feature. Simplicity is a design goal. Every cycle counts.*